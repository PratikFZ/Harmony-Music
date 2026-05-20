import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/player/player_controller.dart';

enum JamRole { none, host, guest }

enum JamState { idle, starting, waitingForPeer, connected, error }

/// A participant in a Jam Session — either the host or a connected guest.
class JamPeer {
  final String id;
  final String name;
  final bool isHost;
  final bool isSelf;

  const JamPeer({
    required this.id,
    required this.name,
    required this.isHost,
    this.isSelf = false,
  });

  JamPeer copyWith({String? id, String? name, bool? isHost, bool? isSelf}) =>
      JamPeer(
        id: id ?? this.id,
        name: name ?? this.name,
        isHost: isHost ?? this.isHost,
        isSelf: isSelf ?? this.isSelf,
      );

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'id': id, 'name': name, 'isHost': isHost};

  static JamPeer fromJson(Map<String, dynamic> j) => JamPeer(
        id: (j['id'] as String?) ?? '',
        name: ((j['name'] as String?) ?? '').trim().isEmpty
            ? 'Listener'
            : (j['name'] as String).trim(),
        isHost: j['isHost'] as bool? ?? false,
      );
}

/// LAN / Tailscale Jam Session.
///
/// Host opens an HTTP + WebSocket server bound to the LAN address and shows a
/// QR code containing `harmonyjam://<ip>:<port>`. Guests on the same network
/// (or Tailscale tailnet) scan the QR and connect via WebSocket.
///
/// Sync protocol (no audio over the wire — only timing):
///   - Host advertises its authoritative playback offset as an anchor
///     `(anchorMs, anchorAt)` meaning "song was at anchorMs at host-time
///     anchorAt", plus a `playing` flag.
///   - Guests run an NTP-style ping/pong against the host to learn the
///     host↔guest clock offset, then compute their target song position any
///     time as `anchorMs + (now + offset - anchorAt)` while playing.
///   - A 150 ms drift loop on each guest closes the gap: for big drift
///     (>1.5 s) it hard-seeks, for small drift it nudges `setSpeed` by up to
///     ±5 % until aligned, then restores 1.0.
class JamSessionController extends GetxController {
  static const int defaultPort = 47474;
  static const String scheme = 'harmonyjam';

  // ─── Sync tuning ──────────────────────────────────────────────────────────
  static const _heartbeatMs = 250; // host → all-peers anchor refresh
  static const _driftTickMs = 150; // guest correction loop
  static const _pingIntervalMs = 5000; // steady-state clock-sync ping
  static const _initialPingBurst = 5; // rapid pings on connect
  static const _initialPingGapMs = 250;
  static const _hardSeekDriftMs = 1500;
  static const _seekDeadbandMs = 40;
  static const _seekCooldownMs = 700;
  static const _maxRateNudge = 0.05; // ±5 % at full drift

  final role = JamRole.none.obs;
  final state = JamState.idle.obs;
  final syncStatus = ''.obs;
  final connectedPeers = 0.obs;

  /// Everyone in the session — host first, then guests. Both host and
  /// guest sides keep this in sync so each screen can render the same roster.
  final peers = <JamPeer>[].obs;

  /// Identity for this device — set on `startHosting` / `joinSession`,
  /// cleared on `endSession`.
  JamPeer? _selfPeer;
  JamPeer? get selfPeer => _selfPeer;

  // ─── Host state ───────────────────────────────────────────────────────────
  HttpServer? _server;
  final Map<WebSocket, JamPeer> _clientPeers = <WebSocket, JamPeer>{};
  Timer? _broadcastTimer;
  Worker? _songWatcher;
  Worker? _playStateWatcher;
  Worker? _positionWatcher;
  final Random _rand = Random();

  /// Authoritative anchor maintained on the host: song was at `_hostAnchorMs`
  /// at host-time `_hostAnchorAt`. Updated whenever the player's reported
  /// position changes so the broadcast is always carrying the freshest pair.
  int _hostAnchorMs = 0;
  int _hostAnchorAt = 0;

  // ─── Guest state ──────────────────────────────────────────────────────────
  WebSocket? _client;
  StreamSubscription? _clientSub;
  Timer? _driftTimer;
  Timer? _pingTimer;

  /// Best (lowest-RTT) estimate of `hostTime - guestTime` in ms. Null until
  /// the first pong arrives.
  int? _clockOffsetMs;
  int _bestRttMs = 1 << 30;

  /// Latest anchor reported by the host.
  String? _hostSongId;
  String? _hostSongTitle;
  String? _hostSongArtist;
  String? _hostSongArt;
  int _anchorMs = 0;
  int _anchorAt = 0; // host-clock ms
  bool _hostPlaying = true;

  int _lastSeekAtMs = 0;
  double _currentJamSpeed = 1.0;
  bool _trackLoadInProgress = false;

  // ─── Shared ───────────────────────────────────────────────────────────────
  List<String> hostIps = <String>[];
  int? hostPort;
  String? joinUri; // e.g. harmonyjam://192.168.1.5:47474

  // Preference snapshot so we can restore after the session ends.
  int? _prevQualityIndex;

  PlayerController get _player => Get.find<PlayerController>();
  AudioHandler get _audioHandler => Get.find<AudioHandler>();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  // ─── HOST ──────────────────────────────────────────────────────────────────

  Future<void> startHosting({int port = defaultPort}) async {
    await endSession();
    role.value = JamRole.host;
    state.value = JamState.starting;
    syncStatus.value = 'Starting host…';
    _selfPeer = JamPeer(
      id: _generatePeerId(),
      name: _detectMyName(),
      isHost: true,
      isSelf: true,
    );
    peers.value = <JamPeer>[_selfPeer!];
    update();

    _forceHighQuality();

    try {
      hostIps = await _detectLanIps();
      if (hostIps.isEmpty) {
        state.value = JamState.error;
        syncStatus.value =
            'No LAN / Tailscale network found.\nConnect to Wi-Fi or Tailscale and retry.';
        update();
        return;
      }

      // Try the preferred port first, then fall back to an ephemeral one.
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      } on SocketException {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      }
      hostPort = _server!.port;
      joinUri = '$scheme://${hostIps.first}:${hostPort!}';

      _server!.listen(
        _handleHttpRequest,
        onError: (Object e) {
          syncStatus.value = 'Server error: $e';
        },
      );

      // Seed the anchor from whatever the player is currently reporting so
      // the first heartbeat has valid numbers even before the position
      // stream emits anything.
      _refreshHostAnchor();

      _songWatcher = ever<MediaItem?>(_player.currentSong, (_) {
        _refreshHostAnchor();
        _broadcastState();
      });
      _playStateWatcher =
          ever<PlayButtonState>(_player.buttonState, (_) {
        _refreshHostAnchor();
        _broadcastState();
      });
      // Every position emit is a fresh anchor — keeps the broadcasted
      // (anchorMs, anchorAt) pair tight even though we only push at the
      // heartbeat cadence.
      _positionWatcher = ever(_player.progressBarStatus, (_) {
        _refreshHostAnchor();
      });

      _broadcastTimer = Timer.periodic(
          const Duration(milliseconds: _heartbeatMs), (_) => _broadcastState());

      state.value = JamState.waitingForPeer;
      syncStatus.value = 'Waiting for peers…';
      update();
    } catch (e) {
      state.value = JamState.error;
      syncStatus.value = 'Could not start host: $e';
      update();
    }
  }

  void _refreshHostAnchor() {
    _hostAnchorMs = _player.progressBarStatus.value.current.inMilliseconds;
    _hostAnchorAt = _now();
  }

  Future<void> _handleHttpRequest(HttpRequest req) async {
    if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        final placeholder = JamPeer(
          id: _generatePeerId(),
          name: 'Listener ${_clientPeers.length + 1}',
          isHost: false,
        );
        _clientPeers[ws] = placeholder;

        ws.add(jsonEncode(<String, dynamic>{
          't': 'hello',
          'v': 2,
          'host': _selfPeer?.toJson(),
        }));
        _broadcastPeers();
        _sendStateTo(ws);

        ws.listen(
          (raw) => _onHostMessage(ws, raw),
          onDone: () => _dropClient(ws),
          onError: (_) => _dropClient(ws),
          cancelOnError: true,
        );
      } catch (e) {
        debugPrint('[JamSession] upgrade failed: $e');
      }
    } else if (req.uri.path == '/' || req.uri.path == '/health') {
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'app': 'harmonymusic', 'role': 'host'}))
        ..close();
    } else {
      req.response
        ..statusCode = HttpStatus.notFound
        ..close();
    }
  }

  void _onHostMessage(WebSocket ws, dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['t']) {
        case 'hello':
          final name = (msg['name'] as String?)?.trim();
          final id = (msg['id'] as String?)?.trim();
          final existing = _clientPeers[ws];
          if (existing == null) return;
          _clientPeers[ws] = existing.copyWith(
            id: (id != null && id.isNotEmpty) ? id : existing.id,
            name: (name != null && name.isNotEmpty) ? name : existing.name,
          );
          _broadcastPeers();
          break;
        case 'ping':
          // NTP-style: stamp host receive + send, echo guest's t1 back so the
          // guest can compute RTT and clock offset.
          final t1 = msg['t1'];
          final t2 = _now();
          final t3 = _now();
          ws.add(jsonEncode(<String, dynamic>{
            't': 'pong',
            't1': t1,
            't2': t2,
            't3': t3,
          }));
          break;
      }
    } catch (_) {/* ignore malformed */}
  }

  void _dropClient(WebSocket ws) {
    _clientPeers.remove(ws);
    _broadcastPeers();
  }

  void _broadcastPeers() {
    final all = <JamPeer>[
      if (_selfPeer != null) _selfPeer!,
      ..._clientPeers.values,
    ];
    peers.value = all;

    final guestCount = _clientPeers.length;
    connectedPeers.value = guestCount;
    if (guestCount == 0) {
      state.value = JamState.waitingForPeer;
      syncStatus.value = 'Waiting for peers…';
    } else {
      state.value = JamState.connected;
      syncStatus.value =
          '$guestCount listener${guestCount == 1 ? '' : 's'} connected';
    }

    final payload = jsonEncode(<String, dynamic>{
      't': 'peers',
      'peers': all.map((p) => p.toJson()).toList(),
    });
    for (final c in _clientPeers.keys.toList()) {
      try {
        c.add(payload);
      } catch (_) {/* drop on next event */}
    }
    update();
  }

  void _broadcastState() {
    if (_clientPeers.isEmpty) return;
    final payload = _currentStatePayload();
    if (payload == null) return;
    for (final c in _clientPeers.keys.toList()) {
      try {
        c.add(payload);
      } catch (_) {/* drop on next event */}
    }
  }

  void _sendStateTo(WebSocket ws) {
    final payload = _currentStatePayload();
    if (payload != null) ws.add(payload);
  }

  String? _currentStatePayload() {
    final song = _player.currentSong.value;
    if (song == null) return null;
    final playing = _player.buttonState.value == PlayButtonState.playing;
    return jsonEncode({
      't': 'state',
      'id': song.id,
      'title': song.title,
      'artist': song.artist ?? '',
      'art': song.artUri?.toString() ?? '',
      'anchorMs': _hostAnchorMs,
      'anchorAt': _hostAnchorAt,
      'playing': playing,
    });
  }

  // ─── GUEST ─────────────────────────────────────────────────────────────────

  Future<void> joinSession(String uri) async {
    await endSession();
    role.value = JamRole.guest;
    state.value = JamState.starting;
    syncStatus.value = 'Connecting…';
    _selfPeer = JamPeer(
      id: _generatePeerId(),
      name: _detectMyName(),
      isHost: false,
      isSelf: true,
    );
    peers.value = <JamPeer>[_selfPeer!];
    update();

    _forceHighQuality();

    final parsed = parseJoinUri(uri);
    if (parsed == null) {
      state.value = JamState.error;
      syncStatus.value = 'Invalid QR code or address.';
      update();
      return;
    }
    final (host, port) = parsed;
    final wsUrl = 'ws://$host:$port/ws';

    try {
      _client = await WebSocket.connect(wsUrl)
          .timeout(const Duration(seconds: 6));
      state.value = JamState.connected;
      syncStatus.value = 'Connected to host';
      connectedPeers.value = 1;
      update();

      _client!.add(jsonEncode(<String, dynamic>{
        't': 'hello',
        'name': _selfPeer!.name,
        'id': _selfPeer!.id,
      }));

      _clientSub = _client!.listen(
        _onGuestMessage,
        onDone: _onGuestDisconnected,
        onError: (Object e) {
          syncStatus.value = 'Connection error: $e';
          _onGuestDisconnected();
        },
        cancelOnError: true,
      );

      _startClockSync();
      _startDriftLoop();
    } on TimeoutException {
      state.value = JamState.error;
      syncStatus.value = 'Host did not respond. Same network?';
      update();
    } catch (e) {
      state.value = JamState.error;
      syncStatus.value = 'Could not reach host. $e';
      update();
    }
  }

  /// Burst a handful of pings up front so the offset converges before the
  /// first correction tick fires, then keep pinging at a steady cadence.
  void _startClockSync() {
    _bestRttMs = 1 << 30;
    _clockOffsetMs = null;
    for (int i = 0; i < _initialPingBurst; i++) {
      Future.delayed(Duration(milliseconds: i * _initialPingGapMs), _sendPing);
    }
    _pingTimer = Timer.periodic(
        const Duration(milliseconds: _pingIntervalMs), (_) => _sendPing());
  }

  void _sendPing() {
    final ws = _client;
    if (ws == null) return;
    try {
      ws.add(jsonEncode(<String, dynamic>{'t': 'ping', 't1': _now()}));
    } catch (_) {/* socket may have closed; loop will tear down */}
  }

  void _onPong(Map<String, dynamic> msg) {
    final t1 = (msg['t1'] as num?)?.toInt();
    final t2 = (msg['t2'] as num?)?.toInt();
    final t3 = (msg['t3'] as num?)?.toInt();
    if (t1 == null || t2 == null || t3 == null) return;
    final t4 = _now();
    final rtt = (t4 - t1) - (t3 - t2);
    if (rtt < 0) return; // clock weirdness, skip
    // Always update on first sample; afterward only when RTT improves so the
    // offset estimate keeps converging to the best link conditions seen.
    if (_clockOffsetMs == null || rtt < _bestRttMs) {
      _bestRttMs = rtt;
      _clockOffsetMs = ((t2 - t1) + (t3 - t4)) ~/ 2;
    }
  }

  void _onGuestMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (msg['t']) {
        case 'hello':
          break;
        case 'peers':
          _applyPeerList(msg);
          break;
        case 'state':
          _applyHostState(msg);
          break;
        case 'pong':
          _onPong(msg);
          break;
      }
    } catch (_) {/* ignore malformed */}
  }

  void _applyPeerList(Map<String, dynamic> msg) {
    final raw = msg['peers'] as List? ?? const [];
    final list = <JamPeer>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final p = JamPeer.fromJson(entry);
        list.add(p.id == _selfPeer?.id ? p.copyWith(isSelf: true) : p);
      }
    }
    peers.value = list;
    final others = list.where((p) => !p.isSelf).length;
    connectedPeers.value = others;
    update();
  }

  Future<void> _applyHostState(Map<String, dynamic> msg) async {
    final id = msg['id'] as String?;
    if (id == null || id.isEmpty) return;

    _hostSongId = id;
    _hostSongTitle = msg['title'] as String? ?? '';
    _hostSongArtist = msg['artist'] as String? ?? '';
    _hostSongArt = msg['art'] as String? ?? '';
    _anchorMs = (msg['anchorMs'] as num?)?.toInt() ?? 0;
    _anchorAt = (msg['anchorAt'] as num?)?.toInt() ?? _now();
    _hostPlaying = msg['playing'] as bool? ?? true;

    syncStatus.value = 'Playing: $_hostSongTitle';

    final current = _player.currentSong.value;
    if (current?.id != id) {
      if (_trackLoadInProgress) return;
      _trackLoadInProgress = true;

      final song = MediaItem(
        id: id,
        title: _hostSongTitle ?? '',
        artist: _hostSongArtist ?? '',
        artUri: Uri.tryParse(_hostSongArt ?? ''),
        // Audio handler mutates extras (sets `url`), so this must NOT be const.
        extras: <String, dynamic>{'resultType': 'song', 'date': 0, 'url': ''},
      );
      try {
        await _audioHandler
            .customAction('setSourceNPlay', {'mediaItem': song});
      } catch (e) {
        debugPrint('[JamSession] setSourceNPlay failed: $e');
        _trackLoadInProgress = false;
        return;
      }
      _waitForTrackReady(id).then((_) {
        _trackLoadInProgress = false;
        // The drift loop will pick up from here using the latest anchor +
        // clock offset, so no explicit seek is needed.
      });
    }
  }

  /// Polls for up to ~5 s waiting for the audio handler to finish loading
  /// `expectedId`.
  Future<bool> _waitForTrackReady(String expectedId) async {
    for (int i = 0; i < 50; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_player.currentSong.value?.id == expectedId &&
          _player.isCurrentSongBuffered.value) {
        return true;
      }
    }
    return _player.currentSong.value?.id == expectedId;
  }

  void _startDriftLoop() {
    _driftTimer?.cancel();
    _driftTimer = Timer.periodic(
        const Duration(milliseconds: _driftTickMs), (_) => _onDriftTick());
  }

  void _onDriftTick() {
    if (role.value != JamRole.guest) return;
    if (_clockOffsetMs == null) return; // wait for first pong
    if (_trackLoadInProgress) return;
    final songId = _hostSongId;
    if (songId == null) return;
    final current = _player.currentSong.value;
    if (current?.id != songId) return;
    if (!_player.isCurrentSongBuffered.value) return;

    // Mirror play/pause first — no point correcting drift if we're not even
    // running in the same state as the host.
    final guestPlaying = _player.buttonState.value == PlayButtonState.playing;
    if (_hostPlaying && !guestPlaying) {
      _player.play();
      return;
    }
    if (!_hostPlaying && guestPlaying) {
      _player.pause();
    }
    if (!_hostPlaying) {
      _applyJamSpeed(1.0);
      // While paused, snap to anchor if we've drifted way off.
      final pos = _player.progressBarStatus.value.current.inMilliseconds;
      if ((pos - _anchorMs).abs() > 800 &&
          _now() - _lastSeekAtMs > _seekCooldownMs) {
        _lastSeekAtMs = _now();
        _player.seek(Duration(milliseconds: _anchorMs));
      }
      return;
    }

    // Playing: extrapolate target from anchor using host-side clock.
    final hostNow = _now() + _clockOffsetMs!;
    final targetMs = _anchorMs + (hostNow - _anchorAt);
    final playerMs = _player.progressBarStatus.value.current.inMilliseconds;
    final drift = playerMs - targetMs; // + = ahead of host, − = behind

    if (drift.abs() > _hardSeekDriftMs) {
      if (_now() - _lastSeekAtMs > _seekCooldownMs) {
        _lastSeekAtMs = _now();
        // Small forward bias accounts for the time it takes the audio engine
        // to actually start playing from the seek target.
        _player.seek(Duration(milliseconds: targetMs + 50));
        _applyJamSpeed(1.0);
        syncStatus.value = 'Re-syncing…';
      }
      return;
    }

    // Proportional rate nudge for sub-second drift. Positive drift → guest
    // is ahead → slow down (<1). Negative drift → speed up (>1).
    final factor = (drift / _hardSeekDriftMs).clamp(-1.0, 1.0);
    double targetSpeed = 1.0 - _maxRateNudge * factor;
    if (drift.abs() < _seekDeadbandMs) targetSpeed = 1.0;
    _applyJamSpeed(targetSpeed);
  }

  void _applyJamSpeed(double speed) {
    if ((speed - _currentJamSpeed).abs() < 0.002) return;
    _currentJamSpeed = speed;
    try {
      _audioHandler.customAction('jamSetSpeed', {'value': speed});
    } catch (_) {/* non-fatal */}
  }

  void _onGuestDisconnected() {
    if (role.value != JamRole.guest) return;
    state.value = JamState.idle;
    syncStatus.value = 'Disconnected from host';
    connectedPeers.value = 0;
    peers.clear();
    _driftTimer?.cancel();
    _driftTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _applyJamSpeed(1.0);
    update();
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────

  /// Best-effort friendly name for this device.
  String _detectMyName() {
    try {
      final host = Platform.localHostname.trim();
      final isPlaceholder = host.isEmpty ||
          host.toLowerCase() == 'localhost' ||
          host.toLowerCase().startsWith('localhost.');
      if (!isPlaceholder) return host;
    } catch (_) {/* hostname lookup can fail on locked-down platforms */}
    if (Platform.isAndroid) return 'Android Listener';
    if (Platform.isIOS) return 'iPhone Listener';
    if (Platform.isMacOS) return 'Mac Listener';
    if (Platform.isWindows) return 'Windows Listener';
    if (Platform.isLinux) return 'Linux Listener';
    return 'Listener';
  }

  String _generatePeerId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_rand.nextInt(1 << 32).toRadixString(36)}';

  /// Returns LAN-routable IPv4s in preference order:
  /// Tailscale (100.64/10) > 192.168.x > 10.x > 172.16-31.x > everything else.
  Future<List<String>> _detectLanIps() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    final addrs = <String>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        addrs.add(addr.address);
      }
    }
    int rank(String s) {
      if (_isTailscale(s)) return 0;
      if (s.startsWith('192.168.')) return 1;
      if (s.startsWith('10.')) return 2;
      if (_is172Private(s)) return 3;
      return 9;
    }
    addrs.sort((a, b) => rank(a).compareTo(rank(b)));
    return addrs;
  }

  bool _isTailscale(String s) {
    // Tailscale CGNAT range: 100.64.0.0 – 100.127.255.255
    if (!s.startsWith('100.')) return false;
    final parts = s.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 64 && second <= 127;
  }

  bool _is172Private(String s) {
    if (!s.startsWith('172.')) return false;
    final parts = s.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }

  /// Accepts `harmonyjam://host:port`, `http://host:port`, `ws://host:port`,
  /// `host:port`, or bare `host` (defaulting to [defaultPort]).
  static (String, int)? parseJoinUri(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      Uri u;
      if (trimmed.startsWith('$scheme://')) {
        u = Uri.parse(trimmed.replaceFirst('$scheme://', 'http://'));
      } else if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('ws://') ||
          trimmed.startsWith('wss://')) {
        u = Uri.parse(trimmed);
      } else if (trimmed.contains(':')) {
        u = Uri.parse('http://$trimmed');
      } else {
        u = Uri.parse('http://$trimmed:$defaultPort');
      }
      final host = u.host;
      if (host.isEmpty) return null;
      final port = u.hasPort ? u.port : defaultPort;
      return (host, port);
    } catch (_) {
      return null;
    }
  }

  void _forceHighQuality() {
    try {
      final box = Hive.box('AppPrefs');
      _prevQualityIndex = box.get('streamingQuality') as int?;
      if (_prevQualityIndex != 1) {
        box.put('streamingQuality', 1);
      }
    } catch (_) {/* settings not ready – non-fatal */}
  }

  void _restoreQuality() {
    try {
      if (_prevQualityIndex != null) {
        Hive.box('AppPrefs').put('streamingQuality', _prevQualityIndex);
      }
    } catch (_) {}
    _prevQualityIndex = null;
  }

  // ─── CLEANUP ───────────────────────────────────────────────────────────────

  Future<void> endSession() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _songWatcher?.dispose();
    _songWatcher = null;
    _playStateWatcher?.dispose();
    _playStateWatcher = null;
    _positionWatcher?.dispose();
    _positionWatcher = null;

    _driftTimer?.cancel();
    _driftTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;

    for (final c in _clientPeers.keys.toList()) {
      try {
        await c.close();
      } catch (_) {}
    }
    _clientPeers.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;

    await _clientSub?.cancel();
    _clientSub = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;

    // Restore default playback speed in case a guest session left a nudge in
    // place when it was torn down.
    if (_currentJamSpeed != 1.0) {
      try {
        await _audioHandler.customAction('jamSetSpeed', {'value': 1.0});
      } catch (_) {}
    }
    _currentJamSpeed = 1.0;

    _restoreQuality();
    _lastSeekAtMs = 0;
    _trackLoadInProgress = false;
    _hostSongId = null;
    _hostSongTitle = null;
    _hostSongArtist = null;
    _hostSongArt = null;
    _anchorMs = 0;
    _anchorAt = 0;
    _hostAnchorMs = 0;
    _hostAnchorAt = 0;
    _clockOffsetMs = null;
    _bestRttMs = 1 << 30;

    role.value = JamRole.none;
    state.value = JamState.idle;
    connectedPeers.value = 0;
    syncStatus.value = '';
    peers.clear();
    _selfPeer = null;
    joinUri = null;
    hostIps = <String>[];
    hostPort = null;
    update();
  }

  @override
  void onClose() {
    endSession();
    super.onClose();
  }
}
