import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/chat_codec.dart';

void main() {
  test('uses history map keys when entries omit their ids', () {
    final chat = ChatCodec.decode({
      'chat': {
        'history': {
          'currentId': 'reply',
          'messages': {
            'user': {'role': 'user', 'content': 'Question'},
            'reply': {
              'id': '',
              'role': 'assistant',
              'parentId': 'user',
              'content': 'Answer',
            },
          },
        },
      },
    });
    expect(chat.messages.map((message) => message.id), ['user', 'reply']);
    expect(chat.messages.last.parentId, chat.messages.first.id);
  });

  test('restores images stored in multimodal content without duplicates', () {
    final chat = ChatCodec.decode({
      'chat': {
        'messages': [
          {
            'id': 'user',
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Describe this'},
              {
                'type': 'image_url',
                'image_url': {'url': '/image.png'},
              },
              {'type': 'image_url', 'image_url': '/image.png'},
              {'type': 'image_url', 'image_url': null},
            ],
          },
        ],
      },
    });
    expect(chat.messages.single.content, 'Describe this');
    expect(chat.messages.single.attachments.single.url, '/image.png');
  });

  test('does not drop image-only multimodal messages', () {
    final chat = ChatCodec.decode({
      'chat': {
        'messages': [
          {
            'id': 'user',
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': '/image.png'},
              },
            ],
          },
        ],
      },
    });
    expect(chat.messages, hasLength(1));
    expect(chat.messages.single.hasContent, isTrue);
  });

  for (final resultFirst in [false, true]) {
    test('matches tool results by call id (result first: $resultFirst)', () {
      final call = <String, dynamic>{
        'type': 'function_call',
        'id': 'output-item',
        'call_id': 'call',
        'name': 'search',
        'arguments': '{}',
        'status': 'in_progress',
      };
      final result = <String, dynamic>{
        'type': 'function_call_output',
        'call_id': 'call',
        'output': 'Found documents',
      };
      final parsed = ChatCodec.parseOutput(
        resultFirst ? [result, call] : [call, result],
        '',
      );
      expect(parsed.toolCalls.single.id, 'call');
      expect(parsed.toolCalls.single.result, 'Found documents');
      expect(parsed.toolCalls.single.status, 'completed');
      expect(parsed.toolCalls.single.isDone, isTrue);
      expect(call['status'], 'in_progress');
    });
  }

  test('ignores unmatched tool results', () {
    final parsed = ChatCodec.parseOutput([
      {
        'type': 'function_call_output',
        'call_id': 'missing',
        'output': 'Result',
      },
      {'type': 'function_call', 'call_id': 'pending', 'name': 'search'},
    ], 'Fallback');
    expect(parsed.text, 'Fallback');
    expect(parsed.toolCalls.single.result, isNull);
    expect(parsed.toolCalls.single.isDone, isFalse);
  });

  for (final content in [
    '  Preserve spacing\n',
    '<details><summary>Example</summary>HTML code</details>',
    '<think>Literal user text</think>',
  ]) {
    test('preserves literal user content: $content', () {
      final chat = ChatCodec.decode({
        'chat': {
          'messages': [
            {'id': 'user', 'role': 'user', 'content': content},
          ],
        },
      });
      expect(chat.messages.single.content, content);
      expect(chat.messages.single.reasoning, isEmpty);
    });
  }

  test('still extracts reasoning from assistant messages', () {
    final chat = ChatCodec.decode({
      'chat': {
        'messages': [
          {
            'id': 'reply',
            'role': 'assistant',
            'content': '<think>Reasoning</think>Answer',
          },
        ],
      },
    });
    expect(chat.messages.single.content, 'Answer');
    expect(chat.messages.single.reasoning, 'Reasoning');
  });

  final flatMessages = [
    {'id': 'user', 'role': 'user', 'content': 'Question'},
    {'id': 'reply', 'role': 'assistant', 'content': 'Answer'},
  ];

  for (final history in [
    {'messages': <String, dynamic>{}, 'currentId': null},
    {'messages': <String, dynamic>{}, 'currentId': 'missing'},
    {
      'messages': {'user': flatMessages.first},
      'currentId': null,
    },
  ]) {
    test('falls back to flat messages for unusable history: $history', () {
      final chat = ChatCodec.decode({
        'id': 'chat',
        'chat': {'history': history, 'messages': flatMessages},
      });
      expect(chat.messages.map((message) => message.content), [
        'Question',
        'Answer',
      ]);
    });
  }

  test('preserves the selected history branch over the flat list', () {
    final chat = ChatCodec.decode({
      'id': 'chat',
      'chat': {
        'history': {
          'messages': {
            'user': flatMessages.first,
            'selected': {
              'id': 'selected',
              'parentId': 'user',
              'role': 'assistant',
              'content': 'Selected branch',
            },
          },
          'currentId': 'selected',
        },
        'messages': flatMessages,
      },
    });
    expect(chat.messages.map((message) => message.content), [
      'Question',
      'Selected branch',
    ]);
  });
}
