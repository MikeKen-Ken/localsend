import 'dart:async';
import 'dart:typed_data';

import 'package:common/model/device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/features/avatar/avatar_provider.dart';
import 'package:localsend_app/features/avatar/avatar_service.dart';
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
    final fetchUrl = AvatarService.resolveFetchUrl(device);
    if (fetchUrl == null) {
      return Icon(device.deviceType.icon, size: size);
    }

    return _RemoteAvatarImage(
      avatarUrl: fetchUrl,
      size: size,
      fallback: Icon(device.deviceType.icon, size: size),
    );
  }
}

/// Fetches remote avatars via [AvatarService] so LAN self-signed HTTPS works on desktop.
class _RemoteAvatarImage extends StatefulWidget {
  final String avatarUrl;
  final double size;
  final Widget fallback;

  const _RemoteAvatarImage({
    required this.avatarUrl,
    required this.size,
    required this.fallback,
  });

  @override
  State<_RemoteAvatarImage> createState() => _RemoteAvatarImageState();
}

class _RemoteAvatarImageState extends State<_RemoteAvatarImage> {
  static const _retryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  Uint8List? _bytes;
  bool _loading = true;
  Timer? _retryTimer;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _startLoad(widget.avatarUrl);
  }

  @override
  void didUpdateWidget(_RemoteAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _cancelRetry();
      _retryAttempt = 0;
      _startLoad(widget.avatarUrl);
    }
  }

  @override
  void dispose() {
    _cancelRetry();
    super.dispose();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _startLoad(String url) {
    final cached = AvatarService.getCachedRemoteAvatarBytes(url);
    if (cached != null) {
      _bytes = cached;
      _loading = false;
      return;
    }
    unawaited(_load(url));
  }

  void _scheduleRetry(String url) {
    _cancelRetry();
    if (_bytes != null || !mounted || url != widget.avatarUrl) {
      return;
    }

    final delay = _retryDelays[_retryAttempt.clamp(0, _retryDelays.length - 1)];
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      if (!mounted || url != widget.avatarUrl || _bytes != null) {
        return;
      }
      unawaited(_load(url));
    });
  }

  Future<void> _load(String url) async {
    setState(() {
      _loading = true;
    });

    Uint8List? bytes;
    for (var attempt = 0; attempt < 3; attempt++) {
      bytes = await AvatarService.fetchUrlImageBytes(url);
      if (bytes != null || !mounted || url != widget.avatarUrl) {
        break;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    if (!mounted || url != widget.avatarUrl) {
      return;
    }

    setState(() {
      _bytes = bytes;
      _loading = false;
    });

    if (bytes != null) {
      _retryAttempt = 0;
      _cancelRetry();
    } else {
      _scheduleRetry(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: SizedBox(
            width: widget.size * 0.4,
            height: widget.size * 0.4,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_bytes == null) {
      return widget.fallback;
    }

    return ClipOval(
      child: Image.memory(
        _bytes!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => widget.fallback,
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
