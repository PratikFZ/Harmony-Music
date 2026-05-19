import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:get/get.dart';

import '/ui/player/player_controller.dart';

enum JamRole { none, host, guest }

enum JamState { idle, preparingOffer, waitingForPeer, connected, error }

class JamSessionController extends GetxController {
  final role = JamRole.none.obs;
  final state = JamState.idle.obs;
  final syncStatus = ''.obs;
  final connectedPeers = 0.obs;

  String? offerQrData;
  String? answerQrData;

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  Timer? _syncTimer;

  final _iceCandidates = <Map<String, dynamic>>[];
  bool _iceGatheringDone = false;

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  PlayerController get _player => Get.find<PlayerController>();

  // ─── HOST ──────────────────────────────────────────────────────────────────

  Future<void> startHosting() async {
    role.value = JamRole.host;
    state.value = JamState.preparingOffer;
    offerQrData = null;
    _iceCandidates.clear();
    _iceGatheringDone = false;

    _pc = await createPeerConnection(_iceConfig);

    final dcInit = RTCDataChannelInit()..ordered = true;
    _dc = await _pc!.createDataChannel('jam', dcInit);
    _setupDataChannel(_dc!);

    _pc!.onIceCandidate = _onIceCandidate;
    _pc!.onIceGatheringState = _onIceGatheringState;
    _pc!.onConnectionState = _onConnectionState;

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // Finalize after 8 s if ICE gathering hasn't completed
    Future.delayed(const Duration(seconds: 8), _finalizeIceGathering);
  }

  Future<void> applyGuestAnswer(String answerBase64) async {
    try {
      final json = _decodeSignal(answerBase64);
      await _pc!.setRemoteDescription(
          RTCSessionDescription(json['sdp'] as String, json['type'] as String));
      for (final ice in (json['ice'] as List)) {
        await _pc!.addCandidate(RTCIceCandidate(
          ice['candidate'] as String?,
          ice['sdpMid'] as String?,
          ice['sdpMLineIndex'] as int?,
        ));
      }
    } catch (e) {
      state.value = JamState.error;
      syncStatus.value = 'Invalid guest QR code';
    }
  }

  // ─── GUEST ─────────────────────────────────────────────────────────────────

  Future<void> joinSession(String offerBase64) async {
    role.value = JamRole.guest;
    state.value = JamState.preparingOffer;
    answerQrData = null;
    _iceCandidates.clear();
    _iceGatheringDone = false;

    _pc = await createPeerConnection(_iceConfig);

    _pc!.onDataChannel = (channel) {
      _dc = channel;
      _setupDataChannel(channel);
    };

    _pc!.onIceCandidate = _onIceCandidate;
    _pc!.onIceGatheringState = _onIceGatheringState;
    _pc!.onConnectionState = _onConnectionState;

    try {
      final json = _decodeSignal(offerBase64);
      await _pc!.setRemoteDescription(
          RTCSessionDescription(json['sdp'] as String, json['type'] as String));
      for (final ice in (json['ice'] as List)) {
        await _pc!.addCandidate(RTCIceCandidate(
          ice['candidate'] as String?,
          ice['sdpMid'] as String?,
          ice['sdpMLineIndex'] as int?,
        ));
      }
    } catch (e) {
      state.value = JamState.error;
      syncStatus.value = 'Invalid host QR code';
      return;
    }

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    Future.delayed(const Duration(seconds: 8), _finalizeIceGathering);
  }

  // ─── ICE ───────────────────────────────────────────────────────────────────

  void _onIceCandidate(RTCIceCandidate candidate) {
    if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
      _iceCandidates.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    }
  }

  void _onIceGatheringState(RTCIceGatheringState iceState) {
    if (iceState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      _finalizeIceGathering();
    }
  }

  Future<void> _finalizeIceGathering() async {
    if (_iceGatheringDone) return;
    _iceGatheringDone = true;

    final ld = await _pc?.getLocalDescription();
    if (ld == null) return;

    // Strip embedded candidate lines from the SDP — they are already in the
    // ice array, and embedding them would double the payload size.
    final strippedSdp = _stripCandidateLines(ld.sdp ?? '');

    // Only keep routable candidates (skip loopback and link-local).
    final filteredIce = _filterCandidates(_iceCandidates);

    final jsonStr = jsonEncode({
      'sdp': strippedSdp,
      'type': ld.type,
      'ice': filteredIce,
    });

    // Gzip-compress then base64url-encode to keep the QR payload small.
    final compressed = GZipCodec().encode(utf8.encode(jsonStr));
    final encoded = base64Url.encode(compressed);

    if (role.value == JamRole.host) {
      offerQrData = encoded;
    } else {
      answerQrData = encoded;
    }
    state.value = JamState.waitingForPeer;
    update();
  }

  /// Removes `a=candidate:` and `a=end-of-candidates` lines from the SDP.
  /// These will be delivered separately via [addCandidate] on the remote peer.
  String _stripCandidateLines(String sdp) {
    return sdp
        .split('\n')
        .where((l) =>
            !l.startsWith('a=candidate:') && l.trim() != 'a=end-of-candidates')
        .join('\n');
  }

  /// Removes loopback (127.x / ::1) and link-local (169.254.x) candidates
  /// that can never be used across devices.
  List<Map<String, dynamic>> _filterCandidates(
      List<Map<String, dynamic>> candidates) {
    return candidates.where((c) {
      final s = c['candidate'] as String? ?? '';
      if (s.contains(' 127.0.0.1 ') || s.contains(' ::1 ')) return false;
      if (s.contains(' 169.254.')) return false;
      return true;
    }).toList();
  }

  // ─── CONNECTION ────────────────────────────────────────────────────────────

  void _onConnectionState(RTCPeerConnectionState connectionState) {
    if (connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      state.value = JamState.connected;
      connectedPeers.value = 1;
      syncStatus.value = 'Connected!';
      if (role.value == JamRole.host) {
        _startSyncBroadcast();
      }
    } else if (connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _syncTimer?.cancel();
      connectedPeers.value = 0;
      syncStatus.value = 'Peer disconnected';
      state.value = JamState.idle;
    }
  }

  // ─── DATA CHANNEL ──────────────────────────────────────────────────────────

  void _setupDataChannel(RTCDataChannel dc) {
    dc.onDataChannelState = (dcState) {
      if (dcState == RTCDataChannelState.RTCDataChannelOpen) {
        state.value = JamState.connected;
        connectedPeers.value = 1;
        syncStatus.value = 'Connected!';
        if (role.value == JamRole.host) {
          _startSyncBroadcast();
        }
      } else if (dcState == RTCDataChannelState.RTCDataChannelClosed) {
        _syncTimer?.cancel();
        connectedPeers.value = 0;
        syncStatus.value = 'Disconnected';
      }
    };
    dc.onMessage = (msg) {
      if (role.value == JamRole.guest) {
        _applySync(msg.text);
      }
    };
  }

  // ─── SYNC BROADCAST (host only) ────────────────────────────────────────────

  void _startSyncBroadcast() {
    _syncTimer?.cancel();
    _sendSync();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sendSync());
  }

  void _sendSync() {
    if (_dc == null) return;
    if (_dc!.state != RTCDataChannelState.RTCDataChannelOpen) return;

    final song = _player.currentSong.value;
    if (song == null) return;

    final posMs = _player.progressBarStatus.value.current.inMilliseconds;
    final ts = DateTime.now().millisecondsSinceEpoch;

    _dc!.send(RTCDataChannelMessage(jsonEncode({
      't': 's',
      'id': song.id,
      'title': song.title,
      'artist': song.artist ?? '',
      'art': song.artUri?.toString() ?? '',
      'ms': posMs,
      'ts': ts,
    })));
  }

  // ─── SYNC APPLY (guest only) ───────────────────────────────────────────────

  void _applySync(String raw) async {
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      if (msg['t'] != 's') return;

      final videoId = msg['id'] as String;
      final posMs = msg['ms'] as int;
      final sentTs = msg['ts'] as int;
      final networkDelayMs = DateTime.now().millisecondsSinceEpoch - sentTs;
      final adjustedPos =
          Duration(milliseconds: (posMs + networkDelayMs).clamp(0, 1 << 30));

      syncStatus.value = 'Syncing: ${msg['title']}';

      if (_player.currentSong.value?.id != videoId) {
        final song = MediaItem(
          id: videoId,
          title: msg['title'] as String? ?? '',
          artist: msg['artist'] as String? ?? '',
          artUri: Uri.tryParse(msg['art'] as String? ?? ''),
          extras: const {'resultType': 'song'},
        );
        await _player.pushSongToQueue(song);
        await Future.delayed(const Duration(seconds: 3));
        _player.seek(adjustedPos);
      } else {
        final currentPos = _player.progressBarStatus.value.current;
        if ((currentPos - adjustedPos).inMilliseconds.abs() > 3000) {
          _player.seek(adjustedPos);
        }
      }
    } catch (_) {}
  }

  // ─── CLEANUP ───────────────────────────────────────────────────────────────

  Future<void> endSession() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    try {
      _dc?.close();
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _dc = null;
    _iceCandidates.clear();
    offerQrData = null;
    answerQrData = null;
    role.value = JamRole.none;
    state.value = JamState.idle;
    connectedPeers.value = 0;
    syncStatus.value = '';
    _iceGatheringDone = false;
  }

  @override
  void onClose() {
    endSession();
    super.onClose();
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────

  /// Decodes a base64url+gzip-compressed signaling payload into a JSON map.
  Map<String, dynamic> _decodeSignal(String encoded) {
    final padded = _padBase64(encoded);
    final compressed = base64Url.decode(padded);
    final bytes = GZipCodec().decode(compressed);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  /// Add missing base64url padding characters.
  String _padBase64(String input) {
    final mod = input.length % 4;
    if (mod == 0) return input;
    return input + '=' * (4 - mod);
  }
}
