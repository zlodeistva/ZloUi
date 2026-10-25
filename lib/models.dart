import 'dart:convert';
import 'dart:math';

String newId() {
  final random = Random.secure();
  String hex(int length) =>
      List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  final variant = (8 + random.nextInt(4)).toRadixString(16);
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// Link to a source (web search result, document).
class SourceLink {
  const SourceLink({required this.title, required this.url});

  final String title;
  final String url;
}

/// Extracts links from `source` events and the message `sources` field.
List<SourceLink> sourceLinksFrom(Object? raw) {
  final result = <SourceLink>[];

  void add(String? url, String? title) {
    if (url == null || !url.startsWith('http')) return;
    if (result.any((link) => link.url == url)) return;
    result.add(
      SourceLink(
        title: (title == null || title.isEmpty) ? url : title,
        url: url,
      ),
    );
  }

  void walk(Object? node) {
    if (node is List) {
      for (final item in node) {
        walk(item);
      }
      return;
    }
    if (node is! Map) return;

    final source = node['source'];
    if (source is Map) {
      add(source['url']?.toString(), source['name']?.toString());
      final urls = source['urls'];
      if (urls is List) {
        for (final url in urls) {
          add(url?.toString(), null);
        }
      }
    }
    final metadata = node['metadata'];
    if (metadata is List) {
      for (final item in metadata) {
        if (item is Map) {
          add(
            item['source']?.toString(),
            (item['title'] ?? item['name'])?.toString(),
          );
        }
      }
    }
    add(node['url']?.toString(), (node['title'] ?? node['name'])?.toString());
  }

  walk(raw);
  return result;
}

/// A tool / MCP call inside an assistant reply.
class ToolCall {
  ToolCall({
    required this.id,
    required this.name,
    this.arguments = '',
    this.status = 'in_progress',
    this.result,
  });

  final String id;
  final String name;
  String arguments;
  String status;
  String? result;

  String get displayName {
    if (name.startsWith('mcp__')) {
      final parts = name.split('__');
      return parts.length > 2 ? parts.sublist(2).join('__') : name;
    }
    return name;
  }

  /// A call is done once its result arrived: the server marks the
  /// function_call itself as completed right after sending it.
  bool get isDone =>
      status == 'incomplete' ||
      status == 'failed' ||
      status == 'rejected' ||
      result != null;
}

/// An attachment of a message.
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
    required this.type,
    this.url = '',
    this.contentType = '',
    this.size = 0,
    this.content,
    this.localBytes,
  });

  final String id;
  final String name;

  /// file | image | text | collection
  final String type;
  final String url;
  final String contentType;
  final int size;

  /// Text extracted locally (for temporary chats).
  final String? content;

  /// Bytes of a locally picked file (preview before/without upload).
  final List<int>? localBytes;

  bool get isImage => type == 'image' || contentType.startsWith('image/');

  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'url': url.isEmpty ? id : url,
    'name': name,
    'status': 'uploaded',
    if (contentType.isNotEmpty) 'content_type': contentType,
    if (size > 0) 'size': size,
    if (content != null) 'content': content,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? 'file').toString();
    final contentType = (json['content_type'] ?? '').toString();
    final id = (json['id'] ?? '').toString();
    return ChatAttachment(
      id: id,
      name: (json['name'] ?? '').toString(),
      type: type == 'image' || contentType.startsWith('image/')
          ? 'image'
          : type,
      url: (json['url'] ?? id).toString(),
      contentType: contentType,
      size: (json['size'] as num?)?.toInt() ?? 0,
      content: json['content'] as String?,
    );
  }
}

class ChatMessage {
  ChatMessage({
    String? id,
    this.parentId,
    required this.role,
    String? content,
    int? timestamp,
    this.model,
    this.isNotice = false,
    this.attachments = const [],
    this.toolCalls = const [],
    this.output = const [],
    this.sources = const [],
    this.done = true,
    this.reasoning = '',
    this.statusText,
    this.usage,
  }) : id = id ?? newId(),
       content = content ?? '',
       timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final String id;
  String? parentId;
  final String role;
  String content;
  final int timestamp;
  final String? model;

  /// Local notice (error, stop): never sent to the model or saved on the
  /// server.
  bool isNotice;
  List<ChatAttachment> attachments;
  List<ToolCall> toolCalls;
  List<Map<String, dynamic>> output;
  List<SourceLink> sources;
  bool done;
  String reasoning;
  String? statusText;
  bool statusDone = false;
  Map<String, dynamic>? usage;

  bool get isAssistant => role == 'assistant';

  String get plainText => content;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (attachments.isNotEmpty)
      'files': attachments.map((item) => item.toJson()).toList(),
  };
}

class ModelOption {
  const ModelOption({
    required this.id,
    required this.name,
    this.capabilities,
    this.toolIds = const [],
    this.defaultFeatureIds = const [],
  });

  final String id;
  final String name;
  final Map<String, dynamic>? capabilities;

  /// Tools enabled for the model by default on the server.
  final List<String> toolIds;

  /// Features (web_search, code_interpreter, image_generation) enabled for
  /// the model by default on the server.
  final List<String> defaultFeatureIds;

  bool capability(String name, {bool fallback = true}) {
    final value = capabilities?[name];
    return value is bool ? value : fallback;
  }

  factory ModelOption.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final name = (json['name'] ?? '').toString();
    final info = json['info'];
    final meta = info is Map ? info['meta'] : null;
    final capabilities = meta is Map ? meta['capabilities'] : null;
    final toolIds = meta is Map ? meta['toolIds'] : null;
    final featureIds = meta is Map ? meta['defaultFeatureIds'] : null;
    return ModelOption(
      toolIds: toolIds is List
          ? [for (final id in toolIds) id.toString()]
          : const [],
      defaultFeatureIds: featureIds is List
          ? [for (final id in featureIds) id.toString()]
          : const [],
      id: id,
      name: name.isEmpty ? id : name,
      capabilities: capabilities is Map
          ? Map<String, dynamic>.from(capabilities)
          : null,
    );
  }
}

class Session {
  const Session({
    required this.baseUrl,
    required this.token,
    required this.email,
    required this.name,
    this.userId = '',
    this.avatarUrl = '',
  });

  final String baseUrl;
  final String token;
  final String email;
  final String name;
  final String userId;
  final String avatarUrl;

  Session copyWith({String? name, String? avatarUrl}) => Session(
    baseUrl: baseUrl,
    token: token,
    email: email,
    name: name ?? this.name,
    userId: userId,
    avatarUrl: avatarUrl ?? this.avatarUrl,
  );
}

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.pinned = false,
    this.archived = false,
  });

  final String id;
  final String title;
  final int updatedAt;
  final bool pinned;
  final bool archived;

  ChatSummary copyWith({String? title, bool? pinned, bool? archived}) =>
      ChatSummary(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt,
        pinned: pinned ?? this.pinned,
        archived: archived ?? this.archived,
      );

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    final title = (json['title'] ?? '').toString();
    return ChatSummary(
      id: (json['id'] ?? '').toString(),
      title: title.isEmpty ? 'Chat' : title,
      updatedAt: (json['updated_at'] as num?)?.toInt() ?? 0,
      pinned: json['pinned'] == true,
      archived: json['archived'] == true,
    );
  }
}

class LoadedChat {
  const LoadedChat({
    required this.id,
    required this.title,
    required this.model,
    required this.messages,
    this.pinned = false,
    this.archived = false,
  });

  final String id;
  final String title;
  final String? model;
  final List<ChatMessage> messages;
  final bool pinned;
  final bool archived;
}

/// Permissions and settings of temporary chats.
class ChatPrefs {
  const ChatPrefs({
    this.temporaryAllowed = false,
    this.temporaryEnforced = false,
    this.temporaryByDefault = false,
  });

  final bool temporaryAllowed;
  final bool temporaryEnforced;
  final bool temporaryByDefault;
}

class ServerConfig {
  const ServerConfig({
    this.features = const {},
    this.permissions = const {},
    this.maxFileSize,
    this.maxFileCount,
    this.version = '',
  });

  final Map<String, dynamic> features;
  final Map<String, dynamic> permissions;
  final int? maxFileSize;
  final int? maxFileCount;
  final String version;

  bool feature(String name) => features[name] == true;

  bool permission(String path, {bool fallback = true}) {
    Object? current = permissions;
    for (final key in path.split('.')) {
      if (current is! Map) return fallback;
      current = current[key];
    }
    return current is bool ? current : fallback;
  }
}

class ToolInfo {
  const ToolInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.isMcp = false,
  });

  final String id;
  final String name;
  final String description;
  final bool isMcp;

  factory ToolInfo.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final meta = json['meta'];
    return ToolInfo(
      id: id,
      name: (json['name'] ?? id).toString(),
      description: meta is Map ? (meta['description'] ?? '').toString() : '',
      isMcp: id.startsWith('server:'),
    );
  }
}

/// Feature flags toggled from the tools sheet.
class ChatFeatures {
  const ChatFeatures({
    this.webSearch = false,
    this.codeInterpreter = false,
    this.imageGeneration = false,
    this.memory = true,
  });

  final bool webSearch;
  final bool codeInterpreter;
  final bool imageGeneration;
  final bool memory;

  ChatFeatures copyWith({
    bool? webSearch,
    bool? codeInterpreter,
    bool? imageGeneration,
    bool? memory,
  }) => ChatFeatures(
    webSearch: webSearch ?? this.webSearch,
    codeInterpreter: codeInterpreter ?? this.codeInterpreter,
    imageGeneration: imageGeneration ?? this.imageGeneration,
    memory: memory ?? this.memory,
  );

  Map<String, dynamic> toJson() => {
    'web_search': webSearch,
    'code_interpreter': codeInterpreter,
    'image_generation': imageGeneration,
    'memory': memory,
    'voice': false,
  };
}

class ChatEvent {
  const ChatEvent({
    required this.chatId,
    required this.messageId,
    required this.type,
    this.payload,
  });

  final String chatId;
  final String messageId;
  final String type;
  final Object? payload;

  Map<String, dynamic>? get data =>
      payload is Map ? Map<String, dynamic>.from(payload as Map) : null;

  String? get text => payload is String ? payload as String : null;

  static ChatEvent? fromPayload(Object? payload) {
    if (payload is! Map) return null;
    final data = payload['data'];
    if (data is! Map) return null;
    return ChatEvent(
      chatId: (payload['chat_id'] ?? '').toString(),
      messageId: (payload['message_id'] ?? '').toString(),
      type: (data['type'] ?? '').toString(),
      payload: data['data'],
    );
  }
}

String prettyJson(String raw) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
  } catch (_) {
    return raw;
  }
}

/// Request from the assistant window to open the app: new or saved chat.
class AssistRequest {
  const AssistRequest(this.id, [this.chatId]);

  final int id;
  final String? chatId;
}
