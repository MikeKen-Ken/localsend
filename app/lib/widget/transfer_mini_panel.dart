import 'package:common/model/device.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/custom_progress_bar.dart';
import 'package:localsend_app/widget/session_peer_header.dart';

/// Compact transfer chrome: peer, overall progress, restore and cancel.
class TransferMiniPanel extends StatelessWidget {
  final String title;
  final Device? peerDevice;
  final String? peerName;
  final String statusLabel;
  final double progress;
  final VoidCallback onRestore;
  final VoidCallback onCancelOrDone;
  final bool sending;

  const TransferMiniPanel({
    super.key,
    required this.title,
    required this.peerDevice,
    required this.peerName,
    required this.statusLabel,
    required this.progress,
    required this.onRestore,
    required this.onCancelOrDone,
    required this.sending,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: peerDevice != null && peerName != null
                        ? SessionPeerHeader(
                            device: peerDevice!,
                            displayName: peerName!,
                            avatarSize: 32,
                          )
                        : Text(title, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: t.progressPage.restoreWindow,
                    onPressed: onRestore,
                    icon: const Icon(Icons.open_in_full),
                  ),
                  IconButton(
                    tooltip: sending ? t.general.cancel : t.general.done,
                    onPressed: onCancelOrDone,
                    icon: Icon(sending ? Icons.close : Icons.check_circle),
                  ),
                ],
              ),
              Text(statusLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              CustomProgressBar(progress: progress, borderRadius: 5),
            ],
          ),
        ),
      ),
    );
  }
}
