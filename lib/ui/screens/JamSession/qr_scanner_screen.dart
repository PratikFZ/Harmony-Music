import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen QR scanner.
/// Pops and returns the scanned raw value string via [Get.back(result: value)].
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  // - formats: only QR codes → faster, more reliable ML Kit detection
  // - cameraResolution: 1280×720 instead of the 640×480 Android default,
  //   which is too low to reliably resolve dense (high-version) QR codes.
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    cameraResolution: const Size(1280, 720),
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final rawValue = capture.barcodes.firstOrNull?.rawValue;
    if (rawValue != null && rawValue.isNotEmpty) {
      _done = true;
      debugPrint('[JamSession] QR detected (${rawValue.length} chars)');
      Get.back(result: rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          ValueListenableBuilder<TorchState>(
            valueListenable: _controller.torchState,
            builder: (_, state, __) => IconButton(
              tooltip: 'Toggle flash',
              icon: Icon(
                state == TorchState.on
                    ? Icons.flashlight_off
                    : Icons.flashlight_on,
              ),
              onPressed: _controller.toggleTorch,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt_outlined,
                        size: 56, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      'Camera could not start.\n${error.errorCode.name}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Scan-window guide — helps the user centre the QR code
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: primary, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Point your camera at the QR code',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
