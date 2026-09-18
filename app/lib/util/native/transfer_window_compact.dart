import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:window_manager/window_manager.dart';

/// Shrinks the desktop window into a compact always-on-top transfer bar.
class TransferWindowCompact {
  static const Size miniSize = Size(420, 156);
  static const Size restoredMinimum = Size(400, 500);

  Size? _previousSize;
  Offset? _previousPosition;
  bool _active = false;

  bool get isActive => _active;

  Future<void> enter() async {
    if (!checkPlatformIsDesktop() || kIsWeb) {
      _active = true;
      return;
    }
    _previousSize = await windowManager.getSize();
    _previousPosition = await windowManager.getPosition();
    await windowManager.setMinimumSize(miniSize);
    await windowManager.setSize(miniSize);
    await windowManager.setAlwaysOnTop(true);
    _active = true;
  }

  Future<void> exit() async {
    if (!_active) {
      return;
    }
    _active = false;
    if (!checkPlatformIsDesktop() || kIsWeb) {
      return;
    }
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(restoredMinimum);
    final size = _previousSize;
    if (size != null) {
      await windowManager.setSize(size);
    }
    final position = _previousPosition;
    if (position != null) {
      await windowManager.setPosition(position);
    }
  }
}
