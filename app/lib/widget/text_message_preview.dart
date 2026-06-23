import 'package:flutter/material.dart';

/// 可滚动的文本消息预览卡片。
class TextMessagePreview extends StatefulWidget {
  final String text;
  final double maxHeight;

  const TextMessagePreview({
    required this.text,
    this.maxHeight = 100,
  });

  @override
  State<TextMessagePreview> createState() => _TextMessagePreviewState();
}

class _TextMessagePreviewState extends State<TextMessagePreview> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.maxHeight,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: SelectableText(widget.text),
          ),
        ),
      ),
    );
  }
}
