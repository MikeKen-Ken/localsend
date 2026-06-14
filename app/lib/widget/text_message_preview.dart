import 'package:flutter/material.dart';

/// 可滚动的文本消息预览卡片。
class TextMessagePreview extends StatelessWidget {
  final String text;
  final double maxHeight;

  const TextMessagePreview({
    required this.text,
    this.maxHeight = 100,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: maxHeight,
      child: Card(
        margin: EdgeInsets.zero,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: SelectableText(text),
        ),
      ),
    );
  }
}
