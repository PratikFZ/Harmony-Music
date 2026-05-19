import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'jam_session_controller.dart';
import 'qr_scanner_screen.dart';

class JamSessionHostScreen extends StatefulWidget {
  const JamSessionHostScreen({super.key});

  @override
  State<JamSessionHostScreen> createState() => _JamSessionHostScreenState();
}

class _JamSessionHostScreenState extends State<JamSessionHostScreen> {
  late final JamSessionController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<JamSessionController>()
        ? Get.find<JamSessionController>()
        : Get.put(JamSessionController());
    // Start ICE gathering right away
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.startHosting());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start Jam Session'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _close,
        ),
      ),
      body: GetBuilder<JamSessionController>(
        builder: (c) => _buildBody(context, c),
      ),
    );
  }

  Widget _buildBody(BuildContext context, JamSessionController c) {
    switch (c.state.value) {
      case JamState.preparingOffer:
        return const _LoadingView(message: 'Preparing jam session…');

      case JamState.waitingForPeer:
        return _WaitingForPeerView(
          offerQrData: c.offerQrData ?? '',
          onScanGuest: () => _scanGuestQr(c),
        );

      case JamState.connected:
        return _ConnectedView(ctrl: c, onEnd: _close);

      case JamState.error:
        return _ErrorView(
          message: c.syncStatus.value,
          onRetry: () => c.startHosting(),
        );

      default:
        return const _LoadingView(message: 'Starting…');
    }
  }

  Future<void> _scanGuestQr(JamSessionController c) async {
    final hasPerm = await _requestCamera();
    if (!hasPerm) return;
    final result = await Get.to<String>(() => const QrScannerScreen());
    if (result != null && result.isNotEmpty) {
      await c.applyGuestAnswer(result);
    }
  }

  Future<bool> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      Get.snackbar(
        'Camera required',
        'Please grant camera permission to scan QR codes.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return false;
    }
    return true;
  }

  void _close() {
    _ctrl.endSession();
    Get.back();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String message;
  const _LoadingView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _WaitingForPeerView extends StatelessWidget {
  final String offerQrData;
  final VoidCallback onScanGuest;

  const _WaitingForPeerView({
    required this.offerQrData,
    required this.onScanGuest,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Step 1 – Let your friend scan this QR',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: offerQrData,
                version: QrVersions.auto,
                size: 260,
                errorCorrectionLevel: QrErrorCorrectLevel.L,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 20),
          Text(
            'Step 2 – Scan your friend\'s reply QR',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Friend\'s QR'),
            onPressed: onScanGuest,
          ),
        ],
      ),
    );
  }
}

class _ConnectedView extends StatelessWidget {
  final JamSessionController ctrl;
  final VoidCallback onEnd;

  const _ConnectedView({required this.ctrl, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Jam Session Active',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Obx(() => Text(
                '${ctrl.connectedPeers.value} listener(s) connected',
                style: Theme.of(context).textTheme.bodyMedium,
              )),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Your friends are now listening with you!\nPlay any song and they\'ll hear the same.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 40),
          OutlinedButton.icon(
            icon: const Icon(Icons.stop),
            label: const Text('End Session'),
            onPressed: onEnd,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
