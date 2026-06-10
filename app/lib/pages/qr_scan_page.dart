import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/web_share_download_page.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/util/web_share_url.dart';
import 'package:localsend_app/widget/custom_basic_appbar.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:routerino/routerino.dart';

class QrScanPage extends StatefulWidget {
  const QrScanPage();

  static Future<void> open(BuildContext context) async {
    if (checkPlatform([TargetPlatform.android, TargetPlatform.iOS])) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!context.mounted) {
          return;
        }

        if (status.isPermanentlyDenied) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(t.dialogs.qr.cameraPermissionTitle),
              content: Text(t.dialogs.qr.cameraPermissionDenied),
              actions: [
                TextButton(
                  onPressed: () => context.pop(),
                  child: Text(t.general.close),
                ),
                TextButton(
                  onPressed: () async {
                    context.pop();
                    await openAppSettings();
                  },
                  child: Text(t.dialogs.qr.openSettings),
                ),
              ],
            ),
          );
        } else {
          context.showSnackBar(t.dialogs.qr.cameraRequired);
        }
        return;
      }
    }

    if (context.mounted) {
      await context.push(() => const QrScanPage());
    }
  }

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }

    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue == null) {
      return;
    }

    final url = WebShareUrl.tryParse(rawValue);
    if (url == null) {
      context.showSnackBar(t.dialogs.qr.invalidCode);
      return;
    }

    _handled = true;
    _controller.stop();
    await context.push(() => WebShareDownloadPage(url: url));
    if (mounted) {
      _handled = false;
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: basicLocalSendAppbar(t.dialogs.qr.scanTitle),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                if (checkPlatform([TargetPlatform.android]))
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: IconButton.filled(
                      onPressed: () => _controller.toggleTorch(),
                      icon: const Icon(Icons.flash_on),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              t.dialogs.qr.scanHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
