import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

typedef Json = Map<String, dynamic>;

/// An error answer from the API (or a failure to reach it), already in words a person can read.
class ApiException implements Exception {
  ApiException(this.message, {this.code = 'error', this.status = 0, this.errors = const {}});

  final String message;
  final String code;
  final int status;

  /// Field errors: `{field: [messages]}`.
  final Map<String, dynamic> errors;

  bool get isOffline => status == 0;

  @override
  String toString() => message;
}

/// Where the access and refresh tokens are kept between launches.
abstract class TokenStore {
  Future<Map<String, String?>> read();
  Future<void> write({required String? access, required String? refresh});
}

class MemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;

  @override
  Future<Map<String, String?>> read() async => {'access': access, 'refresh': refresh};

  @override
  Future<void> write({required String? access, required String? refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }
}

/// Talks to the TuitionTrack REST API: adds the bearer token, renews it once
/// when it has expired, follows pagination and turns error bodies into
/// [ApiException]s.
class ApiClient {
  ApiClient({required String baseUrl, required this.tokens, http.Client? client})
      : _http = client ?? http.Client(),
        _baseUrl = _clean(baseUrl);

  static const _prefix = '/api/v1';
  static const _timeout = Duration(seconds: 30);

  final http.Client _http;
  final TokenStore tokens;
  String _baseUrl;
  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Counts how many responses came back without a usable time header. When
  /// the app has been running for a while and this stays at zero we are confident
  /// that exam timers follow the server clock; when it climbs the UI can warn.
  int responsesWithoutClockHeader = 0;

  /// Called when the session can no longer be renewed (signed out elsewhere, expired).
  void Function()? onSessionExpired;

  /// Difference between the server clock and this device's, so exam timers follow the server.
  Duration serverOffset = Duration.zero;

  String get baseUrl => _baseUrl;
  set baseUrl(String value) => _baseUrl = _clean(value);
  bool get hasSession => _refresh != null && _refresh!.isNotEmpty;
  DateTime get serverNow => DateTime.now().add(serverOffset);

  static String _clean(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isNotEmpty && !value.startsWith('http://') && !value.startsWith('https://')) value = 'http://$value';
    return value;
  }

  /// Turns a stored file path ("/media/…") into an address this device can open.
  String mediaUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$_baseUrl${url.startsWith('/') ? '' : '/'}$url';
  }

  Future<void> loadTokens() async {
    final saved = await tokens.read();
    _access = saved['access'];
    _refresh = saved['refresh'];
  }

  Future<void> setTokens(String? access, String? refresh) async {
    _access = access;
    _refresh = refresh;
    await tokens.write(access: access, refresh: refresh);
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final clean = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && '$value'.isNotEmpty) clean[key] = '$value';
    });
    final uri = Uri.parse(path.startsWith('http') ? path : '$_baseUrl$_prefix$path');
    return clean.isEmpty ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...clean});
  }

  Map<String, String> _headers({bool json = true}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_access != null && _access!.isNotEmpty) 'Authorization': 'Bearer $_access',
      };

  Future<http.Response> _send(String method, Uri uri, Object? body) async {
    final request = http.Request(method, uri)..headers.addAll(_headers());
    if (body != null) request.body = jsonEncode(body);
    try {
      return await http.Response.fromStream(await _http.send(request).timeout(_timeout));
    } on TimeoutException {
      throw ApiException('The server took too long to answer. Check your connection and try again.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Cannot reach the server. Check your internet connection and the server address.');
    }
  }

  /// Renews the access token. Parallel callers share one request.
  Future<bool> _renew() {
    return _refreshing ??= () async {
      try {
        if (!hasSession) return false;
        final response = await _http
            .post(
              _uri('/auth/token/refresh/'),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({'refresh': _refresh}),
            )
            .timeout(_timeout);
        if (response.statusCode != 200) {
          // Only a definite refusal ends the session; a server hiccup must not sign anyone out.
          if (response.statusCode == 401 || response.statusCode == 400) {
            await setTokens(null, null);
            onSessionExpired?.call();
          }
          return false;
        }
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
        await setTokens(data['access'] as String?, (data['refresh'] as String?) ?? _refresh);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  dynamic _decode(http.Response response) {
    final header = _bestClockHeader(response);
    _syncClock(header);
    if (header == null) responsesWithoutClockHeader++;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    dynamic data;
    if (text.isNotEmpty && (response.headers['content-type'] ?? '').contains('json')) {
      try {
        data = jsonDecode(text);
      } catch (_) {
        data = null;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    if ([502, 503, 504].contains(response.statusCode)) {
      throw ApiException('The server is not available right now. Please try again in a moment.', status: response.statusCode);
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = [map['message'], map['error'], map['detail']].whereType<String>().firstWhere(
            (m) => m.isNotEmpty,
            orElse: () => 'The request could not be completed.',
          );
      throw ApiException(
        message,
        code: map['code'] is String ? map['code'] as String : 'error',
        status: response.statusCode,
        errors: map['errors'] is Map ? Map<String, dynamic>.from(map['errors'] as Map) : const {},
      );
    }
    throw ApiException(
      response.statusCode >= 500 ? 'Something went wrong on the server. Please try again.' : 'The request could not be completed.',
      status: response.statusCode,
    );
  }

  void _syncClock(String? header) {
    final raw = header;
    if (raw == null || raw.isEmpty) return;
    try {
      final server = parseHttpDate(raw);
      final offset = server.difference(DateTime.now().toUtc());
      // The Date header has one-second precision; ignore jitter smaller than that.
      if (offset.abs() > const Duration(seconds: 2) || serverOffset.abs() > const Duration(seconds: 2)) {
        serverOffset = offset;
      }
    } catch (e) {
      // not a date we can read; keep the previous offset
      developer.log('Clock sync header was rejected: $raw ($e)', name: 'TuitionTrack');
    }
  }

  /// Picks the best timestamp off an HTTP response, falling back from `date`
  /// (which Django doesn't always emit) to `last-modified` and finally to the
  /// response's own request time as a last resort.
  String? _bestClockHeader(http.Response response) {
    final headers = response.headers;
    return headers['date'] ?? headers['last-modified'] ?? headers['x-server-time'];
  }

  Future<dynamic> _request(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    final uri = _uri(path, query);
    var response = await _send(method, uri, body);
    if (response.statusCode == 401 && hasSession && !path.startsWith('/auth/token')) {
      if (await _renew()) {
        response = await _send(method, uri, body);
      }
    }
    return _decode(response);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _request('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _request('POST', path, body: body ?? const <String, dynamic>{});
  Future<dynamic> patch(String path, [Object? body]) => _request('PATCH', path, body: body ?? const <String, dynamic>{});
  Future<dynamic> delete(String path) => _request('DELETE', path);

  /// A whole list, whether the endpoint answers with a bare array or with pages.
  Future<List<Json>> list(String path, {Map<String, dynamic>? query}) async {
    dynamic data = await get(path, query: {'page_size': 200, ...?query});
    final items = <Json>[];
    var guard = 0;
    while (true) {
      if (data is List) {
        items.addAll(data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
        return items;
      }
      if (data is! Map) return items;
      final results = data['results'];
      if (results is List) items.addAll(results.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      final next = data['next'];
      if (next is! String || next.isEmpty || ++guard > 50) return items;
      // The server builds `next` from the host it sees; keep our own origin and take only the path.
      final nextUri = Uri.parse(next);
      data = await _request('GET', '$_baseUrl${nextUri.path}${nextUri.hasQuery ? '?${nextUri.query}' : ''}');
    }
  }

  /// Uploads one picture or PDF and returns its stored address (relative, e.g. "/media/uploads/…").
  Future<String> upload(Uint8List bytes, String filename) async {
    Future<http.Response> attempt() async {
      final request = http.MultipartRequest('POST', _uri('/media/upload/'))
        ..headers.addAll(_headers(json: false))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _mediaType(filename)));
      try {
        return await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 90)));
      } on TimeoutException {
        throw ApiException('The upload took too long. Check your connection and try again.');
      } catch (_) {
        throw ApiException('Cannot reach the server. Check your internet connection and try again.');
      }
    }

    var response = await attempt();
    if (response.statusCode == 401 && hasSession && await _renew()) response = await attempt();
    final data = _decode(response);
    final url = data is Map ? data['url'] : null;
    if (url is! String || !(url.startsWith('/media/') || url.startsWith('http://') || url.startsWith('https://'))) {
      throw ApiException(
        'The upload did not return a media path; please try again.',
        code: 'upload_invalid_url',
      );
    }
    return url;
  }

  static MediaType _mediaType(String filename) {
    final name = filename.toLowerCase();
    if (name.endsWith('.png')) return MediaType('image', 'png');
    if (name.endsWith('.webp')) return MediaType('image', 'webp');
    if (name.endsWith('.pdf')) return MediaType('application', 'pdf');
    return MediaType('image', 'jpeg');
  }
}
