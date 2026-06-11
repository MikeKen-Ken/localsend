import 'dart:typed_data';

import 'package:common/model/device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/features/avatar/avatar_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:refena_flutter/refena_flutter.dart';

class DeviceAvatar extends StatelessWidget {
  final Device device;
  final double size;
  final bool useLocalAvatarFile;

  /// 保留以兼容调用方；本地预览实际由 [avatarLocalBytesProvider] 驱动。
  final int localAvatarRevision;

  const DeviceAvatar({
    required this.device,
    this.size = 46,
    this.useLocalAvatarFile = false,
    this.localAvatarRevision = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (useLocalAvatarFile) {
      final bytes = context.ref.watch(avatarLocalBytesProvider);
      if (bytes != null) {
        return _LocalAvatarImage(
          bytes: bytes,
          size: size,
          fallback: Icon(device.deviceType.icon, size: size),
        );
      }
      return _buildNetworkOrFallback();
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
        key: ValueKey(avatarUrl),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
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

/// 独立 StatefulWidget，避免父级重建时丢弃已解码的 [Image.memory]。
class _LocalAvatarImage extends StatefulWidget {
  final Uint8List bytes;
  final double size;
  final Widget fallback;

  const _LocalAvatarImage({
    required this.bytes,
    required this.size,
    required this.fallback,
  });

  @override
  State<_LocalAvatarImage> createState() => _LocalAvatarImageState();
}

class _LocalAvatarImageState extends State<_LocalAvatarImage> {
  late Uint8List _displayedBytes;

  @override
  void initState() {
    super.initState();
    _displayedBytes = widget.bytes;
  }

  @override
  void didUpdateWidget(_LocalAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_bytesEqual(oldWidget.bytes, widget.bytes)) {
      _displayedBytes = widget.bytes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.memory(
        _displayedBytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.fallback,
      ),
    );
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    return identical(a, b) || listEquals(a, b);
  }
}
