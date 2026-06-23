import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:routerino/routerino.dart';

class MessageInputDialog extends StatefulWidget {
  final String? initialText;

  const MessageInputDialog({this.initialText});

  @override
  State<MessageInputDialog> createState() => _MessageInputDialogState();
}

class _MessageInputDialogState extends State<MessageInputDialog> {
  final _textController = TextEditingController();

  static const _maxInputHeight = 240.0;
  static const _inputPadding = EdgeInsets.fromLTRB(12, 12, 4, 12);

  @override
  void initState() {
    super.initState();
    _textController.text = widget.initialText ?? '';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  BorderRadius _inputBorderRadius(BuildContext context) {
    final border = Theme.of(context).inputDecorationTheme.border;
    if (border is OutlineInputBorder) {
      return border.borderRadius;
    }
    return BorderRadius.circular(5);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.dialogs.messageInput.title),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxInputHeight),
          child: ClipRRect(
            borderRadius: _inputBorderRadius(context),
            child: TextFormField(
              controller: _textController,
              keyboardType: TextInputType.multiline,
              maxLines: null,
              autofocus: true,
              scrollPadding: EdgeInsets.zero,
              decoration: const InputDecoration(
                contentPadding: _inputPadding,
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.cancel),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
          onPressed: () => context.pop(_textController.text),
          child: Text(t.general.confirm),
        ),
      ],
    );
  }
}
