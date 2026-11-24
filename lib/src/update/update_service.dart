import 'dart:convert';

import 'package:http/http.dart' as http;

/// Repository the app updates itself from (public GitHub Releases).
const updateRepository = 'SanuSanal/gatekeeper';

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl, required this.size, this.sha256});

  final String name;
  final String downloadUrl;
  final int size;

  /// `sha256:HEX` digest published by GitHub, when available.
  final String? sha256;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
  });

  final String tag;
  final String version;
  final String name;
  final String notes;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
}

class UpdateCheck {
  const UpdateCheck({required this.currentVersion, required this.release, required this.asset});

  final String currentVersion;
  final ReleaseInfo? release;

  /// APK matching this device's ABI, if the release has one.
  final ReleaseAsset? asset;

  bool get updateAvailable =>
      release != null && asset != null && UpdateService.compareVersions(release!.version, currentVersion) > 0;
}

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Checks GitHub Releases for a newer signed APK. Sends no personal data: an anonymous
/// GET to the public API with a generic User-Agent.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Uri latestReleaseUri = Uri.https('api.github.com', '/repos/$updateRepository/releases/latest');

  Future<ReleaseInfo?> fetchLatest() async {
    final http.Response res;
    try {
      res = await _client.get(latestReleaseUri, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'GateKeeper-Android',
      }).timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw UpdateCheckException('Could not reach GitHub ($e)');
    }
    if (res.statusCode == 404) return null; // no releases yet
    if (res.statusCode != 200) throw UpdateCheckException('GitHub returned HTTP ${res.statusCode}');
    return parseRelease(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<UpdateCheck> check({required String currentVersion, required List<String> abis}) async {
    final release = await fetchLatest();
    return UpdateCheck(
      currentVersion: currentVersion,
      release: release,
      asset: release == null ? null : pickAsset(release, abis),
    );
  }

  static ReleaseInfo? parseRelease(Map<String, dynamic> json) {
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'] as String? ?? '';
    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) return null;
    final assets = <ReleaseAsset>[
      for (final a in (json['assets'] as List<dynamic>? ?? const []))
        if (a is Map<String, dynamic> && a['browser_download_url'] is String)
          ReleaseAsset(
            name: a['name'] as String? ?? '',
            downloadUrl: a['browser_download_url'] as String,
            size: (a['size'] as num?)?.toInt() ?? 0,
            sha256: a['digest'] as String?,
          ),
    ];
    return ReleaseInfo(
      tag: tag,
      version: version,
      name: json['name'] as String? ?? tag,
      notes: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? 'https://github.com/$updateRepository/releases',
      assets: assets,
    );
  }

  /// Picks `gatekeeper-VERSION-ABI.apk` for the first device ABI that has one.
  static ReleaseAsset? pickAsset(ReleaseInfo release, List<String> abis) {
    for (final abi in abis) {
      final wanted = 'gatekeeper-${release.version}-$abi.apk';
      for (final a in release.assets) {
        if (a.name == wanted) return a;
      }
    }
    return null;
  }

  /// Numeric semantic-version comparison of "MAJOR.MINOR.PATCH" (build metadata ignored).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split('+').first.split('-').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
