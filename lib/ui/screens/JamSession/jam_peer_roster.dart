import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'jam_session_controller.dart';

/// Shows everyone currently in the Jam Session — the host plus each
/// connected guest — as a row of avatars with names underneath.
///
/// Rendered on both the host and guest screens so every device sees the
/// same roster.
class JamPeerRoster extends StatelessWidget {
  final JamSessionController ctrl;
  const JamPeerRoster({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final peers = ctrl.peers.toList();
      final theme = Theme.of(context);
      final hasGuests = peers.any((p) => !p.isHost);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasGuests ? Icons.people_alt : Icons.hourglass_top,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _statusLabel(peers),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (peers.isEmpty)
            Text(
              'Nobody connected yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            )
          else
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: peers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _PeerChip(peer: peers[i]),
              ),
            ),
        ],
      );
    });
  }

  String _statusLabel(List<JamPeer> peers) {
    final guests = peers.where((p) => !p.isHost).length;
    if (guests == 0) return 'Waiting for peers…';
    return '$guests listener${guests == 1 ? '' : 's'} connected';
  }
}

class _PeerChip extends StatelessWidget {
  final JamPeer peer;
  const _PeerChip({required this.peer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = peer.isHost ? scheme.primary : scheme.secondary;

    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withOpacity(0.85),
                      accent.withOpacity(0.55),
                    ],
                  ),
                  border: Border.all(
                    color: peer.isSelf
                        ? scheme.primary
                        : scheme.outline.withOpacity(0.25),
                    width: peer.isSelf ? 2.2 : 1,
                  ),
                ),
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: Text(
                  _initials(peer.name),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (peer.isHost)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            peer.isSelf ? '${peer.name} (you)' : peer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: peer.isSelf ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Text(
            peer.isHost ? 'Host' : 'Listener',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'[\s_\-.]+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return trimmed[0].toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.elementAt(1)[0]).toUpperCase();
  }
}
