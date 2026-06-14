import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';

/// 调用系统分享面板分享本地文件。
Future<void> shareLocalFiles(List<String> paths) async {
  if (paths.isEmpty) {
    return;
  }

  await Share.shareXFiles(
    paths.map((path) => XFile(path)).toList(),
  );
}
