import 'dart:io';

import 'package:common/model/device.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';
import 'package:localsend_app/util/device_type_ext.dart';

class DeviceAvatar extends StatelessWidget {
  final Device device;
  final double size;
  final bool useLocalAvatarFile;

  const DeviceAvatar({
    required this.device,
    this.size = 46,
    this.useLocalAvatarFile = false,
  });

  @override
  Widget build(BuildContext context) {
    if (useLocalAvatarFile) {
      return FutureBuilder<File?>(
        future: AvatarService.getLocalAvatarFile(),
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file != null) {
            return ClipOval(
              child: Image.file(
                file,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(device.deviceType.icon, size: size),
              ),
            );
          }
          return _buildNetworkOrFallback();
        },
      );
    }

    return _buildNetworkOrFallback();
  }

  Widget _buildNetworkOrFallback() {
    final avatarUrl = device.avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return Icon(device.deviceType.icon, size: size);
    }

    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(device.deviceType.icon, size: size),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return SizedBox(
            width: size,
            height: size,
            child: Center(
              child: SizedBox(
                width: size * 0.4,
                height: size * 0.4,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }
}
