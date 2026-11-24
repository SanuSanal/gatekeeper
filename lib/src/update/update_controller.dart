import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/gatekeeper_platform.dart';
import 'update_service.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, needsPermission, installerOpened, error }

/// Update state for the UI: automatic daily check, manual check, download + install.
class UpdateController extends ChangeNotifier {
  UpdateController(this.platform, {UpdateService? service, Future<SharedPreferences> Function()? prefs})
      : _service = service ?? UpdateService(),
        _prefs = prefs != null ? prefs() : SharedPreferences.getInstance() {
    _progressSub = platform.updateProgress.listen((p) {
      received = p.$1;
      total = p.$2;
      notifyListeners();
    });
  }

  static const autoCheckInterval = Duration(hours: 24);
  static const _kAuto = 'update_auto_check';
  static const _kLast = 'update_last_check_ms';
  static const _kDismissed = 'update_dismissed_version';

  final GateKeeperPlatform platform;
  final UpdateService _service;
  final Future<SharedPreferences> _prefs;
  StreamSubscription<(int, int)>? _progressSub;

  UpdateStatus status = UpdateStatus.idle;
  UpdateCheck? lastCheck;
  String? currentVersion;
  String? error;
  bool autoCheck = true;
  DateTime? lastCheckedAt;
  int received = 0;
  int total = -1;

  /// Set when an automatic check found a version the user has not dismissed yet.
  String? promptVersion;

  Future<void> init() async {
    final p = await _prefs;
    autoCheck = p.getBool(_kAuto) ?? true;
    final last = p.getInt(_kLast);
    lastCheckedAt = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
    currentVersion = (await platform.getAppInfo()).versionName;
    notifyListeners();
  }

  Future<void> setAutoCheck(bool value) async {
    autoCheck = value;
    (await _prefs).setBool(_kAuto, value);
    notifyListeners();
  }

  /// Runs at most once per [autoCheckInterval] when enabled. Failures are silent.
  Future<void> maybeAutoCheck({DateTime? now}) async {
    if (!autoCheck || status == UpdateStatus.checking || status == UpdateStatus.downloading) return;
    final n = now ?? DateTime.now();
    if (lastCheckedAt != null && n.difference(lastCheckedAt!) < autoCheckInterval) return;
    await check(silent: true);
    final r = lastCheck;
    if (r != null && r.updateAvailable) {
      final dismissed = (await _prefs).getString(_kDismissed);
      if (dismissed != r.release!.version) {
        promptVersion = r.release!.version;
        notifyListeners();
      }
    }
  }

  Future<void> check({bool silent = false}) async {
    status = UpdateStatus.checking;
    error = null;
    notifyListeners();
    try {
      final info = await platform.getAppInfo();
      currentVersion = info.versionName;
      lastCheck = await _service.check(currentVersion: info.versionName, abis: info.supportedAbis);
      status = lastCheck!.updateAvailable ? UpdateStatus.available : UpdateStatus.upToDate;
      if (lastCheck!.release != null && lastCheck!.asset == null &&
          UpdateService.compareVersions(lastCheck!.release!.version, info.versionName) > 0) {
        error = 'Version ${lastCheck!.release!.version} has no APK for this device (${info.supportedAbis.join(', ')})';
      }
      lastCheckedAt = DateTime.now();
      (await _prefs).setInt(_kLast, lastCheckedAt!.millisecondsSinceEpoch);
    } on UpdateCheckException catch (e) {
      status = silent ? UpdateStatus.idle : UpdateStatus.error;
      error = e.message;
    }
    notifyListeners();
  }

  Future<void> dismissPrompt() async {
    final v = promptVersion;
    promptVersion = null;
    if (v != null) (await _prefs).setString(_kDismissed, v);
    notifyListeners();
  }

  Future<void> downloadAndInstall() async {
    final asset = lastCheck?.asset;
    if (asset == null) return;
    promptVersion = null;
    status = UpdateStatus.downloading;
    received = 0;
    total = asset.size > 0 ? asset.size : -1;
    error = null;
    notifyListeners();
    try {
      final r = await platform.downloadAndInstallUpdate(asset.downloadUrl, asset.name, asset.sha256);
      status = r == 'needs_permission' ? UpdateStatus.needsPermission : UpdateStatus.installerOpened;
    } on PlatformException catch (e) {
      status = UpdateStatus.error;
      error = e.message ?? e.code;
    }
    notifyListeners();
  }

  Future<void> openInstallPermissionSettings() => platform.openInstallPermissionSettings();

  double? get progress => total > 0 ? (received / total).clamp(0, 1).toDouble() : null;

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
