import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:localsend_app/gen/strings.g.dart';
import 'package:routerino/routerino.dart';

class AvatarCropPage extends StatefulWidget {
  final Uint8List imageBytes;

  const AvatarCropPage({
    required this.imageBytes,
  });

  static Future<Uint8List?> open({
    required BuildContext context,
    required Uint8List imageBytes,
  }) {
    return context.push<Uint8List?>(() => AvatarCropPage(imageBytes: imageBytes));
  }

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  late final img.Image _image;
  late double _cropSize;
  late double _cropCenterX;
  late double _cropCenterY;

  double _minCropSize = 1;
  double _maxCropSize = 1;

  @override
  void initState() {
    super.initState();
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) {
      throw Exception('Failed to decode image');
    }
    _image = decoded;
    _maxCropSize = min(_image.width, _image.height).toDouble();
    _minCropSize = max(32, _maxCropSize * 0.1);
    _cropSize = _maxCropSize * 0.8;
    _cropCenterX = _image.width / 2;
    _cropCenterY = _image.height / 2;
    _clampCropCenter();
  }

  void _clampCropCenter() {
    final half = _cropSize / 2;
    _cropCenterX = _cropCenterX.clamp(half, _image.width - half);
    _cropCenterY = _cropCenterY.clamp(half, _image.height - half);
  }

  void _onCropSizeChanged(double value) {
    setState(() {
      _cropSize = value;
      _clampCropCenter();
    });
  }

  void _onCropDrag(Offset delta, double scale) {
    setState(() {
      _cropCenterX -= delta.dx / scale;
      _cropCenterY -= delta.dy / scale;
      _clampCropCenter();
    });
  }

  Uint8List? _cropImage() {
    final half = _cropSize / 2;
    final left = (_cropCenterX - half).round().clamp(0, _image.width - 1);
    final top = (_cropCenterY - half).round().clamp(0, _image.height - 1);
    final size = _cropSize.round().clamp(1, min(_image.width - left, _image.height - top));
    final cropped = img.copyCrop(_image, x: left, y: top, width: size, height: size);
    return Uint8List.fromList(img.encodePng(cropped));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsTab.network.avatar.cropTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final result = _cropImage();
              context.pop(result);
            },
            child: Text(t.settingsTab.network.avatar.confirm),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final areaWidth = constraints.maxWidth;
                final areaHeight = constraints.maxHeight;
                final scale = min(areaWidth / _image.width, areaHeight / _image.height);
                final displayWidth = _image.width * scale;
                final displayHeight = _image.height * scale;
                final offsetX = (areaWidth - displayWidth) / 2;
                final offsetY = (areaHeight - displayHeight) / 2;

                final half = _cropSize / 2;
                final cropRect = Rect.fromLTWH(
                  offsetX + (_cropCenterX - half) * scale,
                  offsetY + (_cropCenterY - half) * scale,
                  _cropSize * scale,
                  _cropSize * scale,
                );

                return GestureDetector(
                  onPanUpdate: (details) => _onCropDrag(details.delta, scale),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: SizedBox(
                          width: displayWidth,
                          height: displayHeight,
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: _CropOverlayPainter(cropRect: cropRect),
                        child: const SizedBox.expand(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.settingsTab.network.avatar.cropSize),
                Slider(
                  min: _minCropSize,
                  max: _maxCropSize,
                  value: _cropSize.clamp(_minCropSize, _maxCropSize),
                  onChanged: _onCropSizeChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final Rect cropRect;

  const _CropOverlayPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = const Color(0x99000000);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(cropRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
