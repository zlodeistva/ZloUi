import 'dart:convert';

import 'models.dart';

/// A shared socket can receive events for other chats and previous replies.
bool isCurrentChatEvent(
  ChatEvent event, {
  required String? chatId,
  required String? streamingMessageId,
  required Iterable<String> messageIds,
}) {
  if (event.messageId.isNotEmpty && event.messageId == streamingMessageId) {
    return true;
  }
  if (chatId != null && event.chatId == chatId) return true;
  return chatId == null &&
      (event.chatId.startsWith('temporary:') ||
          event.chatId.startsWith('local:')) &&
      event.messageId.isNotEmpty &&
      messageIds.contains(event.messageId);
}

/// Applies `response:completion` events to the accumulated output array
/// (mirrors applyResponseStreamEvent from the Open WebUI web client).
List<Map<String, dynamic>> applyResponseEvent(
  List<Map<String, dynamic>> output,
  Map<String, dynamic> event,
) {
  final eventType = (event['type'] ?? '').toString();
  if (!eventType.startsWith('response.')) return output;

  final next = [for (final item in output) Map<String, dynamic>.from(item)];

  int findIndex(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    final callId = item['call_id']?.toString();
    for (var i = 0; i < next.length; i++) {
      final candidate = next[i];
      if ((id != null && candidate['id'] == id) ||
          (callId != null &&
              candidate['call_id'] == callId &&
              candidate['type'] == item['type'])) {
        return i;
      }
    }
    return -1;
  }

  int outputIndex(Map<String, dynamic> item) {
    final found = findIndex(item);
    if (found >= 0) return found;
    return (event['output_index'] as num?)?.toInt() ?? next.length;
  }

  if (eventType == 'response.completed') {
    final response = event['response'];
    final responseOutput = response is Map ? response['output'] : null;
    if (responseOutput is! List || responseOutput.isEmpty) return output;
    for (final raw in responseOutput) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final index = findIndex(item);
      if (index >= 0) {
        next[index] = item;
      } else {
        next.add(item);
      }
    }
    return next;
  }

  if (eventType == 'response.output_item.added' ||
      eventType == 'response.output_item.done') {
    final raw = event['item'];
    if (raw is! Map) return output;
    final item = Map<String, dynamic>.from(raw);
    final index = findIndex(item);
    if (index >= 0) {
      if (eventType == 'response.output_item.added') {
        // A creation event can arrive after deltas. Keep accumulated data,
        // while filling in metadata (type, name, call_id) from the real item.
        final existing = next[index];
        next[index] = {...existing, ...item};
        for (final field in ['content', 'summary', 'arguments', 'code']) {
          final value = existing[field];
          if ((value is String && value.isNotEmpty) ||
              (value is List && value.isNotEmpty)) {
            next[index][field] = value;
          }
        }
      } else {
        next[index] = item;
      }
    } else {
      final target = outputIndex(item);
      if (target < 0) return output;
      if (target < next.length) {
        next.insert(target, item);
      } else {
        next.add(item);
      }
    }
    return next;
  }

  if (!eventType.endsWith('.delta') &&
      !eventType.endsWith('.done') &&
      eventType != 'response.content_part.added' &&
      eventType != 'response.reasoning_summary_part.added') {
    return output;
  }

  final itemId = event['item_id']?.toString();
  var itemIndex = itemId == null
      ? -1
      : next.indexWhere(
          (item) => item['id'] == itemId || item['call_id'] == itemId,
        );
  if (itemIndex < 0) {
    final explicitIndex = (event['output_index'] as num?)?.toInt();
    if (explicitIndex != null && explicitIndex < 0) return output;
    itemIndex =
        explicitIndex ?? (itemId != null ? next.length : next.length - 1);
  }
  if (itemIndex < 0) itemIndex = 0;

  while (next.length <= itemIndex) {
    final isTarget = next.length == itemIndex;
    next.add({
      'id': isTarget && itemId != null ? itemId : newId(),
      'type': isTarget && eventType.startsWith('response.reasoning')
          ? 'reasoning'
          : 'message',
      'content': [],
    });
  }

  final item = next[itemIndex];
  final parts = eventType.split('.');
  final name = parts.length > 1 ? parts[1] : '';

  if (name == 'content_part' || name == 'reasoning_summary_part') {
    final raw = event['part'];
    if (raw is! Map) return output;
    final field = name == 'content_part' ? 'content' : 'summary';
    final rawIndex =
        event[name == 'content_part' ? 'content_index' : 'summary_index'];
    final position = (rawIndex as num?)?.toInt() ?? 0;
    if (position < 0) return output;
    final existing = item[field];
    final content = existing is List ? List<Object?>.of(existing) : <Object?>[];
    while (content.length <= position) {
      content.add({'type': 'output_text', 'text': ''});
    }
    content[position] = Map<String, dynamic>.from(raw);
    item[field] = content;
    return next;
  }

  if (eventType.endsWith('.done')) {
    if (name == 'function_call_arguments' && event['arguments'] != null) {
      item['arguments'] = event['arguments'];
    } else if (name == 'reasoning_summary_text' && event['text'] != null) {
      _setPart(item, 'summary', event['summary_index'], event['text']);
    } else if ((name == 'output_text' ||
            name == 'text' ||
            name == 'reasoning_text') &&
        event['text'] != null) {
      _setPart(item, 'content', event['content_index'], event['text']);
    }
    return next;
  }

  final delta = event['delta'];
  if (name == 'function_call_arguments') {
    item['arguments'] = '${item['arguments'] ?? ''}${delta ?? ''}';
  } else if (name == 'reasoning_summary_text') {
    _appendPart(item, 'summary', event['summary_index'], delta);
  } else if (item['type'] == 'open_webui:code_interpreter') {
    item['code'] = '${item['code'] ?? ''}${delta ?? ''}';
  } else if (name == 'output_text' || name == 'reasoning_text') {
    _appendPart(item, 'content', event['content_index'], delta);
  } else {
    _appendPart(item, 'content', event['content_index'], delta, key: name);
  }

  return next;
}

void _appendPart(
  Map<String, dynamic> item,
  String field,
  Object? index,
  Object? delta, {
  String key = 'text',
}) {
  final list = item[field];
  final parts = list is List
      ? [
          for (final part in list)
            part is Map
                ? Map<String, dynamic>.from(part)
                : <String, dynamic>{'type': 'output_text', 'text': ''},
        ]
      : <Map<String, dynamic>>[];
  final position = (index as num?)?.toInt() ?? 0;
  if (position < 0) return;
  while (parts.length <= position) {
    parts.add({'type': 'output_text', 'text': ''});
  }
  final part = parts[position];
  part[key] = '${part[key] ?? ''}${delta ?? ''}';
  item[field] = parts;
}

void _setPart(
  Map<String, dynamic> item,
  String field,
  Object? index,
  Object? value,
) {
  final list = item[field];
  final parts = list is List
      ? [
          for (final part in list)
            part is Map
                ? Map<String, dynamic>.from(part)
                : <String, dynamic>{'type': 'output_text', 'text': ''},
        ]
      : <Map<String, dynamic>>[];
  final position = (index as num?)?.toInt() ?? 0;
  if (position < 0) return;
  while (parts.length <= position) {
    parts.add({'type': 'output_text', 'text': ''});
  }
  parts[position] = {
    ...parts[position],
    'type': parts[position]['type'] ?? 'output_text',
    'text': value,
  };
  item[field] = parts;
}

String outputText(List<Map<String, dynamic>> output) {
  final buffer = StringBuffer();
  for (final item in output) {
    if (item['type'] == 'message' || item['type'] == 'output_text') {
      buffer.write(_textOf(item['content'] ?? item['text']));
    }
  }
  return buffer.toString();
}

String outputReasoning(List<Map<String, dynamic>> output) {
  final buffer = StringBuffer();
  for (final item in output) {
    if (item['type'] == 'reasoning') {
      final summary = _textOf(item['summary']);
      buffer.write(summary.isNotEmpty ? summary : _textOf(item['content']));
    }
  }
  return buffer.toString().trim();
}

String _textOf(Object? parts) {
  if (parts is String) return parts;
  if (parts is! List) return '';
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is Map && part['text'] is String) {
      buffer.write(part['text']);
    }
  }
  return buffer.toString();
}

String? errorFromPayload(Object? payload) {
  if (payload is! Map) return null;
  final error = payload['error'] ?? payload['detail'];
  if (error == null) return null;
  if (error is String) return error;
  if (error is Map) {
    final content = error['content'] ?? error['message'] ?? error['detail'];
    if (content is String) return content;
    return jsonEncode(error);
  }
  return error.toString();
}
