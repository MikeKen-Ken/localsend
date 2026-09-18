import 'dart:async';

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
    super.key,
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
      // Local avatar is loading from disk — avoid HTTP fetch + spinner for own device.
      return Icon(device.deviceType.icon, size: size);
    }

    return _PeerAvatarImage(
      device: device,
      size: size,
      fallback: Icon(device.deviceType.icon, size: size),
    );
  }
}

/// Shows a peer avatar from fingerprint cache first, then refreshes from the network.
class _PeerAvatarImage extends StatefulWidget {
  final Device device;
  final double size;
  final Widget fallback;

  const _PeerAvatarImage({
    required this.device,
    required this.size,
    required this.fallback,
  });

  @override
  State<_PeerAvatarImage> createState() => _PeerAvatarImageState();
}

class _PeerAvatarImageState extends State<_PeerAvatarImage> {
  static const _retryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  Uint8List? _bytes;
  bool _loading = false;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  String? _fetchUrl;

  String get _fingerprint => widget.device.fingerprint.trim();

  @override
  void initState() {
    super.initState();
    _primeFromCache();
    _startLoad();
  }

  @override
  void didUpdateWidget(_PeerAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl = AvatarService.resolveFetchUrl(oldWidget.device);
    final newUrl = AvatarService.resolveFetchUrl(widget.device);
    final fingerprintChanged = oldWidget.device.fingerprint != widget.device.fingerprint;
    if (fingerprintChanged) {
      _cancelRetry();
      _retryAttempt = 0;
      _primeFromCache();
      _startLoad();
      return;
    }
    if (oldUrl != newUrl) {
      _cancelRetry();
      _retryAttempt = 0;
      _startLoad();
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

  void _primeFromCache() {
    _fetchUrl = AvatarService.resolveFetchUrl(widget.device);
    _bytes = AvatarService.getCachedPeerAvatarBytes(_fingerprint) ??
        (_fetchUrl == null ? null : AvatarService.getCachedRemoteAvatarBytes(_fetchUrl!));
    _loading = _bytes == null && _fetchUrl != null;
  }

  void _startLoad() {
    _fetchUrl = AvatarService.resolveFetchUrl(widget.device);
    unawaited(_loadDiskThenNetwork());
  }

  Future<void> _loadDiskThenNetwork() async {
    if (_bytes == null && _fingerprint.isNotEmpty) {
      final disk = await AvatarService.loadPeerAvatarBytes(_fingerprint);
      if (!mounted) {
        return;
      }
      if (disk != null && _bytes == null) {
        setState(() {
          _bytes = disk;
          _loading = false;
        });
      }
    }

    final url = _fetchUrl;
    if (url == null) {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
      return;
    }
    await _load(url);
  }

  void _scheduleRetry(String url) {
    _cancelRetry();
    if (!mounted || url != _fetchUrl) {
      return;
    }

    final delay = _retryDelays[_retryAttempt.clamp(0, _retryDelays.length - 1)];
    _retryAttempt++;
    _retryTimer = Timer(delay, () {
      if (!mounted || url != _fetchUrl) {
        return;
      }
      unawaited(_load(url));
    });
  }

  Future<void> _load(String url) async {
    if (_bytes == null && mounted) {
      setState(() => _loading = true);
    }

    Uint8List? bytes;
    for (var attempt = 0; attempt < 3; attempt++) {
      bytes = await AvatarService.fetchUrlImageBytes(url);
      if (bytes != null || !mounted || url != _fetchUrl) {
        break;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    if (!mounted || url != _fetchUrl) {
      return;
    }

    if (bytes != null) {
      unawaited(AvatarService.savePeerAvatar(_fingerprint, bytes));
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
      _retryAttempt = 0;
      _cancelRetry();
      return;
    }

    setState(() => _loading = false);
    if (_bytes == null) {
      _scheduleRetry(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
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

    return widget.fallback;
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
