import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScanSound { success, unknown, error, saleComplete, warning }

class FeedbackService {
  FeedbackService._();
  static final FeedbackService instance = FeedbackService._();

  static const _kMuteAll = 'mute_all';
  static const _kMuteSuccess = 'mute_success';
  static const _kMuteError = 'mute_error';

  static const _channel = MethodChannel('com.example.pos/feedback');

  bool _ready = false;
  bool _mutedAll = false;
  bool _mutedSuccess = false;
  bool _mutedError = false;
  bool _nativeAudioAvailable = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _mutedAll = prefs.getBool(_kMuteAll) ?? false;
      _mutedSuccess = prefs.getBool(_kMuteSuccess) ?? false;
      _mutedError = prefs.getBool(_kMuteError) ?? false;
      try {
        _nativeAudioAvailable = await _channel.invokeMethod<bool>('isAvailable') ?? false;
      } catch (_) {
        _nativeAudioAvailable = false;
      }
      if (_nativeAudioAvailable) {
        try {
          final data = await rootBundle.load('assets/scan_beep.mp3');
          await _channel.invokeMethod('loadSound', data.buffer.asUint8List());
        } catch (_) {}
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  bool get mutedAll => _mutedAll;
  bool get mutedSuccess => _mutedSuccess;
  bool get mutedError => _mutedError;
  bool get isReady => _ready;
  bool get nativeAudioAvailable => _nativeAudioAvailable;

  Future<void> setMutedAll(bool v) async {
    _mutedAll = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMuteAll, v);
  }

  Future<void> setMutedSuccess(bool v) async {
    _mutedSuccess = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMuteSuccess, v);
  }

  Future<void> setMutedError(bool v) async {
    _mutedError = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMuteError, v);
  }

  Future<void> play(ScanSound kind) async {
    if (_mutedAll) {
      _hapticOnly(kind);
      return;
    }

    final isSuccessKind = kind == ScanSound.success || kind == ScanSound.saleComplete;
    final isErrorKind = kind == ScanSound.unknown ||
        kind == ScanSound.error ||
        kind == ScanSound.warning;

    if (isSuccessKind && _mutedSuccess) {
      _hapticOnly(kind);
      return;
    }
    if (isErrorKind && _mutedError) {
      _hapticOnly(kind);
      return;
    }

    if (_nativeAudioAvailable) {
      try {
        switch (kind) {
          case ScanSound.success:
          case ScanSound.saleComplete:
            await _channel.invokeMethod('playSuccess');
            break;
          case ScanSound.error:
            await _channel.invokeMethod('playError');
            break;
          case ScanSound.unknown:
          case ScanSound.warning:
            await _channel.invokeMethod('playBeep');
            break;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Native audio failed: $e');
      }
    } else {
      try {
        switch (kind) {
          case ScanSound.success:
          case ScanSound.saleComplete:
            await SystemSound.play(SystemSoundType.click);
            break;
          case ScanSound.error:
          case ScanSound.unknown:
          case ScanSound.warning:
            await SystemSound.play(SystemSoundType.alert);
            break;
        }
      } catch (_) {}
    }

    switch (kind) {
      case ScanSound.success:
        HapticFeedback.lightImpact();
        break;
      case ScanSound.unknown:
      case ScanSound.error:
        HapticFeedback.heavyImpact();
        break;
      case ScanSound.saleComplete:
        HapticFeedback.heavyImpact();
        break;
      case ScanSound.warning:
        HapticFeedback.mediumImpact();
        break;
    }
  }

  void _hapticOnly(ScanSound kind) {
    switch (kind) {
      case ScanSound.success:
        HapticFeedback.lightImpact();
        break;
      case ScanSound.unknown:
      case ScanSound.error:
        HapticFeedback.heavyImpact();
        break;
      case ScanSound.saleComplete:
        HapticFeedback.heavyImpact();
        break;
      case ScanSound.warning:
        HapticFeedback.mediumImpact();
        break;
    }
  }
}
