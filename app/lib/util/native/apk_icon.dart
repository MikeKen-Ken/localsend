import 'dart:io';

import 'package:archive/archive.dart';
import 'package:common/model/file_type.dart';
import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;

final Map<String, Uint8List?> _apkIconMemoryCache = {};

const _densityRank = <String, int>{
  'xxxhdpi': 6,
  'xxhdpi': 5,
  'xhdpi': 4,
  'hdpi': 3,
  'mdpi': 2,
  'ldpi': 1,
};

final _launcherPng = RegExp(
  r'^res/(mipmap|drawable)(?:-([a-zA-Z0-9]+))?/(ic_launcher(?:_round|_foreground)?)\.png$',
  caseSensitive: false,
);

@visibleForTesting
void debugResetApkIconCache() {
  _apkIconMemoryCache.clear();
}

/// Picks the densest launcher PNG inside an APK zip listing.
@visibleForTesting
String? pickBestApkIconPath(Iterable<String> names) {
  String? best;
  var bestScore = -1;
  for (final raw in names) {
    final name = raw.replaceAll('\\', '/');
    final match = _launcherPng.firstMatch(name);
    if (match == null) {
      continue;
    }
    final folder = match.group(1)!.toLowerCase();
    final qualifier = (match.group(2) ?? '').toLowerCase();
    final file = match.group(3)!.toLowerCase();
    final density = _densityFromQualifier(qualifier);
    var score = density * 10;
    if (folder == 'mipmap') {
      score += 3;
    }
    if (file == 'ic_launcher') {
      score += 2;
    } else if (file == 'ic_launcher_round') {
      score += 1;
    }
    if (score > bestScore) {
      bestScore = score;
      best = name;
    }
  }
  return best;
}

int _densityFromQualifier(String qualifier) {
  if (qualifier.isEmpty) {
    return 0;
  }
  for (final entry in _densityRank.entries) {
    if (qualifier == entry.key || qualifier.split('-').contains(entry.key)) {
      return entry.value;
    }
  }
  return 0;
}

Uint8List? extractApkIconFromArchiveBytes(List<int> zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: false);
  final best = pickBestApkIconPath(archive.map((e) => e.name));
  if (best == null) {
    return null;
  }
  for (final file in archive) {
    if (file.name.replaceAll('\\', '/') != best || !file.isFile) {
      continue;
    }
    final content = file.content;
    if (content.isNotEmpty) {
      return Uint8List.fromList(content);
    }
  }
  return null;
}

Future<Uint8List?> extractApkIconBytes(String? path, {FileType? fileType}) async {
  if (kIsWeb || path == null || path.isEmpty) {
    return null;
  }
  if (fileType != null && fileType != FileType.apk) {
    return null;
  }
  if (fileType == null && path.fileName.guessFileType() != FileType.apk) {
    return null;
  }
  if (path.startsWith('content://')) {
    return null;
  }

  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  final stat = file.statSync();
  final cacheKey = '${file.absolute.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
  if (_apkIconMemoryCache.containsKey(cacheKey)) {
    return _apkIconMemoryCache[cacheKey];
  }

  Uint8List? bytes;
  if (defaultTargetPlatform == TargetPlatform.android) {
    bytes = await android_channel.extractApkIcon(path);
  }
  bytes ??= extractApkIconFromArchiveBytes(await file.readAsBytes());
  _apkIconMemoryCache[cacheKey] = bytes;
  return bytes;
}
