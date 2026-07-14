import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:firebase_auth/firebase_auth.dart';

class BackupEncryption {
  static final BackupEncryption instance = BackupEncryption._();
  BackupEncryption._();

  static const int _ivLength = 16;
  static const _salt = 'pos_backup_salt_2026';

  encrypt.Key _deriveKey(String uid) {
    final hash = sha256.convert(utf8.encode('$_salt:$uid'));
    return encrypt.Key.fromUtf8(hash.toString().substring(0, 32));
  }

  String? _getUid() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.uid;
  }

  List<int> encryptBytes(List<int> data) {
    final uid = _getUid();
    if (uid == null) throw Exception('لم يتم تسجيل الدخول');
    final key = _deriveKey(uid);
    final rng = Random.secure();
    final ivBytes = Uint8List(_ivLength);
    for (int i = 0; i < _ivLength; i++) {
      ivBytes[i] = rng.nextInt(256);
    }
    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    return iv.bytes + encrypted.bytes;
  }

  List<int> decryptBytes(List<int> encryptedData) {
    final uid = _getUid();
    if (uid == null) throw Exception('لم يتم تسجيل الدخول');
    if (encryptedData.length < _ivLength) {
      throw Exception('بيانات مشفرة غير صالحة');
    }
    final key = _deriveKey(uid);
    final iv = encrypt.IV(Uint8List.fromList(encryptedData.take(_ivLength).toList()));
    final cipherBytes = Uint8List.fromList(encryptedData.skip(_ivLength).toList());
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: iv);
  }
}
