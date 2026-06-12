import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/util/device_resolver.dart';
import 'package:localsend_app/util/file_size_helper.dart';
import 'package:localsend_app/widget/device_avatar.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class FileInfoDialog extends StatelessWidget {
  final ReceiveHistoryEntry entry;

  const FileInfoDialog({required this.entry, super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.dialogs.fileInfo.title),
      content: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Table(
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: IntrinsicColumnWidth(),
                  2: IntrinsicColumnWidth(),
                },
                children: [
                  if (!entry.isMessage) ...[
                    TableRow(
                      children: [
                        Text(t.dialogs.fileInfo.fileName, maxLines: 1),
                        const SizedBox(width: 10),
                        SelectableText(entry.fileName),
                      ],
                    ),
                    TableRow(
                      children: [
                        Text(t.dialogs.fileInfo.path),
                        const SizedBox(width: 10),
                        SelectableText(entry.savedToGallery ? t.progressPage.savedToGallery : (entry.path ?? '')),
                      ],
                    ),
                  ],
                  TableRow(
                    children: [
                      Text(t.dialogs.fileInfo.size),
                      const SizedBox(width: 10),
                      SelectableText(entry.fileSize.asReadableFileSize),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(entry.isOutgoing ? t.dialogs.fileInfo.recipient : t.dialogs.fileInfo.sender),
                      const SizedBox(width: 10),
                      Consumer(
                        builder: (context, ref) {
                          final device = DeviceResolver.deviceForHistoryEntry(ref, entry);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              DeviceAvatar(device: device, size: 32),
                              const SizedBox(width: 8),
                              SelectableText(entry.senderAlias),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text(t.dialogs.fileInfo.time),
                      const SizedBox(width: 10),
                      SelectableText(entry.timestampString),
                    ],
                  ),
                ],
              ),
              if (entry.isMessage)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SelectableText(entry.fileName),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text(t.general.close),
        ),
      ],
    );
  }
}
