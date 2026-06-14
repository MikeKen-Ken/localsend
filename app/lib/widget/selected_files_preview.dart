import 'package:flutter/material.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/cross_file_message_ext.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_app/widget/text_message_preview.dart';

/// 发送页选中文件的缩略图与文本预览。
class SelectedFilesPreview extends StatelessWidget {
  final List<CrossFile> files;

  const SelectedFilesPreview({
    required this.files,
  });

  @override
  Widget build(BuildContext context) {
    final textFiles = files.where((f) => f.isTextMessage).toList();
    final allText = textFiles.length == files.length;

    if (allText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < textFiles.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < textFiles.length - 1 ? 8 : 0),
              child: TextMessagePreview(text: textFiles[i].messageText!),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: defaultThumbnailSize,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: SmartFileThumbnail.fromCrossFile(file),
              );
            },
          ),
        ),
        if (textFiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var i = 0; i < textFiles.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < textFiles.length - 1 ? 8 : 0),
              child: TextMessagePreview(
                text: textFiles[i].messageText!,
                maxHeight: 60,
              ),
            ),
        ],
      ],
    );
  }
}
