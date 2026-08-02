/// A tiny in-memory [HttpClientAdapter] so repository tests can assert the
/// exact request a repository builds (path, method, body) and feed back a
/// canned response — without a mocking package or a real server.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One captured request.
class CapturedRequest {
  CapturedRequest({
    required this.method,
    required this.path,
    required this.body,
    required this.queryParameters,
  });

  final String method;
  final String path;

  /// The data the repository handed to Dio, before serialisation. Null for
  /// bodyless requests.
  final Map<String, dynamic>? body;
  final Map<String, dynamic> queryParameters;
}

/// Replays [responses] in order, one per request, and records what was sent.
///
/// ```dart
/// final adapter = FakeHttpAdapter([FakeResponse(body: {...})]);
/// final dio = Dio(BaseOptions(baseUrl: 'http://test'))
///   ..httpClientAdapter = adapter;
/// ```
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this._responses);

  final List<FakeResponse> _responses;
  final List<CapturedRequest> requests = [];

  /// The single request captured. Fails loudly if there was not exactly one.
  CapturedRequest get request {
    if (requests.length != 1) {
      throw StateError('expected exactly 1 request, got ${requests.length}');
    }
    return requests.first;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      CapturedRequest(
        method: options.method,
        path: options.path,
        body: options.data is Map<String, dynamic>
            ? Map<String, dynamic>.from(options.data as Map<String, dynamic>)
            : null,
        queryParameters: Map<String, dynamic>.from(options.queryParameters),
      ),
    );

    if (_responses.isEmpty) {
      throw StateError('FakeHttpAdapter ran out of canned responses');
    }
    final next = _responses.removeAt(0);

    return ResponseBody.fromString(
      jsonEncode(next.body),
      next.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class FakeResponse {
  const FakeResponse({required this.body, this.statusCode = 200});

  final Object body;
  final int statusCode;
}
