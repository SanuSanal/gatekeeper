import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gatekeeper/src/update/update_controller.dart';
import 'package:gatekeeper/src/update/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_platform.dart';

Map<String, dynamic> releaseJson(String tag, {List<String> abis = const ['arm64-v8a', 'armeabi-v7a', 'x86_64']}) {
  final v = tag.substring(1);
  return {
    'tag_name': tag,
    'name': 'GateKeeper $v',
    'body': 'Notes',
    'draft': false,
    'prerelease': false,
    'html_url': 'https://github.com/$updateRepository/releases/tag/$tag',
    'assets': [
      for (final abi in abis)
        {
          'name': 'gatekeeper-$v-$abi.apk',
          'browser_download_url': 'https://github.com/$updateRepository/releases/download/$tag/gatekeeper-$v-$abi.apk',
          'size': 1000,
          'digest': 'sha256:abc',
        },
      {'name': 'SHA256SUMS.txt', 'browser_download_url': 'https://example/x', 'size': 10},
    ],
  };
}

UpdateService serviceReturning(int status, [Object? body]) => UpdateService(
      client: MockClient((req) async {
        expect(req.url.toString(), 'https://api.github.com/repos/$updateRepository/releases/latest');
        expect(req.headers['User-Agent'], 'GateKeeper-Android');
        return http.Response(body == null ? '' : jsonEncode(body), status);
      }),
    );

void main() {
  group('version comparison', () {
    test('numeric, not lexical', () {
      expect(UpdateService.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.0+5', '1.0.0'), 0);
      expect(UpdateService.compareVersions('0.9.0', '1.0.0'), lessThan(0));
      expect(UpdateService.compareVersions('2.0', '1.9.9'), greaterThan(0));
    });
  });

  group('release parsing', () {
    test('parses tag, assets and digests', () {
      final r = UpdateService.parseRelease(releaseJson('v1.2.3'))!;
      expect(r.version, '1.2.3');
      expect(r.assets, hasLength(4));
      expect(r.assets.first.sha256, 'sha256:abc');
    });

    test('ignores drafts, prereleases and non-semver tags', () {
      expect(UpdateService.parseRelease({...releaseJson('v1.2.3'), 'prerelease': true}), isNull);
      expect(UpdateService.parseRelease({...releaseJson('v1.2.3'), 'draft': true}), isNull);
      expect(UpdateService.parseRelease({...releaseJson('v1.2.3'), 'tag_name': 'nightly'}), isNull);
    });

    test('picks the APK for the first supported device ABI', () {
      final r = UpdateService.parseRelease(releaseJson('v1.2.3'))!;
      expect(UpdateService.pickAsset(r, ['arm64-v8a', 'armeabi-v7a'])!.name, 'gatekeeper-1.2.3-arm64-v8a.apk');
      expect(UpdateService.pickAsset(r, ['x86_64'])!.name, 'gatekeeper-1.2.3-x86_64.apk');
      final armOnly = UpdateService.parseRelease(releaseJson('v1.2.3', abis: ['armeabi-v7a']))!;
      expect(UpdateService.pickAsset(armOnly, ['arm64-v8a', 'armeabi-v7a'])!.name, 'gatekeeper-1.2.3-armeabi-v7a.apk');
      expect(UpdateService.pickAsset(armOnly, ['x86_64']), isNull);
    });
  });

  group('UpdateService.check', () {
    test('newer release with matching asset is available', () async {
      final c = await serviceReturning(200, releaseJson('v1.1.0')).check(currentVersion: '1.0.0', abis: ['arm64-v8a']);
      expect(c.updateAvailable, isTrue);
    });

    test('same version is not an update', () async {
      final c = await serviceReturning(200, releaseJson('v1.0.0')).check(currentVersion: '1.0.0', abis: ['arm64-v8a']);
      expect(c.updateAvailable, isFalse);
    });

    test('no releases (404) means no update', () async {
      final c = await serviceReturning(404).check(currentVersion: '1.0.0', abis: ['arm64-v8a']);
      expect(c.release, isNull);
      expect(c.updateAvailable, isFalse);
    });

    test('server errors raise UpdateCheckException', () async {
      expect(
        serviceReturning(500).check(currentVersion: '1.0.0', abis: ['arm64-v8a']),
        throwsA(isA<UpdateCheckException>()),
      );
    });
  });

  group('UpdateController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('auto check runs at most once per day and prompts once per version', () async {
      final platform = FakePlatform();
      var calls = 0;
      final c = UpdateController(
        platform,
        service: UpdateService(client: MockClient((_) async {
          calls++;
          return http.Response(jsonEncode(releaseJson('v1.1.0')), 200);
        })),
      );
      await c.init();
      await c.maybeAutoCheck();
      expect(calls, 1);
      expect(c.promptVersion, '1.1.0');
      await c.dismissPrompt();
      await c.maybeAutoCheck();
      expect(calls, 1, reason: 'within 24 h');
      await c.maybeAutoCheck(now: DateTime.now().add(const Duration(hours: 25)));
      expect(calls, 2);
      expect(c.promptVersion, isNull, reason: 'dismissed version is not prompted again');
    });

    test('auto check disabled does nothing', () async {
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      var calls = 0;
      final c = UpdateController(
        FakePlatform(),
        service: UpdateService(client: MockClient((_) async {
          calls++;
          return http.Response('', 404);
        })),
      );
      await c.init();
      await c.maybeAutoCheck();
      expect(calls, 0);
    });

    test('install passes the device ABI asset and its digest to native', () async {
      final platform = FakePlatform()..abis = ['armeabi-v7a'];
      final c = UpdateController(platform, service: serviceReturning(200, releaseJson('v2.0.0')));
      await c.init();
      await c.check();
      expect(c.status, UpdateStatus.available);
      await c.downloadAndInstall();
      expect(platform.installed, ['gatekeeper-2.0.0-armeabi-v7a.apk']);
      expect(c.status, UpdateStatus.installerOpened);
    });

    test('needs_permission result is surfaced', () async {
      final platform = FakePlatform()..installResult = 'needs_permission';
      final c = UpdateController(platform, service: serviceReturning(200, releaseJson('v2.0.0')));
      await c.init();
      await c.check();
      await c.downloadAndInstall();
      expect(c.status, UpdateStatus.needsPermission);
    });
  });
}
