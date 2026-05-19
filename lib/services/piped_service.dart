import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';

class PipedServices extends GetxService {
  final Map<String, dynamic> _headers = {};
  final _dio = Dio();
  String _insApiUrl = "";
  bool _isLoggedIn = false;

  PipedServices() {
    final appPrefsBox = Hive.box('AppPrefs');
    final piped = appPrefsBox.get('piped') ??
        {"isLoggedIn": false, "token": "", "instApiUrl": ""};
    _isLoggedIn = piped["isLoggedIn"];
    if (isLoggedIn) {
      _headers["Authorization"] = piped['token'];
      _insApiUrl = piped["instApiUrl"];
    }
  }

  bool get isLoggedIn => _isLoggedIn;

  Future<Res> login(String insApiUrl, String userName, String password) async {
    final url = "$insApiUrl/login";
    try {
      final response = await _dio
          .post(url, data: {"username": userName, "password": password});
      final data = response.data;
      final appPrefsBox = Hive.box('AppPrefs');
      appPrefsBox.put("piped", {
        "isLoggedIn": true,
        "token": data['token'],
        "instApiUrl": insApiUrl
      });
      _headers["Authorization"] = data['token'];
      _isLoggedIn = true;
      _insApiUrl = insApiUrl;

      if (response.data.runtimeType.toString() == "_Map<String, dynamic>" &&
          response.data.containsKey("error")) {
        return Res(0, errorMessage: response.data['error']);
      }

      printINFO("Login successful! topken : ${data['token']}");
      return Res(1, response: response.data);
    } on DioException catch (e) {
      printERROR("Login Failed! => ${e.response?.statusMessage ?? e.message}");
      return Res(0, errorMessage: e.response?.statusMessage ?? e.message);
    }
  }

  void logout() {
    final appPrefsBox = Hive.box('AppPrefs');
    appPrefsBox
        .put("piped", {"isLoggedIn": false, "token": "", "instApiUrl": ""});
    _headers["Authorization"] = "";
    _isLoggedIn = false;
    _insApiUrl = "";
  }

  Future<Res> _sendRequest(String endpoint,
      {dynamic data,
      String reqType = "post",
      bool isInstanceListReq = false,
      bool isSongListReq = false}) async {
    final url = isInstanceListReq
        ? "https://piped-instances.kavin.rocks/"
        : "$_insApiUrl$endpoint";
    try {
      final response = reqType == "post"
          ? await _dio.post(
              url,
              data: data,
              options: Options(
                headers: _headers,
              ),
            )
          : await _dio.get(
              url,
              options: (isInstanceListReq || isSongListReq)
                  ? null
                  : Options(
                      headers: _headers,
                    ),
            );

      printINFO("Successful=> $endpoint");

      if (isInstanceListReq) {
        return Res(1,
            response: response.data
                .map((data) =>
                    PipedInstance(name: data['name'], apiUrl: data['api_url']))
                .toList());
      } else {
        if (response.data.runtimeType.toString() == "_Map<String, dynamic>" &&
            response.data.containsKey("error")) {
          return Res(0, errorMessage: response.data['error']);
        }
        return Res(1, response: response.data);
      }
    } on DioException catch (e) {
      printERROR("Error ! => ${e.response?.statusMessage ?? e.message}");
      return Res(0, errorMessage: e.response?.statusMessage ?? e.message);
    }
  }

  Future<Res> getAllInstanceList() async {
    return await _sendRequest("", isInstanceListReq: true, reqType: "get");
  }

  Future<Res> createPlaylist(String playlistName) async {
    return await _sendRequest("/user/playlists/create",
        data: {"name": playlistName});
  }

  Future<Res> getAllPlaylists() async {
    return await _sendRequest("/user/playlists", reqType: "get");
  }

  Future<Res> renamePlaylist(String plalistId, String newName) async {
    return await _sendRequest("/user/playlists/rename",
        data: {"playlistId": plalistId, "newName": newName});
  }

  Future<Res> deletePlaylist(String plalistId) async {
    return await _sendRequest("/user/playlists/delete",
        data: {"playlistId": plalistId});
  }

  Future<Res> addToPlaylist(String plalistId, List<String> videosId) async {
    return await _sendRequest("/user/playlists/add",
        data: {"playlistId": plalistId, "videoIds": videosId});
  }

  Future<Res> removeFromPlaylist(String plalistId, int index) async {
    return await _sendRequest("/user/playlists/remove",
        data: {"playlistId": plalistId, "index": index});
  }

  Future<List<MediaItem>> getPlaylistSongs(String playlistid) async {
    final res = await _sendRequest("/playlists/$playlistid",
        reqType: "get", isSongListReq: true);
    if (res.code == 1) {
      return (res.response['relatedStreams'])
          .map((item) {
            return MediaItem(
                id: (item['url']).split("?v=")[1],
                title: item['title'],
                artist: item['uploaderName'],
                duration: Duration(seconds: item['duration']),
                artUri: Uri.tryParse(
                  item['thumbnail'],
                ),
                extras: {
                  'artists': [
                    {"name": item['uploaderName']}
                  ],
                });
          })
          .whereType<MediaItem>()
          .toList();
    }
    return [];
  }

  /// Searches YouTube Music via a Piped instance.
  ///
  /// [filter] can be 'music_songs', 'music_videos', 'music_albums',
  /// 'music_playlists', or 'music_artists'. Defaults to 'music_songs'.
  /// Uses the user's configured Piped instance when logged in, otherwise
  /// falls back to the default public Piped instance.
  Future<List<MediaItem>> searchSongs(String query,
      {String filter = 'music_songs'}) async {
    const String defaultPipedUrl = "https://pipedapi.kavin.rocks";
    final baseUrl = _isLoggedIn ? _insApiUrl : defaultPipedUrl;
    try {
      final response = await _dio.get(
        "$baseUrl/search",
        queryParameters: {"q": query, "filter": filter},
      );
      if (response.statusCode == 200 && response.data['items'] != null) {
        final items = response.data['items'] as List;
        return items
            .where((item) => item['type'] == 'stream' && item['url'] != null)
            .map<MediaItem?>((item) {
              final url = item['url'] as String;
              final videoId =
                  url.contains('?v=') ? url.split('?v=').last : null;
              if (videoId == null || videoId.isEmpty) return null;
              final artistName = (item['uploaderName'] as String?) ?? 'Unknown';
              return MediaItem(
                id: videoId,
                title: (item['title'] as String?) ?? '',
                artist: artistName,
                duration: Duration(seconds: (item['duration'] as int?) ?? 0),
                artUri: Uri.tryParse((item['thumbnail'] as String?) ?? ''),
                extras: {
                  'artists': [
                    {'name': artistName, 'id': null}
                  ],
                  'resultType': filter == 'music_videos' ? 'video' : 'song',
                },
              );
            })
            .whereType<MediaItem>()
            .toList();
      }
    } on DioException catch (e) {
      printERROR("Piped search error: ${e.message}");
    }
    return [];
  }
}

class Res {
  final int code;
  final String? errorMessage;
  final dynamic response;
  Res(this.code, {this.errorMessage, this.response});
}

class PipedInstance {
  final String name;
  final String apiUrl;
  PipedInstance({required this.name, required this.apiUrl});
}
