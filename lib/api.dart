import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'chat_codec.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

class OpenWebUiApi {
  OpenWebUiApi({required String baseUrl, required this.token})
    : baseUrl = normalizeBaseUrl(baseUrl);

  final String baseUrl;
  final String token;

  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<Session> signIn({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/v1/auths/signin'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 30));

    final body = _decodeBody(_bodyOf(response));
    if (response.statusCode != 200) {
      throw ApiException(
        _detail(body) ?? 'Sign in failed (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    final data = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final token = data['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ApiException('The server did not return an auth token');
    }

    return Session(
      baseUrl: baseUrl,
      token: token,
      email: data['email']?.toString() ?? email.trim(),
      name: data['name']?.toString() ?? email.trim(),
      userId: data['id']?.toString() ?? '',
      avatarUrl: _absoluteUrl(data['profile_image_url']?.toString()),
    );
  }

  Future<Session> refreshProfile(Session session) async {
    final body = await _json('GET', '/api/v1/auths/');
    if (body is! Map) return session;
    return session.copyWith(
      name: body['name']?.toString(),
      avatarUrl: _absoluteUrl(body['profile_image_url']?.toString()),
    );
  }

  String _absoluteUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:')) {
      return path;
    }
    return path.startsWith('/') ? '$baseUrl$path' : '$baseUrl/$path';
  }

  Future<List<ModelOption>> fetchModels() async {
    final body = await _json('GET', '/api/models');
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! List) return const [];

    final seen = <String>{};
    final models = <ModelOption>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      final option = ModelOption.fromJson(item);
      if (option.id.isEmpty || !seen.add(option.id)) continue;
      models.add(option);
    }
    return models;
  }

  Future<ServerConfig> fetchConfig() async {
    final body = await _json('GET', '/api/config');
    if (body is! Map) return const ServerConfig();
    final features = body['features'];
    final permissions = body['permissions'];
    final file = body['file'];
    return ServerConfig(
      features: features is Map
          ? Map<String, dynamic>.from(features)
          : const {},
      permissions: permissions is Map
          ? Map<String, dynamic>.from(permissions)
          : const {},
      maxFileSize: file is Map ? (file['max_size'] as num?)?.toInt() : null,
      maxFileCount: file is Map ? (file['max_count'] as num?)?.toInt() : null,
      version: (body['version'] ?? '').toString(),
    );
  }

  /// Chat permissions (permissions.chat.temporary / temporary_enforced) and
  /// the user's ui.temporaryChatByDefault setting.
  Future<ChatPrefs> fetchChatPrefs() async {
    final auth = await _json('GET', '/api/v1/auths/');
    var allowed = false;
    var enforced = false;
    if (auth is Map) {
      final permissions = auth['permissions'];
      final chat = permissions is Map ? permissions['chat'] : null;
      if (chat is Map) {
        allowed = chat['temporary'] == true;
        enforced = chat['temporary_enforced'] == true;
      }
    }

    var byDefault = false;
    try {
      final settings = await _json('GET', '/api/v1/users/user/settings');
      final ui = settings is Map ? settings['ui'] : null;
      if (ui is Map) byDefault = ui['temporaryChatByDefault'] == true;
    } on ApiException catch (error) {
      if (error.isUnauthorized) rethrow;
    }

    return ChatPrefs(
      temporaryAllowed: allowed || enforced,
      temporaryEnforced: enforced,
      temporaryByDefault: byDefault,
    );
  }

  Future<List<ToolInfo>> fetchTools() async {
    final body = await _json('GET', '/api/v1/tools/');
    if (body is! List) return const [];
    final seen = <String>{};
    final tools = <ToolInfo>[];
    for (final item in body) {
      if (item is! Map) continue;
      final tool = ToolInfo.fromJson(Map<String, dynamic>.from(item));
      if (tool.id.isEmpty || !seen.add(tool.id)) continue;
      tools.add(tool);
    }
    return tools;
  }

  Future<List<ChatSummary>> listChats({int page = 1}) async {
    final body = await _json('GET', '/api/v1/chats/?page=$page');
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic>) ChatSummary.fromJson(item),
    ];
  }

  Future<List<ChatSummary>> listPinnedChats() async {
    final body = await _json('GET', '/api/v1/chats/pinned');
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic>)
          ChatSummary.fromJson(item).copyWith(pinned: true),
    ];
  }

  Future<List<ChatSummary>> listArchivedChats({int page = 1}) async {
    final body = await _json('GET', '/api/v1/chats/archived?page=$page');
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic>)
          ChatSummary.fromJson(item).copyWith(archived: true),
    ];
  }

  Future<List<ChatSummary>> searchChats(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final body = await _json('GET', '/api/v1/chats/search?text=$encoded');
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic>) ChatSummary.fromJson(item),
    ];
  }

  Future<LoadedChat> getChat(String id) async {
    final body = await _json('GET', '/api/v1/chats/$id');
    if (body is! Map<String, dynamic>) {
      throw ApiException('Unexpected server response');
    }
    return ChatCodec.decode(body);
  }

  Future<void> renameChat(String id, String title) async {
    await _json('POST', '/api/v1/chats/$id', {
      'chat': {'title': title},
    });
  }

  Future<void> deleteChat(String id) async {
    await _json('DELETE', '/api/v1/chats/$id');
  }

  Future<void> pinChat(String id) async {
    await _json('POST', '/api/v1/chats/$id/pin');
  }

  Future<void> archiveChat(String id) async {
    await _json('POST', '/api/v1/chats/$id/archive');
  }

  Future<String> cloneChat(String id, String title) async {
    final body = await _json('POST', '/api/v1/chats/$id/clone', {
      'title': title,
    });
    final newId = body is Map ? body['id']?.toString() : null;
    if (newId == null || newId.isEmpty) {
      throw ApiException('The server did not return the cloned chat id');
    }
    return newId;
  }

  /// Saves a finished conversation on the server (used by the assistant).
  Future<String> importChat({
    required String title,
    required String model,
    required List<ChatMessage> messages,
  }) async {
    final map = <String, dynamic>{};
    final list = <Map<String, dynamic>>[];
    String? parent;
    for (final message in messages) {
      final entry = <String, dynamic>{
        'id': message.id,
        'parentId': parent,
        'childrenIds': <String>[],
        'role': message.role,
        'content': message.content,
        'timestamp': message.timestamp,
        if (message.isAssistant) 'model': model,
        if (message.isAssistant) 'modelName': model,
        if (message.isAssistant) 'done': true,
        if (message.attachments.isNotEmpty)
          'files': message.attachments.map((item) => item.toJson()).toList(),
        if (message.output.isNotEmpty) 'output': message.output,
        if (message.sources.isNotEmpty) 'sources': <dynamic>[],
      };
      if (parent != null) {
        (map[parent]['childrenIds'] as List<String>).add(message.id);
      }
      map[message.id] = entry;
      list.add(entry);
      parent = message.id;
    }
    final trimmed = title.trim();
    final chat = <String, dynamic>{
      'title': trimmed.isEmpty
          ? 'Chat'
          : (trimmed.length > 60 ? trimmed.substring(0, 60) : trimmed),
      'models': [model],
      'params': <String, dynamic>{},
      'history': {'messages': map, 'currentId': parent},
      'messages': list,
      'tags': <String>[],
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    final body = await _json('POST', '/api/v1/chats/new', {'chat': chat});
    final id = body is Map ? body['id']?.toString() : null;
    if (id == null || id.isEmpty) {
      throw ApiException('The server did not return the chat id');
    }
    return id;
  }

  Future<void> stopGeneration(String chatId) async {
    await _json('POST', '/api/tasks/chat/$chatId/stop');
  }

  Future<void> resolveToolCall({
    required String chatId,
    required String messageId,
    required String callId,
    String action = 'answer',
    Map<String, dynamic>? answers,
    bool timedOut = false,
  }) async {
    await _json('POST', '/api/v1/chats/$chatId/messages/$messageId/resolve', {
      'call_id': callId,
      'action': action,
      'answers': ?answers,
      if (timedOut) 'timed_out': true,
    });
  }

  Future<ChatAttachment> uploadFile({
    required String filename,
    required Uint8List bytes,
    required String contentType,
    bool process = true,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/files/?process=$process'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/json';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: MediaType.parse(
          contentType.isEmpty ? 'application/octet-stream' : contentType,
        ),
      ),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    final body = _decodeBody(_bodyOf(response));
    if (response.statusCode == 401) {
      throw ApiException('Session expired', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        _detail(body) ?? 'Upload failed (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    if (body is! Map) throw ApiException('Unexpected upload response');

    final meta = body['meta'];
    final metaMap = meta is Map ? Map<String, dynamic>.from(meta) : const {};
    final id = body['id']?.toString() ?? '';
    final type =
        (metaMap['content_type']?.toString() ?? contentType).startsWith(
          'image/',
        )
        ? 'image'
        : 'file';
    return ChatAttachment(
      id: id,
      name: (body['filename'] ?? filename).toString(),
      type: type,
      url: id,
      contentType: (metaMap['content_type'] ?? contentType).toString(),
      size: (metaMap['size'] as num?)?.toInt() ?? bytes.length,
    );
  }

  Future<Uint8List> downloadFile(String id) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/v1/files/$id/content'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw ApiException(
        'Could not download file (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  Future<Uint8List> fetchImage(String path) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$baseUrl$path');
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw ApiException(
        'Could not load image (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  /// Connects to the Open WebUI socket.io endpoint.
  ///
  /// Chat events arrive through `events`: reasoning, tool calls, statuses and
  /// background tasks (chat title).
  io.Socket connectSocket({
    required void Function(ChatEvent event, void Function(Object?)? ack)
    onEvent,
    void Function(Object error)? onError,
    void Function()? onConnect,
    void Function()? onDisconnect,
  }) {
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setPath('/ws/socket.io')
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    socket.onConnect((_) {
      socket.emit('user-join', {
        'auth': {'token': token},
      });
      onConnect?.call();
    });
    socket.on('events', (payload, [Function? ack]) {
      final event = ChatEvent.fromPayload(payload);
      if (event == null) return;
      onEvent(event, ack == null ? null : (response) => ack(response));
    });
    socket.onConnectError((error) => onError?.call(error ?? 'connect error'));
    socket.onError((error) => onError?.call(error ?? 'socket error'));
    socket.onDisconnect((_) => onDisconnect?.call());
    socket.connect();
    return socket;
  }

  /// Sends a message. The server creates/updates the chat and stores the
  /// reply, and reports progress through socket.io events.
  Future<String?> sendMessage({
    required String model,
    required List<ChatMessage> history,
    required ChatMessage userMessage,
    required ChatMessage assistantMessage,
    String? chatId,
    String? sessionId,
    bool temporary = false,
    String? parentId,
    ChatFeatures features = const ChatFeatures(),
    List<String> toolIds = const [],
    List<ToolInfo> toolServers = const [],
  }) async {
    final messages = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.isNotice || message.content.trim().isEmpty) continue;
      messages.add(message.toJson());
    }

    final files = userMessage.attachments.map((item) => item.toJson()).toList();

    final body = <String, dynamic>{
      'stream': true,
      'model': model,
      'messages': messages,
      'params': <String, dynamic>{},
      'files': files.isEmpty ? null : files,
      'tool_ids': toolIds.isEmpty ? null : toolIds,
      'features': features.toJson(),
      'variables': <String, dynamic>{},
      'session_id': sessionId,
      'id': assistantMessage.id,
      'parent_id': parentId,
      'user_message': {
        'id': userMessage.id,
        'parentId': userMessage.parentId,
        'childrenIds': [assistantMessage.id],
        'role': 'user',
        'content': userMessage.content,
        'timestamp': userMessage.timestamp,
        'models': [model],
        if (files.isNotEmpty) 'files': files,
      },
      'background_tasks': <String, dynamic>{
        'title_generation': !temporary,
        'tags_generation': !temporary,
        'follow_up_generation': false,
      },
    };
    if (chatId != null && chatId.isNotEmpty) body['chat_id'] = chatId;
    if (toolServers.isNotEmpty) {
      body['tool_servers'] = [
        for (final server in toolServers)
          if (server.id.startsWith('server:')) {'id': server.id},
      ];
    }

    final body$ = {
      ...body,
      if (body['files'] == null) 'files': <dynamic>[],
      if (body['tool_ids'] == null) 'tool_ids': <dynamic>[],
    };

    final result = await _json('POST', '/api/chat/completions', body$);
    if (result is Map) {
      final newChatId = result['chat_id']?.toString();
      if (newChatId != null && newChatId.isNotEmpty) return newChatId;
    }
    return null;
  }

  Future<Object?> _json(String method, String path, [Object? payload]) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final Future<http.Response> request;
      switch (method) {
        case 'GET':
          request = http.get(uri, headers: _headers);
        case 'DELETE':
          request = http.delete(uri, headers: _headers);
        default:
          request = http.post(
            uri,
            headers: _headers,
            body: payload == null ? null : jsonEncode(payload),
          );
      }
      final response = await request.timeout(const Duration(seconds: 30));
      final body = _decodeBody(_bodyOf(response));
      if (response.statusCode == 401) {
        throw ApiException('Session expired', statusCode: 401);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _detail(body) ?? 'Server error (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return body;
    } on TimeoutException {
      throw ApiException('The server did not respond in time');
    } on ApiException {
      rethrow;
    } on SocketException catch (error) {
      throw ApiException('Network error: ${error.message}');
    } catch (error) {
      throw ApiException('Network error: $error');
    }
  }

  String _bodyOf(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  Object? _decodeBody(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  String? _detail(Object? body) {
    if (body is Map) {
      final detail = body['detail'] ?? body['error'];
      if (detail is String && detail.isNotEmpty) return detail;
      if (detail is Map && detail['message'] is String) {
        return detail['message'] as String;
      }
      if (detail != null) return detail.toString();
    }
    if (body is String && body.isNotEmpty && body.length < 500) return body;
    return null;
  }
}
