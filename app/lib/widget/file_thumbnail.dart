import 'dart:io';
import 'dart:ui';

import 'package:common/model/file_type.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/file_path_helper.dart';
import 'package:localsend_app/util/file_type_ext.dart';
import 'package:localsend_app/widget/apk_file_thumbnail.dart';
import 'package:uri_content/uri_content.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

const double defaultThumbnailSize = 50;

class SmartFileThumbnail extends StatelessWidget {
  final Uint8List? bytes;
  final AssetEntity? asset;
  final String? path;
  final FileType fileType;

  const SmartFileThumbnail({
    required this.bytes,
    required this.asset,
    required this.path,
    required this.fileType,
  });

  factory SmartFileThumbnail.fromCrossFile(CrossFile file) {
    return SmartFileThumbnail(
      bytes: file.thumbnail,
      asset: file.asset,
      path: file.path,
      fileType: file.fileType,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return MemoryThumbnail(
        bytes: bytes,
        fileType: fileType,
      );
    } else if (asset != null) {
      return AssetThumbnail(
        asset: asset!,
        fileType: fileType,
      );
    } else if (_isApkPath(path, fileType)) {
      return ApkPathThumbnail(path: path!);
    } else {
      return FilePathThumbnail(
        path: path,
        fileType: fileType,
      );
    }
  }
}

class AssetThumbnail extends StatelessWidget {
  final AssetEntity asset;
  final FileType fileType;

  const AssetThumbnail({
    required this.asset,
    required this.fileType,
  });

  @override
  Widget build(BuildContext context) {
    return _Thumbnail(
      thumbnail: AssetEntityImage(
        asset,
        isOriginal: false,
        thumbnailSize: const ThumbnailSize.square(64),
        thumbnailFormat: ThumbnailFormat.jpeg,
      ),
      icon: fileType.icon,
    );
  }
}

class FilePathThumbnail extends StatelessWidget {
  final String? path;
  final FileType fileType;

  const FilePathThumbnail({
    required this.path,
    required this.fileType,
  });

  @override
  Widget build(BuildContext context) {
    if (_isApkPath(path, fileType)) {
      return ApkPathThumbnail(path: path!);
    }
    final Widget? thumbnail;
    if (path != null && fileType == FileType.image) {
      if (path!.startsWith('content://')) {
        thumbnail = Image(
          image: ResizeImage.resizeIfNeeded(
            64,
            null,
            _ContentUriImage(Uri.parse(path!)),
          ),
          errorBuilder: (_, __, ___) => Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(fileType.icon, size: 32),
          ),
        );
      } else {
        thumbnail = Image.file(
          File(path!),
          cacheWidth: 64, // reduce memory with low cached size; do not set cacheHeight because the image must keep its ratio
          errorBuilder: (_, __, ___) => Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(fileType.icon, size: 32),
          ),
        );
      }
    } else {
      thumbnail = null;
    }

    return _Thumbnail(
      thumbnail: thumbnail,
      icon: fileType.icon,
    );
  }
}

class MemoryThumbnail extends StatelessWidget {
  final Uint8List? bytes;
  final FileType fileType;
  final double size;

  const MemoryThumbnail({
    required this.bytes,
    required this.fileType,
    this.size = defaultThumbnailSize,
  });

  @override
  Widget build(BuildContext context) {
    final Widget? thumbnail;
    if (bytes != null) {
      thumbnail = Image.memory(
        bytes!,
        errorBuilder: (_, __, ___) => Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(fileType.icon, size: 32),
        ),
      );
    } else {
      thumbnail = null;
    }

    return _Thumbnail(
      thumbnail: thumbnail,
      icon: fileType.icon,
      size: size,
      fit: fileType == FileType.apk ? BoxFit.contain : BoxFit.cover,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final Widget? thumbnail;
  final IconData? icon;
  final double size;
  final BoxFit fit;

  const _Thumbnail({
    required this.thumbnail,
    required this.icon,
    this.size = defaultThumbnailSize,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: Theme.of(context).inputDecorationTheme.fillColor!,
          child: thumbnail == null
              ? Icon(icon!, size: 32)
              : FittedBox(
                  fit: fit,
                  clipBehavior: Clip.hardEdge,
                  child: thumbnail,
                ),
        ),
      ),
    );
  }
}

bool _isApkPath(String? path, FileType fileType) {
  if (path == null || path.isEmpty) {
    return false;
  }
  if (fileType == FileType.apk) {
    return true;
  }
  return path.fileName.guessFileType() == FileType.apk;
}

class _ContentUriImage extends ImageProvider<Uri> {
  final Uri uri;

  _ContentUriImage(this.uri);

  @override
  Future<Uri> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<Uri>(uri);
  }

  @override
  ImageStreamCompleter loadImage(Uri key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      // ignore: discarded_futures
      codec: _loadAsync(key, decode),
      scale: 1,
      informationCollector: () sync* {
        yield ErrorDescription('ContentUriImage: $uri');
      },
    );
  }

  Future<Codec> _loadAsync(Uri key, ImageDecoderCallback decode) async {
    final bytes = await UriContent().from(key);
    return decode(await ImmutableBuffer.fromUint8List(bytes));
  }
}
