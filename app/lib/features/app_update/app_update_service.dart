import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/features/app_update/app_update_constants.dart';
import 'package:localsend_app/features/app_update/app_update_installer.dart';
import 'package:localsend_app/features/app_update/github_release_client.dart';
import 'package:localsend_app/features/app_update/github_release_models.dart';
import 'package:localsend_app/features/app_update/version_compare.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUpdateService {
  AppUpdateService({
    GithubReleaseClient? client,
    AppUpdateInstaller? installer,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _client = client ?? GithubReleaseClient(),
       _installer = installer ?? AppUpdateInstaller(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  final GithubReleaseClient _client;
  final AppUpdateInstaller _installer;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<SharedPreferences> Function() _prefsLoader;

  bool get isSupported => _installer.isSupported;

  Future<AppUpdateCheckResult> checkForUpdate() async {
    final info = await _packageInfoLoader();
    final currentVersion = info.version;
    final currentBuild = info.buildNumber;

    if (!isSupported) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        message: 'unsupported',
      );
    }

    final releases = await _client.fetchReleases();
    final published = releases.where((r) => !r.prerelease).toList();
    final pool = published.isNotEmpty ? published : releases;
    if (pool.isEmpty) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        message: 'empty',
      );
    }

    pool.sort((left, right) => VersionCompare.compare(right.versionLabel, left.versionLabel));
    final release = pool.first;
    final currentRelease = _findReleaseForVersion(pool, currentVersion);
    final asset = await _client.resolvePlatformAsset(
      release,
      android: !kIsWeb && Platform.isAndroid,
      windows: !kIsWeb && Platform.isWindows,
    );
    if (asset == null) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        release: release,
        message: 'no-asset',
      );
    }

    final newer = VersionCompare.isNewer(release.versionLabel, currentVersion);
    final rebuilt = await _isSameVersionNewerAsset(release.versionLabel, asset);
    final updateAvailable = newer || rebuilt;

    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      release: release,
      currentRelease: currentRelease,
      asset: asset,
      updateAvailable: updateAvailable,
      message: newer ? 'newer' : (rebuilt ? 'same-version' : 'current'),
    );
  }

  Future<bool> _isSameVersionNewerAsset(String remoteVersion, GithubReleaseAsset asset) async {
    if (VersionCompare.compare(remoteVersion, (await _packageInfoLoader()).version) != 0) {
      return false;
    }
    final updatedAt = asset.updatedAt;
    if (updatedAt == null) {
      return false;
    }
    final prefs = await _prefsLoader();
    final raw = prefs.getString(AppUpdateConstants.prefsLastAssetUpdatedAt);
    if (raw == null || raw.isEmpty) {
      return false;
    }
    final last = DateTime.tryParse(raw);
    if (last == null) {
      return false;
    }
    return updatedAt.isAfter(last);
  }

  Future<void> markAssetInstalled(
    GithubReleaseAsset asset, {
    DateTime? publishedAt,
    required String releaseVersion,
  }) async {
    final prefs = await _prefsLoader();
    final stamp = (asset.updatedAt ?? DateTime.now().toUtc()).toIso8601String();
    await prefs.setString(AppUpdateConstants.prefsLastAssetUpdatedAt, stamp);
    await prefs.setString(AppUpdateConstants.prefsLastReleaseVersion, releaseVersion);
    final published = publishedAt ?? asset.updatedAt;
    if (published != null) {
      await prefs.setString(AppUpdateConstants.prefsLastReleasePublishedAt, published.toUtc().toIso8601String());
    }
  }

  Future<DateTime?> installedReleasePublishedAt(String currentVersion) async {
    final prefs = await _prefsLoader();
    final storedVersion = prefs.getString(AppUpdateConstants.prefsLastReleaseVersion);
    if (storedVersion == null || storedVersion.isEmpty || VersionCompare.compare(storedVersion, currentVersion) != 0) {
      return null;
    }
    final raw = prefs.getString(AppUpdateConstants.prefsLastReleasePublishedAt);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static GithubReleaseInfo? _findReleaseForVersion(List<GithubReleaseInfo> releases, String version) {
    for (final release in releases) {
      if (VersionCompare.compare(release.versionLabel, version) == 0) {
        return release;
      }
    }
    return null;
  }

  Future<void> skipVersion(String version) async {
    final prefs = await _prefsLoader();
    await prefs.setString(AppUpdateConstants.prefsSkippedVersion, version);
  }

  Future<String?> skippedVersion() async {
    final prefs = await _prefsLoader();
    return prefs.getString(AppUpdateConstants.prefsSkippedVersion);
  }

  Future<void> downloadAndInstall(
    AppUpdateCheckResult check, {
    void Function(double? progress)? onProgress,
  }) async {
    final release = check.release;
    final asset = check.asset;
    if (release == null || asset == null || !check.updateAvailable) {
      throw StateError('No installable update is available');
    }

    final tempDir = await getTemporaryDirectory();
    final downloadPath = p.join(tempDir.path, localDownloadFileName(release, asset));
    final file = File(downloadPath);
    if (!await _ensureLocalPackage(file, asset)) {
      await _downloadToCompleteFile(file, asset, onProgress: onProgress);
    } else {
      onProgress?.call(1.0);
    }

    if (!kIsWeb && Platform.isAndroid) {
      await _installer.installAndroidApk(file);
      await markAssetInstalled(asset, publishedAt: release.publishedAt, releaseVersion: release.versionLabel);
      return;
    }

    if (!kIsWeb && Platform.isWindows) {
      final extracted = await _installer.extractZip(file);
      await markAssetInstalled(asset, publishedAt: release.publishedAt, releaseVersion: release.versionLabel);
      await _installer.applyWindowsZipUpdate(extracted);
    }
  }

  Future<bool> _ensureLocalPackage(File file, GithubReleaseAsset asset) async {
    if (!await file.exists()) {
      return false;
    }
    final length = await file.length();
    return isReusableDownloadedPackage(exists: true, length: length, expectedSize: asset.size);
  }

  Future<void> _downloadToCompleteFile(
    File file,
    GithubReleaseAsset asset, {
    void Function(double? progress)? onProgress,
  }) async {
    if (await file.exists()) {
      await file.delete();
    }
    final partial = File('${file.path}.partial');
    if (await partial.exists()) {
      await partial.delete();
    }
    await _client.downloadAsset(asset, partial, onProgress: onProgress);
    await partial.rename(file.path);
  }

  @visibleForTesting
  static String localDownloadFileName(GithubReleaseInfo release, GithubReleaseAsset asset) {
    final releaseKey = release.versionLabel.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final assetKey = asset.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return 'localsend_download_${releaseKey}_$assetKey';
  }

  @visibleForTesting
  static bool isReusableDownloadedPackage({
    required bool exists,
    required int length,
    required int expectedSize,
  }) {
    if (!exists || length <= 0) {
      return false;
    }
    if (expectedSize > 0) {
      return length == expectedSize;
    }
    return true;
  }

  void dispose() => _client.close();
}
