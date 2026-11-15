import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/models.dart';

void main() {
  test('an empty assistant placeholder has no content', () {
    expect(ChatMessage(role: 'assistant').hasContent, isFalse);
  });

  test('an image-only reply has content', () {
    final message = ChatMessage(
      role: 'assistant',
      attachments: const [
        ChatAttachment(id: 'image', name: 'image.png', type: 'image'),
      ],
    );
    expect(message.hasContent, isTrue);
  });

  test('reasoning and tool calls count as content without reply text', () {
    expect(
      ChatMessage(role: 'assistant', reasoning: 'Thinking').hasContent,
      isTrue,
    );
    expect(
      ChatMessage(
        role: 'assistant',
        toolCalls: [ToolCall(id: 'call', name: 'search')],
      ).hasContent,
      isTrue,
    );
  });
}
