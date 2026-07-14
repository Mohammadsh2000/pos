import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class DriveBackupInfo {
  final String id;
  final String name;
  final int size;
  final DateTime createdTime;

  DriveBackupInfo({
    required this.id,
    required this.name,
    required this.size,
    required this.createdTime,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedDate {
    final d = createdTime;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class DriveBackupService {
  static final DriveBackupService instance = DriveBackupService._();
  DriveBackupService._();

  static const _baseUrl = 'https://www.googleapis.com/drive/v3';
  static const _uploadUrl = 'https://www.googleapis.com/upload/drive/v3';
  static const _prefsKey = 'drive_backups';
  static const _backupFolderName = 'posBackup';

  Future<String?> _getToken() => AuthService.instance.getAccessToken();

  Future<bool> ensureDriveAccess() async {
    var account = AuthService.instance.currentGoogleAccount;
    if (account == null) {
      account = await AuthService.instance.trySilentSignIn();
    }
    if (account == null) {
      account = await AuthService.instance.signInGoogle();
    }

    if (account == null) {
      await Future.delayed(const Duration(milliseconds: 500));
      account = AuthService.instance.currentGoogleAccount;
    }
    if (account == null) {
      account = await AuthService.instance.trySilentSignIn();
    }

    if (account == null) return false;

    final token = await AuthService.instance.getAccessToken();
    if (token == null) return false;

    try {
      final resp = await http.get(
        Uri.parse('https://www.googleapis.com/drive/v3/about?fields=user'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) return true;
      return await AuthService.instance.requestDriveScope();
    } catch (_) {
      return await AuthService.instance.requestDriveScope();
    }
  }

  String _fileNameFromPath(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isNotEmpty ? parts.last : path;
  }

  List<Map<String, dynamic>> _loadPrefsList(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> _saveBackupEntry(Map<String, dynamic> entry) async {
    final prefs = await SharedPreferences.getInstance();
    final String? existing = prefs.getString(_prefsKey);
    final List<Map<String, dynamic>> list = existing != null
        ? _loadPrefsList(existing)
        : [];
    list.add(entry);
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> _loadBackupEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? json = prefs.getString(_prefsKey);
    if (json == null) return [];
    return _loadPrefsList(json);
  }

  Future<void> _removeBackupEntry(String fileId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? existing = prefs.getString(_prefsKey);
    if (existing == null) return;
    final list = _loadPrefsList(existing);
    list.removeWhere((e) => e['id'] == fileId);
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  Future<String> _ensureBackupFolder() async {
    final token = await _getToken();
    if (token == null) throw Exception('لم يتم تسجيل الدخول');

    final searchResp = await http.get(
      Uri.parse('$_baseUrl/files?q=name=\'$_backupFolderName\'+and+mimeType=\'application/vnd.google-apps.folder\'+and+trashed=false&pageSize=1&fields=files(id)'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (searchResp.statusCode != 200) {
      throw Exception('فشل البحث عن مجلد posBackup: ${searchResp.body}');
    }
    final data = jsonDecode(searchResp.body);
    final files = data['files'] as List? ?? [];
    if (files.isNotEmpty) return files.first['id'] as String;

    final createResp = await http.post(
      Uri.parse('$_baseUrl/files'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': _backupFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );
    if (createResp.statusCode != 200) {
      throw Exception('فشل إنشاء مجلد posBackup على Drive: ${createResp.body}');
    }
    return jsonDecode(createResp.body)['id'] as String;
  }

  Future<Map<String, dynamic>> uploadBackup(
    String zipPath, {
    void Function(double progress)? onProgress,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('لم يتم تسجيل الدخول');

    final folderId = await _ensureBackupFolder();
    final fileName = _fileNameFromPath(zipPath);

    final createResp = await http.post(
      Uri.parse('$_baseUrl/files'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': fileName,
        'parents': [folderId],
      }),
    );
    if (createResp.statusCode != 200) {
      throw Exception('فشل إنشاء الملف على Drive: ${createResp.body}');
    }
    final createData = jsonDecode(createResp.body);
    final fileId = createData['id'] as String?;
    if (fileId == null) throw Exception('فشل الحصول على معرف الملف من Drive');

    final fileBytes = await File(zipPath).readAsBytes();
    final totalBytes = fileBytes.length;

    final client = HttpClient();
    try {
      final request = await client.patchUrl(
        Uri.parse('$_uploadUrl/files/$fileId?uploadType=media'),
      );
      request.headers.set('Authorization', 'Bearer $token');
      request.headers.set('Content-Type', 'application/zip');
      request.contentLength = totalBytes;

      const chunkSize = 65536;
      int bytesSent = 0;
      for (int offset = 0; offset < totalBytes; offset += chunkSize) {
        final end = (offset + chunkSize > totalBytes) ? totalBytes : offset + chunkSize;
        request.add(fileBytes.sublist(offset, end));
        bytesSent = end;
        onProgress?.call(bytesSent / totalBytes);
      }
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception('فشل رفع المحتوى إلى Drive: $respBody');
      }

      await _saveBackupEntry({
        'id': fileId,
        'name': fileName,
        'size': fileBytes.length,
        'createdTimeMs': DateTime.now().millisecondsSinceEpoch,
      });

      return {'id': fileId, 'name': fileName};
    } finally {
      client.close();
    }
  }

  Future<List<DriveBackupInfo>> _listBackupsFromDrive() async {
    final token = await _getToken();
    if (token == null) throw Exception('لم يتم تسجيل الدخول');

    final searchResp = await http.get(
      Uri.parse('$_baseUrl/files?q=name=\'$_backupFolderName\'+and+mimeType=\'application/vnd.google-apps.folder\'+and+trashed=false&pageSize=1&fields=files(id)'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (searchResp.statusCode != 200) {
      throw Exception('فشل الاتصال بـ Drive: ${searchResp.statusCode} ${searchResp.body}');
    }
    final searchData = jsonDecode(searchResp.body);
    final foundFolders = searchData['files'] as List? ?? [];
    if (foundFolders.isEmpty) return [];

    final folderId = foundFolders.first['id'] as String;

    final resp = await http.get(
      Uri.parse('$_baseUrl/files?q=\'$folderId\'+in+parents+and+trashed=false&orderBy=createdTime+desc&pageSize=50&fields=files(id,name,size,createdTime)'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل تحميل قائمة النسخ من Drive: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body);
    final files = data['files'] as List? ?? [];
    return files.map((f) {
      final sizeStr = f['size'];
      final size = sizeStr is String ? (int.tryParse(sizeStr) ?? 0) : ((sizeStr as num?)?.toInt() ?? 0);
      return DriveBackupInfo(
        id: f['id'] as String,
        name: f['name'] as String? ?? '',
        size: size,
        createdTime: DateTime.tryParse(f['createdTime'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  Future<List<DriveBackupInfo>> listBackups() async {
    final backups = await _listBackupsFromDrive();
    if (backups.isNotEmpty) return backups;
    final entries = await _loadBackupEntries();
    return entries.map((e) => DriveBackupInfo(
      id: e['id'] as String,
      name: e['name'] as String? ?? '',
      size: e['size'] as int? ?? 0,
      createdTime: DateTime.fromMillisecondsSinceEpoch(e['createdTimeMs'] as int? ?? 0),
    )).toList();
  }

  Future<String> downloadBackup(String fileId) async {
    final token = await _getToken();
    if (token == null) throw Exception('لم يتم تسجيل الدخول');

    final resp = await http.get(
      Uri.parse('$_baseUrl/files/$fileId?alt=media'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل تنزيل الملف: ${resp.body}');
    }

    final tempDir = Directory.systemTemp;
    final path = '${tempDir.path}/drive_download_${DateTime.now().millisecondsSinceEpoch}.enc';
    await File(path).writeAsBytes(resp.bodyBytes);
    return path;
  }

  Future<void> deleteBackup(String fileId) async {
    final token = await _getToken();
    if (token == null) throw Exception('لم يتم تسجيل الدخول');

    final resp = await http.delete(
      Uri.parse('$_baseUrl/files/$fileId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw Exception('فشل حذف الملف: ${resp.body}');
    }

    await _removeBackupEntry(fileId);
  }
}
