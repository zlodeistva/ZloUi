import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/chat_codec.dart';
import 'package:zloui/models.dart';
import 'package:zloui/stream_events.dart';

void main() {
  test('late item creation preserves text received in early deltas', () {
    var output = applyResponseEvent([], {
      'type': 'response.output_text.delta',
      'item_id': 'reply',
      'delta': 'Early text',
    });
    output = applyResponseEvent(output, {
      'type': 'response.output_item.added',
      'item': {'id': 'reply', 'type': 'message', 'content': []},
    });
    expect(output, hasLength(1));
    expect(outputText(output), 'Early text');
    output = applyResponseEvent(output, {
      'type': 'response.output_text.delta',
      'item_id': 'reply',
      'delta': ' continues',
    });
    expect(outputText(output), 'Early text continues');
  });

  test('late tool creation preserves arguments and supplies call metadata', () {
    var output = applyResponseEvent([], {
      'type': 'response.function_call_arguments.delta',
      'item_id': 'tool-item',
      'delta': '{"query":',
    });
    output = applyResponseEvent(output, {
      'type': 'response.output_item.added',
      'item': {
        'id': 'tool-item',
        'type': 'function_call',
        'call_id': 'tool-call',
        'name': 'lookup',
        'arguments': '',
      },
    });
    final call = ChatCodec.parseOutput(output, '').toolCalls.single;
    expect(call.id, 'tool-call');
    expect(call.name, 'lookup');
    expect(call.arguments, '{"query":');
  });

  for (final phase in ['output_item.done', 'completed']) {
    test('keeps tool calls separate from their results in $phase', () {
      final call = <String, dynamic>{
        'id': 'call-item',
        'call_id': 'shared-call',
        'type': 'function_call',
        'name': 'lookup',
        'arguments': '{"query":"test"}',
      };
      final result = <String, dynamic>{
        'call_id': 'shared-call',
        'type': 'function_call_output',
        'output': 'Found',
      };
      var output = applyResponseEvent([], {
        'type': 'response.output_item.added',
        'item': call,
      });
      output = applyResponseEvent(output, {
        'type': 'response.$phase',
        if (phase == 'completed')
          'response': {
            'output': [call, result],
          }
        else
          'item': result,
      });
      expect(output, hasLength(2));
      final calls = ChatCodec.parseOutput(output, '').toolCalls;
      expect(calls, hasLength(1));
      expect(calls.single.name, 'lookup');
      expect(calls.single.arguments, '{"query":"test"}');
      expect(calls.single.result, 'Found');
      expect(calls.single.status, 'completed');

      // Repeated final snapshots must not duplicate either item.
      output = applyResponseEvent(output, {
        'type': 'response.completed',
        'response': {
          'output': [call, result],
        },
      });
      expect(output, hasLength(2));
    });
  }

  test('keeps early deltas separate by item id without output indices', () {
    var output = <Map<String, dynamic>>[];
    for (final entry in [
      ('first', 'Hello'),
      ('second', 'World'),
      ('first', '!'),
    ]) {
      output = applyResponseEvent(output, {
        'type': 'response.output_text.delta',
        'item_id': entry.$1,
        'delta': entry.$2,
      });
    }
    expect(output.map((item) => item['id']), ['first', 'second']);
    expect(outputText(output), 'Hello!World');
    output = applyResponseEvent(output, {
      'type': 'response.output_item.done',
      'item': {'id': 'first', 'type': 'message', 'content': 'Hello!'},
    });
    expect(output, hasLength(2));
    expect(outputText(output), 'Hello!World');
  });

  test('early reasoning deltas are not exposed as reply text', () {
    final output = applyResponseEvent([], {
      'type': 'response.reasoning_summary_text.delta',
      'item_id': 'reasoning',
      'delta': 'Thinking',
    });
    expect(outputReasoning(output), 'Thinking');
    expect(outputText(output), isEmpty);
  });

  test('ignores a negative output item index', () {
    final original = <Map<String, dynamic>>[
      {'id': 'existing', 'type': 'message', 'content': 'Reply'},
    ];
    final output = applyResponseEvent(original, {
      'type': 'response.output_item.added',
      'output_index': -1,
      'item': {'id': 'invalid', 'type': 'message', 'content': 'Invalid'},
    });
    expect(outputText(output), 'Reply');
    expect(output, hasLength(1));
  });

  for (final phase in ['delta', 'done']) {
    test('ignores a negative content index in $phase events', () {
      final original = <Map<String, dynamic>>[
        {
          'id': 'item',
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': 'Reply'},
          ],
        },
      ];
      final output = applyResponseEvent(original, {
        'type': 'response.output_text.$phase',
        'item_id': 'item',
        'content_index': -1,
        'delta': 'Invalid',
        'text': 'Invalid',
      });
      expect(outputText(output), 'Reply');
      expect(outputText(original), 'Reply');
    });
  }

  for (final field in ['content', 'summary']) {
    for (final phase in ['added', 'done']) {
      test('applies complete $field parts from $phase events', () {
        final original = <Map<String, dynamic>>[
          {
            'id': 'item',
            'type': field == 'content' ? 'message' : 'reasoning',
            field: <Map<String, dynamic>>[],
          },
        ];
        final output = applyResponseEvent(original, {
          'type': field == 'content'
              ? 'response.content_part.$phase'
              : 'response.reasoning_summary_part.$phase',
          'item_id': 'item',
          'content_index': 0,
          'summary_index': 0,
          'part': {'type': 'text', 'text': 'Complete block'},
        });
        expect(
          field == 'content' ? outputText(output) : outputReasoning(output),
          'Complete block',
        );
        expect(original.first[field], isEmpty);
      });
    }
  }

  group('chat event routing', () {
    bool matches(String chatId, String messageId, {String? currentChat}) =>
        isCurrentChatEvent(
          ChatEvent(chatId: chatId, messageId: messageId, type: 'message'),
          chatId: currentChat,
          streamingMessageId: 'current-reply',
          messageIds: ['user', 'current-reply'],
        );

    test('accepts the streaming reply before the server returns a chat id', () {
      expect(matches('new-server-chat', 'current-reply'), isTrue);
    });
    test('rejects events from an unrelated saved chat', () {
      expect(
        matches('other-chat', 'other-reply', currentChat: 'active'),
        isFalse,
      );
    });
    test('rejects late events from an old temporary chat', () {
      expect(matches('temporary:session', 'old-reply'), isFalse);
    });
    test('accepts known messages in a temporary chat', () {
      expect(matches('temporary:session', 'user'), isTrue);
    });
    test('accepts chat-level events for the active saved chat', () {
      expect(matches('active', '', currentChat: 'active'), isTrue);
    });
  });

  test('appends output items without an explicit index in arrival order', () {
    var output = <Map<String, dynamic>>[];
    for (final id in ['first', 'second', 'third']) {
      output = applyResponseEvent(output, {
        'type': 'response.output_item.added',
        'item': {'id': id, 'type': 'message', 'content': id},
      });
    }
    expect(output.map((item) => item['id']), ['first', 'second', 'third']);
    expect(outputText(output), 'firstsecondthird');
  });

  test('uses explicit output indices when provided', () {
    final output = applyResponseEvent(
      [
        {'id': 'last', 'type': 'message', 'content': 'last'},
      ],
      {
        'type': 'response.output_item.added',
        'output_index': 0,
        'item': {'id': 'first', 'type': 'message', 'content': 'first'},
      },
    );
    expect(outputText(output), 'firstlast');
  });

  test('reads text from standalone output_text items', () {
    expect(
      outputText([
        {'type': 'output_text', 'text': 'Reply'},
      ]),
      'Reply',
    );
  });

  test('ignores malformed output parts instead of throwing', () {
    final output = applyResponseEvent(
      [
        {
          'id': 'item',
          'type': 'message',
          'content': ['malformed'],
        },
      ],
      {
        'type': 'response.output_text.delta',
        'item_id': 'item',
        'content_index': 0,
        'delta': 'Reply',
      },
    );
    expect(outputText(output), 'Reply');
  });

  test(
    'final reasoning summary replaces partial text without mutating input',
    () {
      final original = <Map<String, dynamic>>[
        {
          'id': 'reasoning',
          'type': 'reasoning',
          'summary': [
            {'type': 'summary_text', 'text': 'Partial'},
          ],
        },
      ];
      final output = applyResponseEvent(original, {
        'type': 'response.reasoning_summary_text.done',
        'item_id': 'reasoning',
        'summary_index': 0,
        'text': 'Complete summary',
      });
      expect(outputReasoning(output), 'Complete summary');
      expect(outputReasoning(original), 'Partial');
    },
  );
}
