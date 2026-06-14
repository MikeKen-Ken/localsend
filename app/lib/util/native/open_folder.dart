import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:logging/logging.dart';
import 'package:open_dir/open_dir.dart';
import 'package:open_filex/open_filex.dart';

final _logger = Logger('OpenFolder');

/// Opens the folder and optionally selects the file in the folder.
Future<void> openFolder({
  required String folderPath,
  String? fileName,
}) async {
  if (folderPath.startsWith('content://')) {
    await android_channel.openContentUri(uri: folderPath);
    return;
  }

  if (checkPlatform([TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS])) {
    var path = folderPath;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      path = path.replaceAll('/', '\\');
    }

    final result = await OpenDir().openNativeDir(path: path, highlightedFileName: fileName);
    _logger.info('Open folder result: $result, path: $path, file: $fileName');
    return;
  }

  if (checkPlatform([TargetPlatform.android])) {
    await android_channel.openFolderInFileManager(
      folderPath: folderPath,
      fileName: fileName,
    );
    return;
  }

  // iOS 等无公开目录 API 的平台：尽量打开文件本身
  final filePath = fileName != null
      ? (folderPath.endsWith('/') ? '$folderPath$fileName' : '$folderPath/$fileName')
      : folderPath.endsWith('/')
      ? folderPath
      : '$folderPath/';
  final result = await OpenFilex.open(filePath);
  _logger.info('Open folder fallback result: ${result.message}, path: $filePath');
}
