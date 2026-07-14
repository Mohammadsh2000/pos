import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'backup_encryption.dart';

class BackupManager {
  static final BackupManager instance = BackupManager._();
  BackupManager._();

  final DatabaseHelper _db = DatabaseHelper();
  final BackupEncryption _encryption = BackupEncryption.instance;

  Future<Directory> getBackupDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'posBackup'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<FileSystemEntity>> getLocalBackups() async {
    final dir = await getBackupDir();
    final entities = await dir.list().toList();
    entities.sort((a, b) {
      final aStat = a.statSync();
      final bStat = b.statSync();
      return bStat.modified.compareTo(aStat.modified);
    });
    return entities.where((e) => e.path.endsWith('.enc')).toList();
  }

  Future<void> deleteLocalBackup(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  Future<String> createBackupZip() async {
    final backupDir = await getBackupDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final zipPath = p.join(backupDir.path, 'pos_backup_$timestamp.zip');
    final encPath = zipPath.replaceAll('.zip', '.enc');

    final dbPath = await _db.getDbFilePath();
    final liveDb = await _db.database;
    await liveDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final dbBytes = await File(dbPath).readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    final prefsJson = jsonEncode(prefs.getKeys().fold<Map<String, dynamic>>({}, (map, key) {
      map[key] = prefs.get(key);
      return map;
    }));
    final prefsBytes = utf8.encode(prefsJson);

    final encoded = await Isolate.run(() {
      final archive = Archive();
      archive.addFile(ArchiveFile('pos.db', dbBytes.length, dbBytes));
      archive.addFile(ArchiveFile('preferences.json', prefsBytes.length, prefsBytes));
      return ZipEncoder().encode(archive);
    });
    if (encoded == null) throw Exception('فشل ضغط الملفات');

    final encrypted = _encryption.encryptBytes(encoded);
    await File(encPath).writeAsBytes(encrypted);

    return encPath;
  }

  Future<String> extractBackupToTemp(String filePath) async {
    final tempDir = await getTemporaryDirectory();
    final extractDir = p.join(tempDir.path, 'backup_extract_${DateTime.now().millisecondsSinceEpoch}');
    await Directory(extractDir).create(recursive: true);

    final bytes = await File(filePath).readAsBytes();
    final zipBytes = _encryption.decryptBytes(bytes);
    final archive = ZipDecoder().decodeBytes(zipBytes);
    for (final file in archive) {
      if (file.isFile) {
        final data = file.content as List<int>;
        final outPath = p.join(extractDir, file.name);
        await File(outPath).writeAsBytes(data);
      }
    }
    return extractDir;
  }

  Future<void> restoreFull(String encPath) async {
    final dbPath = await _db.getDbFilePath();
    final safetyPath = '$dbPath.restore_safety';

    final extractDir = await extractBackupToTemp(encPath);
    try {
      final liveDb = await _db.database;
      await liveDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

      await File(dbPath).copy(safetyPath);

      await _db.close();

      final walFile = '$dbPath-wal';
      final shmFile = '$dbPath-shm';
      for (final f in [walFile, shmFile]) {
        final file = File(f);
        if (await file.exists()) await file.delete();
      }

      final backupDbPath = p.join(extractDir, 'pos.db');
      final tempNewDb = '$dbPath.restore_tmp';
      await File(backupDbPath).copy(tempNewDb);

      await File(tempNewDb).rename(dbPath);

      final prefsPath = p.join(extractDir, 'preferences.json');
      if (await File(prefsPath).exists()) {
        final jsonStr = await File(prefsPath).readAsString();
        final prefsMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        final savedDriveBackups = prefs.getString('drive_backups');
        await prefs.clear();
        if (savedDriveBackups != null) {
          await prefs.setString('drive_backups', savedDriveBackups);
        }
        for (final entry in prefsMap.entries) {
          final v = entry.value;
          if (entry.key == 'drive_backups') continue;
          if (v is String) {
            await prefs.setString(entry.key, v);
          } else if (v is bool) {
            await prefs.setBool(entry.key, v);
          } else if (v is int) {
            await prefs.setInt(entry.key, v);
          } else if (v is double) {
            await prefs.setDouble(entry.key, v);
          }
        }
      }

      final safetyFile = File(safetyPath);
      if (await safetyFile.exists()) await safetyFile.delete();
    } catch (e) {
      final safetyFile = File(safetyPath);
      if (await safetyFile.exists()) {
        await _db.close();
        await safetyFile.copy(dbPath);
      }
      rethrow;
    } finally {
      await Directory(extractDir).delete(recursive: true);
    }
  }

  Future<void> restoreMerge(String encPath) async {
    final extractDir = await extractBackupToTemp(encPath);
    try {
      final backupDbPath = p.join(extractDir, 'pos.db');

      final tempDbPath = p.join(extractDir, 'temp_merge.db');
      await File(backupDbPath).copy(tempDbPath);

      final backupDb = await _db.openDbFromPath(tempDbPath);
      try {
        final tables = [
          'products',
          'sales',
          'customers',
          'debt_payments',
          'purchases',
          'purchase_items',
          'parked_carts',
          'archived_totals',
        ];
        final data = <String, List<Map<String, dynamic>>>{};
        for (final table in tables) {
          data[table] = await backupDb.query(table);
        }
        await _db.mergeFromBackup(data);
      } finally {
        await backupDb.close();
      }

      final prefsPath = p.join(extractDir, 'preferences.json');
      if (await File(prefsPath).exists()) {
        final jsonStr = await File(prefsPath).readAsString();
        final prefsMap = jsonDecode(jsonStr) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        for (final entry in prefsMap.entries) {
          final v = entry.value;
          if (v is String) {
            await prefs.setString(entry.key, v);
          } else if (v is bool) {
            await prefs.setBool(entry.key, v);
          } else if (v is int) {
            await prefs.setInt(entry.key, v);
          } else if (v is double) {
            await prefs.setDouble(entry.key, v);
          }
        }
      }
    } finally {
      await Directory(extractDir).delete(recursive: true);
    }
  }
}
