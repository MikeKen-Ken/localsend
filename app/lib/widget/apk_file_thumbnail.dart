import 'dart:async';
import 'dart:typed_data';

import 'package:common/model/file_type.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/util/native/apk_icon.dart';

const double apkThumbnailSize = 50;

class ApkPathThumbnail extends StatefulWidget {
  final String path;
  final double size;

  const ApkPathThumbnail({
    super.key,
    required this.path,
    this.size = apkThumbnailSize,
  });

  @override
  State<ApkPathThumbnail> createState() => _ApkPathThumbnailState();
}

class _ApkPathThumbnailState extends State<ApkPathThumbnail> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ApkPathThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final bytes = await extractApkIconBytes(widget.path, fileType: FileType.apk);
    if (!mounted) {
      return;
    }
    setState(() {
      _bytes = bytes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: Theme.of(context).inputDecorationTheme.fillColor!,
          child: _bytes != null
              ? FittedBox(
                  fit: BoxFit.contain,
                  clipBehavior: Clip.hardEdge,
                  child: Image.memory(
                    _bytes!,
                    errorBuilder: (_, __, ___) => Icon(FileType.apk.icon, size: 32),
                  ),
                )
              : _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(FileType.apk.icon, size: 32),
        ),
      ),
    );
  }
}
