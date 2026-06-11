import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:routerino/routerino.dart';

class ErrorDialog extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;

  const ErrorDialog({required this.error, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.dialogs.errorDialog.title),
      content: SelectableText(error),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              context.pop();
              onRetry!();
            },
            child: Text(t.general.retry),
          ),
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.close),
        ),
      ],
    );
  }
}
