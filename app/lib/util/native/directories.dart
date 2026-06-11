import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as path;

Future<String> getDefaultDestinationDirectory() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      // path_provider 返回的是应用私有目录（Android/data/<package>/files/Download），
      // 这里改用系统公共 Download/localsend 子目录，便于在系统「下载」应用中查看。
      const dir = '/storage/emulated/0/Download/localsend';
      try {
        await Directory(dir).create(recursive: true);
      } catch (_) {}
      return dir;
    case TargetPlatform.iOS:
      return (await path.getApplicationDocumentsDirectory()).path;
    case TargetPlatform.linux:
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.fuchsia:
      var downloadDir = await path.getDownloadsDirectory();
      if (downloadDir == null) {
        if (defaultTargetPlatform == TargetPlatform.windows) {
          downloadDir = Directory('${Platform.environment['HOMEPATH']}/Downloads');
          if (!downloadDir.existsSync()) {
            downloadDir = Directory(Platform.environment['HOMEPATH']!);
          }
        } else {
          downloadDir = Directory('${Platform.environment['HOME']}/Downloads');
          if (!downloadDir.existsSync()) {
            downloadDir = Directory(Platform.environment['HOME']!);
          }
        }
      }
      return downloadDir.path.replaceAll('\\', '/');
  }
}

Future<String> getCacheDirectory() async {
  return (await path.getTemporaryDirectory()).path;
}
