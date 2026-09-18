import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:localsend_app/util/native/apk_icon.dart';

void main() {
  setUp(debugResetApkIconCache);

  test('pickBestApkIconPath prefers denser mipmap launcher PNG', () {
    expect(
      pickBestApkIconPath([
        'res/mipmap-mdpi/ic_launcher.png',
        'res/mipmap-xxhdpi/ic_launcher.png',
        'res/drawable-hdpi/ic_launcher.png',
        'AndroidManifest.xml',
      ]),
      'res/mipmap-xxhdpi/ic_launcher.png',
    );
  });

  test('pickBestApkIconPath prefers ic_launcher over foreground', () {
    expect(
      pickBestApkIconPath([
        'res/mipmap-xxhdpi/ic_launcher_foreground.png',
        'res/mipmap-xxhdpi/ic_launcher.png',
      ]),
      'res/mipmap-xxhdpi/ic_launcher.png',
    );
  });

  test('extractApkIconFromArchiveBytes reads the chosen PNG', () {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final decoy = Uint8List.fromList([1, 2, 3]);
    final archive = Archive()
      ..addFile(ArchiveFile('res/mipmap-mdpi/ic_launcher.png', decoy.length, decoy))
      ..addFile(ArchiveFile('res/mipmap-xxhdpi/ic_launcher.png', png.length, png));
    final zip = ZipEncoder().encode(archive);

    expect(extractApkIconFromArchiveBytes(zip), png);
  });
}
