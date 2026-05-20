import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'jam_peer_roster.dart';
import 'jam_session_controller.dart';

class JamSessionHostScreen extends StatefulWidget {
  const JamSessionHostScreen({super.key});

  @override
  State<JamSessionHostScreen> createState() => _JamSessionHostScreenState();
}

class _JamSessionHostScreenState extends State<JamSessionHostScreen> {
  late final JamSessionController _ctrl;
  int _selectedIpIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = Get.isRegistered<JamSessionController>()
        ? Get.find<JamSessionController>()
        // permanent: true → controller survives screen pop, so the WebSocket
        // server / connection stays alive when you back out of the screen.
        : Get.put(JamSessionController(), permanent: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.startHosting());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Host Jam Session'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Leave screen (jam keeps running)',
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
      case JamState.starting:
        return const _LoadingView(message: 'Starting host…');

      case JamState.waitingForPeer:
      case JamState.connected:
        return _HostView(
          ctrl: c,
          selectedIpIndex: _selectedIpIndex,
          onIpChanged: (i) => setState(() => _selectedIpIndex = i),
          onEnd: _endSession,
        );

      case JamState.error:
        return _ErrorView(
          message: c.syncStatus.value,
          onRetry: () => c.startHosting(),
        );

      default:
        return const _LoadingView(message: 'Starting…');
    }
  }

  /// Just pop the screen — the host server keeps running so the user can
  /// browse and play music while peers stay connected.
  void _hideScreen() {
    Get.back();
    if (_ctrl.state.value == JamState.connected ||
        _ctrl.state.value == JamState.waitingForPeer) {
      Get.snackbar(
        'Jam still active',
        'Tap the people icon in the player to manage or end.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
    }
  }

  /// Explicit "End Session" — tears down the server and disconnects peers.
  void _endSession() {
    _ctrl.endSession();
    Get.back();
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _HostView extends StatelessWidget {
  final JamSessionController ctrl;
  final int selectedIpIndex;
  final ValueChanged<int> onIpChanged;
  final VoidCallback onEnd;

  const _HostView({
    required this.ctrl,
    required this.selectedIpIndex,
    required this.onIpChanged,
    required this.onEnd,
  });

  String _buildUri(String ip, int port) =>
      '${JamSessionController.scheme}://$ip:$port';

  @override
  Widget build(BuildContext context) {
    final ips = ctrl.hostIps;
    final port = ctrl.hostPort ?? JamSessionController.defaultPort;
    if (ips.isEmpty) {
      return _ErrorView(
        message: 'No LAN interface detected.',
        onRetry: () => ctrl.startHosting(),
      );
    }
    final idx = selectedIpIndex.clamp(0, ips.length - 1);
    final ip = ips[idx];
    final uri = _buildUri(ip, port);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Friends on the same Wi-Fi or Tailscale\nscan this QR to join.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
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
                data: uri,
                version: QrVersions.auto,
                size: 260,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _AddressCard(
            uri: uri,
            ip: ip,
            port: port,
          ),
          if (ips.length > 1) ...[
            const SizedBox(height: 12),
            Text(
              'Multiple addresses detected — pick the one your friend can reach:',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                for (int i = 0; i < ips.length; i++)
                  ChoiceChip(
                    label: Text(ips[i]),
                    selected: i == idx,
                    onSelected: (_) => onIpChanged(i),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          JamPeerRoster(ctrl: ctrl),
          const SizedBox(height: 12),
          const Text(
            'Play any song and they\'ll hear the same.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
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

class _AddressCard extends StatelessWidget {
  final String uri;
  final String ip;
  final int port;
  const _AddressCard(
      {required this.uri, required this.ip, required this.port});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$ip : $port',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  uri,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy address',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uri));
              Get.snackbar('Copied', uri,
                  snackPosition: SnackPosition.BOTTOM);
            },
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: () => Share.share(
              'Join my Jam: $uri',
              subject: 'Harmony Jam Session',
            ),
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
