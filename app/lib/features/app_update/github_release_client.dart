import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/features/app_update/app_update_constants.dart';
import 'package:localsend_app/features/app_update/github_release_models.dart';
import 'package:localsend_app/features/app_update/release_notes_plain_text.dart';

class ReleaseHttpResult {
  const ReleaseHttpResult({
    required this.statusCode,
    required this.body,
    this.rateLimitRemaining,
  });

  final int statusCode;
  final String body;
  final String? rateLimitRemaining;
}

/// 从 GitHub 拉取已发布版本：Atom → jsDelivr → REST API。
class GithubReleaseClient {
  GithubReleaseClient({
    HttpClient? httpClient,
    this.owner = AppUpdateConstants.owner,
    this.repo = AppUpdateConstants.repo,
    Future<ReleaseHttpResult> Function(Uri uri)? httpGet,
  }) : _httpClient = httpClient ?? HttpClient(),
       _httpGetOverride = httpGet {
    _httpClient.userAgent = AppUpdateConstants.userAgent;
  }

  final HttpClient _httpClient;
  final Future<ReleaseHttpResult> Function(Uri uri)? _httpGetOverride;
  final String owner;
  final String repo;

  Uri get _atomUri => Uri.https('github.com', '/$owner/$repo/releases.atom');
  Uri get _jsdelivrUri => Uri.https('data.jsdelivr.com', '/v1/packages/gh/$owner/$repo');
  Uri get _apiUri => Uri.https('api.github.com', '/repos/$owner/$repo/releases', {'per_page': '10'});

  Future<List<GithubReleaseInfo>> fetchReleases() async {
    final errors = <String>[];
    try {
      return await _fetchViaAtom();
    } catch (e) {
      errors.add('Atom: $e');
    }
    try {
      return await _fetchViaJsdelivr();
    } catch (e) {
      errors.add('jsDelivr: $e');
    }
    try {
      return await _fetchViaApi();
    } catch (e) {
      errors.add('API: $e');
    }
    throw StateError('Failed to read releases. ${errors.join('; ')}');
  }

  Future<List<GithubReleaseInfo>> _fetchViaAtom() async {
    final result = await _get(_atomUri);
    _ensureOk(result, label: 'Atom');
    final releases = parseReleasesAtom(result.body, owner: owner, repo: repo);
    if (releases.isEmpty) {
      throw StateError('Atom contains no usable releases');
    }
    return releases;
  }

  Future<List<GithubReleaseInfo>> _fetchViaJsdelivr() async {
    final result = await _get(_jsdelivrUri);
    _ensureOk(result, label: 'jsDelivr');
    return parseJsdelivrGhPackage(result.body, owner: owner, repo: repo);
  }

  Future<List<GithubReleaseInfo>> _fetchViaApi() async {
    final result = await _get(_apiUri);
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw StateError('Failed to read GitHub releases (HTTP ${result.statusCode})');
    }
    final decoded = jsonDecode(result.body);
    if (decoded is! List) {
      throw const FormatException('Invalid GitHub release response format');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(GithubReleaseInfo.fromJson)
        .where((r) => !r.draft && r.tagName.isNotEmpty)
        .toList();
  }

  Future<void> downloadAsset(
    GithubReleaseAsset asset,
    File destination, {
    void Function(double? progress)? onProgress,
  }) async {
    final uri = Uri.parse(asset.browserDownloadUrl);
    final request = await _httpClient.getUrl(uri);
    _applyHeaders(request, uri);
    request.followRedirects = true;
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Download failed (HTTP ${response.statusCode})');
    }
    final total = response.contentLength;
    var received = 0;
    final sink = destination.openWrite();
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          onProgress(total > 0 ? received / total : null);
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<GithubReleaseAsset?> resolvePlatformAsset(
    GithubReleaseInfo release, {
    required bool android,
    required bool windows,
  }) async {
    final version = release.versionLabel;
    final tag = release.tagName.startsWith('v') ? release.tagName : 'v${release.tagName}';
    final candidates = <String>[];
    if (android) {
      candidates.addAll([
        'LocalSend-$version-android-arm64v8.apk',
        'app-release.apk',
      ]);
    }
    if (windows) {
      candidates.add('LocalSend-$version-windows-x86-64.zip');
    }

    for (final name in candidates) {
      final url = 'https://github.com/$owner/$repo/releases/download/$tag/$name';
      if (!await _headExists(Uri.parse(url))) {
        continue;
      }
      return GithubReleaseAsset(
        name: name,
        browserDownloadUrl: url,
        size: 0,
        updatedAt: release.publishedAt,
      );
    }

    return pickAssetForPlatform(release.assets, android: android, windows: windows);
  }

  Future<bool> _headExists(Uri uri) async {
    try {
      final request = await _httpClient.openUrl('HEAD', uri);
      _applyHeaders(request, uri);
      request.followRedirects = true;
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      try {
        final request = await _httpClient.getUrl(uri);
        _applyHeaders(request, uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        request.followRedirects = true;
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode >= 200 && response.statusCode < 400;
      } catch (_) {
        return false;
      }
    }
  }

  Future<ReleaseHttpResult> _get(Uri uri) async {
    final override = _httpGetOverride;
    if (override != null) {
      return override(uri);
    }
    final request = await _httpClient.getUrl(uri);
    _applyHeaders(request, uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return ReleaseHttpResult(
      statusCode: response.statusCode,
      body: body,
      rateLimitRemaining: response.headers.value('x-ratelimit-remaining'),
    );
  }

  void _ensureOk(ReleaseHttpResult result, {required String label}) {
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw StateError('$label HTTP ${result.statusCode}');
    }
  }

  void _applyHeaders(HttpClientRequest request, Uri uri) {
    request.headers.set(HttpHeaders.userAgentHeader, AppUpdateConstants.userAgent);
    final accept = switch (uri.host) {
      'api.github.com' => 'application/vnd.github+json',
      'data.jsdelivr.com' => 'application/json',
      _ when uri.path.endsWith('.atom') => 'application/atom+xml, */*',
      _ => '*/*',
    };
    request.headers.set(HttpHeaders.acceptHeader, accept);
  }

  void close() => _httpClient.close(force: true);
}

List<GithubReleaseInfo> parseReleasesAtom(
  String atom, {
  required String owner,
  required String repo,
}) {
  final results = <GithubReleaseInfo>[];
  final entryPattern = RegExp(r'<entry>([\s\S]*?)</entry>');
  for (final match in entryPattern.allMatches(atom)) {
    final block = match.group(1)!;
    final link =
        RegExp(r'rel="alternate"[^>]*href="([^"]+)"').firstMatch(block)?.group(1) ??
        RegExp(r'href="([^"]+/releases/tag/[^"]+)"').firstMatch(block)?.group(1);
    if (link == null) {
      continue;
    }
    final tagMatch = RegExp(r'/releases/tag/([^/"\s]+)').firstMatch(link);
    if (tagMatch == null) {
      continue;
    }
    final tagName = tagMatch.group(1)!;
    final title = RegExp(r'<title>([^<]*)</title>').firstMatch(block)?.group(1) ?? tagName;
    final published = RegExp(r'<published>([^<]*)</published>').firstMatch(block)?.group(1);
    final updated = RegExp(r'<updated>([^<]*)</updated>').firstMatch(block)?.group(1);
    final rawContent = RegExp(r'<content[^>]*>([\s\S]*?)</content>').firstMatch(block)?.group(1);
    final body = rawContent == null ? '' : releaseNotesToPlainText(_decodeBasicXml(rawContent));
    results.add(
      GithubReleaseInfo(
        tagName: tagName,
        name: _decodeBasicXml(title),
        body: body,
        htmlUrl: link,
        draft: false,
        prerelease: false,
        publishedAt: DateTime.tryParse(published ?? updated ?? ''),
        assets: const [],
      ),
    );
  }
  return results;
}

List<GithubReleaseInfo> parseJsdelivrGhPackage(
  String jsonText, {
  required String owner,
  required String repo,
}) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid jsDelivr response format');
  }
  final versions = decoded['versions'];
  if (versions is! List || versions.isEmpty) {
    throw StateError('jsDelivr contains no usable versions');
  }
  final results = <GithubReleaseInfo>[];
  for (final item in versions) {
    if (item is! Map) {
      continue;
    }
    final version = '${item['version'] ?? ''}'.trim();
    if (version.isEmpty) {
      continue;
    }
    final tagName = version.startsWith('v') || version.startsWith('V') ? version : 'v$version';
    results.add(
      GithubReleaseInfo(
        tagName: tagName,
        name: version,
        body: '',
        htmlUrl: 'https://github.com/$owner/$repo/releases/tag/$tagName',
        draft: false,
        prerelease: version.contains('-'),
        publishedAt: null,
        assets: const [],
      ),
    );
  }
  if (results.isEmpty) {
    throw StateError('jsDelivr contains no usable versions');
  }
  return results;
}

String _decodeBasicXml(String input) {
  return input
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

GithubReleaseAsset? pickAssetForPlatform(
  List<GithubReleaseAsset> assets, {
  required bool android,
  required bool windows,
}) {
  final lower = assets.map((a) => (a, a.name.toLowerCase())).toList();
  if (android) {
    for (final (asset, name) in lower) {
      if (name.contains(AppUpdateConstants.androidAssetHint) && name.endsWith('.apk')) {
        return asset;
      }
    }
    for (final (asset, name) in lower) {
      if (name.endsWith('.apk')) {
        return asset;
      }
    }
  }
  if (windows) {
    for (final (asset, name) in lower) {
      if (name.contains(AppUpdateConstants.windowsAssetHint) && name.endsWith('.zip')) {
        return asset;
      }
    }
    for (final (asset, name) in lower) {
      if (name.endsWith('.zip')) {
        return asset;
      }
    }
  }
  return null;
}
