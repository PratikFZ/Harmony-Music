import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'jam_session_controller.dart';
import 'qr_scanner_screen.dart';

class JamSessionJoinScreen extends StatefulWidget {
  const JamSessionJoinScreen({super.key});

  @override
  State<JamSessionJoinScreen> createState() => _JamSessionJoinScreenState();
}

class _JamSessionJoinScreenState extends State<JamSessionJoinScreen> {
  late final JamSessionController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<JamSessionController>()
        ? Get.find<JamSessionController>()
        : Get.put(JamSessionController());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Jam Session'),
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
      case JamState.idle:
        return _IdleView(onScan: _openScanner);

      case JamState.preparingOffer:
        return const _LoadingView(message: 'Creating answer…');

      case JamState.waitingForPeer:
        return _ShowAnswerQrView(answerQrData: c.answerQrData ?? '');

      case JamState.connected:
        return _ListeningView(ctrl: c, onLeave: _close);

      case JamState.error:
        return _ErrorView(
          message: c.syncStatus.value,
          onRetry: () {
            c.endSession();
            c.update();
          },
        );
    }
  }

  Future<void> _openScanner() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      Get.snackbar(
        'Camera required',
        'Grant camera permission to join a jam session.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final result = await Get.to<String>(() => const QrScannerScreen());
    if (result != null && result.isNotEmpty) {
      await _ctrl.joinSession(result);
    }
  }

  void _close() {
    _ctrl.endSession();
    Get.back();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final VoidCallback onScan;
  const _IdleView({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner,
                size: 80,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.7)),
            const SizedBox(height: 24),
            Text(
              'Scan the host\'s QR code to join their session',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Open Camera'),
              onPressed: onScan,
            ),
          ],
        ),
      ),
    );
  }
}

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

class _ShowAnswerQrView extends StatelessWidget {
  final String answerQrData;
  const _ShowAnswerQrView({required this.answerQrData});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            'Show this QR to the host',
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
                data: answerQrData,
                version: QrVersions.auto,
                size: 260,
                errorCorrectionLevel: QrErrorCorrectLevel.L,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Once the host scans this, playback will sync automatically.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ListeningView extends StatelessWidget {
  final JamSessionController ctrl;
  final VoidCallback onLeave;

  const _ListeningView({required this.ctrl, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.headphones,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Joined Jam Session',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Obx(() => Text(
                ctrl.syncStatus.value,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              )),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'You\'re in sync with the host.\nSit back and enjoy the music!',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 40),
          OutlinedButton.icon(
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Leave Session'),
            onPressed: onLeave,
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
