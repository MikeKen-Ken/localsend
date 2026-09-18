import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/features/app_update/app_update_service.dart';
import 'package:localsend_app/features/app_update/github_release_client.dart';
import 'package:localsend_app/features/app_update/github_release_models.dart';
import 'package:localsend_app/features/app_update/release_notes_plain_text.dart';
import 'package:localsend_app/features/app_update/version_compare.dart';

void main() {
  group('isReusableDownloadedPackage', () {
    test('missing or empty files are not reusable', () {
      expect(
        AppUpdateService.isReusableDownloadedPackage(exists: false, length: 0, expectedSize: 10),
        isFalse,
      );
      expect(
        AppUpdateService.isReusableDownloadedPackage(exists: true, length: 0, expectedSize: 10),
        isFalse,
      );
    });

    test('known size must match exactly', () {
      expect(
        AppUpdateService.isReusableDownloadedPackage(exists: true, length: 9, expectedSize: 10),
        isFalse,
      );
      expect(
        AppUpdateService.isReusableDownloadedPackage(exists: true, length: 10, expectedSize: 10),
        isTrue,
      );
    });

    test('unknown size treats a non-empty file as reusable', () {
      expect(
        AppUpdateService.isReusableDownloadedPackage(exists: true, length: 1024, expectedSize: 0),
        isTrue,
      );
    });
  });

  group('localDownloadFileName', () {
    test('isolates same apk name by release version', () {
      const asset = GithubReleaseAsset(
        name: 'app-release.apk',
        browserDownloadUrl: 'https://example.com/app-release.apk',
        size: 0,
        updatedAt: null,
      );
      const release140 = GithubReleaseInfo(
        tagName: 'v1.17.0',
        name: '1.17.0',
        body: '',
        htmlUrl: '',
        draft: false,
        prerelease: false,
        publishedAt: null,
        assets: [],
      );
      const release141 = GithubReleaseInfo(
        tagName: 'v1.17.1',
        name: '1.17.1',
        body: '',
        htmlUrl: '',
        draft: false,
        prerelease: false,
        publishedAt: null,
        assets: [],
      );
      expect(
        AppUpdateService.localDownloadFileName(release140, asset),
        isNot(AppUpdateService.localDownloadFileName(release141, asset)),
      );
      expect(AppUpdateService.localDownloadFileName(release141, asset), contains('1.17.1'));
    });
  });

  group('VersionCompare', () {
    test('parses prefixes and build numbers', () {
      expect(VersionCompare.parse('v1.2.3'), [1, 2, 3]);
      expect(VersionCompare.parse('1.2.3+10'), [1, 2, 3]);
      expect(VersionCompare.parse('2.0.0-beta'), [2, 0, 0]);
    });

    test('compares versions', () {
      expect(VersionCompare.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(VersionCompare.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(VersionCompare.compare('v2.0.0', '1.9.9'), greaterThan(0));
    });
  });

  group('pickAssetForPlatform', () {
    final assets = [
      const GithubReleaseAsset(
        name: 'LocalSend-1.17.0-android-arm64v8.apk',
        browserDownloadUrl: 'https://example.com/a.apk',
        size: 1,
        updatedAt: null,
      ),
      const GithubReleaseAsset(
        name: 'LocalSend-1.17.0-windows-x86-64.zip',
        browserDownloadUrl: 'https://example.com/w.zip',
        size: 2,
        updatedAt: null,
      ),
    ];

    test('android picks apk', () {
      expect(pickAssetForPlatform(assets, android: true, windows: false)?.name, contains('android'));
    });

    test('windows picks zip', () {
      expect(pickAssetForPlatform(assets, android: false, windows: true)?.name, contains('windows'));
    });
  });

  test('releaseNotesToPlainText strips html', () {
    expect(releaseNotesToPlainText('<p>Hello<br/>World</p>'), 'Hello\nWorld');
  });

  test('parseReleasesAtom reads tag and title', () {
    const atom = '''
<feed>
  <entry>
    <title>v1.17.1</title>
    <link rel="alternate" href="https://github.com/MikeKen-Ken/localsend/releases/tag/v1.17.1"/>
    <published>2026-09-18T00:00:00Z</published>
    <content type="html">Notes</content>
  </entry>
</feed>
''';
    final releases = parseReleasesAtom(atom, owner: 'MikeKen-Ken', repo: 'localsend');
    expect(releases, hasLength(1));
    expect(releases.first.versionLabel, '1.17.1');
  });
}
