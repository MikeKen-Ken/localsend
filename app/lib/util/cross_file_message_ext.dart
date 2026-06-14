import 'dart:convert';

import 'package:common/model/file_type.dart';
import 'package:localsend_app/model/cross_file.dart';

extension CrossFileMessageExt on CrossFile {
  /// 文本消息内容；非文本或缺少 bytes 时返回 null。
  String? get messageText {
    if (fileType == FileType.text && bytes != null) {
      return utf8.decode(bytes!);
    }
    return null;
  }

  bool get isTextMessage => messageText != null;
}
