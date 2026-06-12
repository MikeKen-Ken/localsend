import 'package:common/model/device.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/widget/device_avatar.dart';

/// Avatar and display name for the remote peer in a transfer session.
class SessionPeerHeader extends StatelessWidget {
  final Device device;
  final String displayName;
  final double avatarSize;

  const SessionPeerHeader({
    required this.device,
    required this.displayName,
    this.avatarSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          DeviceAvatar(device: device, size: avatarSize),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
