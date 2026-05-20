import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import 'jam_peer_roster.dart';
import 'jam_session_controller.dart';
import 'qr_scanner_screen.dart';

class JamSessionJoinScreen extends StatefulWidget {
  /// Optional pre-scanned host URI. When non-null the screen jumps straight
  /// into `joinSession`.
  final String? prescannedUri;
  const JamSessionJoinScreen({super.key, this.prescannedUri});

  @override
  State<JamSessionJoinScreen> createState() => _JamSessionJoinScreenState();
}

class _JamSessionJoinScreenState extends State<JamSessionJoinScreen> {
  late final JamSessionController _ctrl;
  final _manualAddressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<JamSessionController>()
        ? Get.find<JamSessionController>()
        // permanent: true → controller survives screen pop, so the WebSocket
        // connection stays alive when you back out of the screen.
        : Get.put(JamSessionController(), permanent: true);
    if (widget.prescannedUri != null && widget.prescannedUri!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ctrl.joinSession(widget.prescannedUri!),
      );
    }
  }

  @override
  void dispose() {
    _manualAddressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Jam Session'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Leave screen (stay connected)',
          onPressed: _hideScreen,
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
        return _IdleView(
          onScan: _openScanner,
          manualCtrl: _manualAddressCtrl,
          onManualConnect: _connectManual,
        );

      case JamState.starting:
        return const _LoadingView(message: 'Connecting…');

      case JamState.connected:
        return _ListeningView(ctrl: c, onLeave: _leaveSession);

      case JamState.waitingForPeer:
        // Guest never enters this state on its own; treat as idle.
        return _IdleView(
          onScan: _openScanner,
          manualCtrl: _manualAddressCtrl,
          onManualConnect: _connectManual,
        );

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
        'Grant camera permission to scan the host\'s QR.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }
    final result = await Get.to<String>(() => const QrScannerScreen());
    if (result != null && result.isNotEmpty) {
      await _ctrl.joinSession(result);
    }
  }

  Future<void> _connectManual() async {
    final text = _manualAddressCtrl.text.trim();
    if (text.isEmpty) {
      Get.snackbar('Enter an address',
          'Type the host\'s IP — e.g. 192.168.1.5:${JamSessionController.defaultPort}',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    await _ctrl.joinSession(text);
  }

  /// Just pop the screen; if a session is connected it stays alive so the
  /// guest keeps mirroring the host while browsing the app.
  void _hideScreen() {
    Get.back();
    if (_ctrl.state.value == JamState.connected) {
      Get.snackbar(
        'Still in Jam',
        'Mirroring host. Tap the people icon in the player to leave.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    }
  }

  /// Explicit "Leave Session" — disconnects the WebSocket and goes back.
  void _leaveSession() {
    _ctrl.endSession();
    Get.back();
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final VoidCallback onScan;
  final TextEditingController manualCtrl;
  final VoidCallback onManualConnect;

  const _IdleView({
    required this.onScan,
    required this.manualCtrl,
    required this.onManualConnect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Icon(
            Icons.qr_code_scanner,
            size: 80,
            color: Theme.of(context)
                .colorScheme
                .primary
                .withOpacity(0.7),
          ),
          const SizedBox(height: 20),
          Text(
            'Scan the host\'s QR code to join.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('Open Camera'),
            onPressed: onScan,
          ),
          const SizedBox(height: 32),
          Row(
            children: const [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('or'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Type the host address',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: manualCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              hintText:
                  'e.g. 192.168.1.5:${JamSessionController.defaultPort}',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.dns),
            ),
            onSubmitted: (_) => onManualConnect(),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Connect'),
            onPressed: onManualConnect,
          ),
          const SizedBox(height: 24),
          Text(
            'Both devices must be on the same Wi-Fi or Tailscale tailnet.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
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

class _ListeningView extends StatelessWidget {
  final JamSessionController ctrl;
  final VoidCallback onLeave;

  const _ListeningView({required this.ctrl, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.headphones,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Joined Jam Session',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Obx(() => Text(
                ctrl.syncStatus.value,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              )),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          JamPeerRoster(ctrl: ctrl),
          const SizedBox(height: 16),
          const Text(
            'Mirroring the host\'s playback.\nSit back and enjoy.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Leave Session'),
            onPressed: onLeave,
          ),
          const SizedBox(height: 16),
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
