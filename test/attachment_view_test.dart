import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/models.dart';
import 'package:zloui/widgets/attachment_view.dart';

void main() {
  for (final base64 in [true, false]) {
    testWidgets('loads an inline image (base64: $base64)', (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      );
      final url = UriData.fromBytes(
        bytes,
        mimeType: 'image/png',
        percentEncoded: !base64,
      ).toString();
      await tester.pumpWidget(
        MaterialApp(
          home: AttachmentImage(
            attachment: ChatAttachment(
              id: '',
              name: 'inline.png',
              type: 'image',
              url: url,
            ),
            baseUrl: 'https://example.com',
            token: '',
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as MemoryImage).bytes, orderedEquals(bytes));
    });
  }

  testWidgets('rejects malformed inline data without a network request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AttachmentImage(
          attachment: ChatAttachment(
            id: 'file',
            name: 'invalid.png',
            type: 'image',
            url: 'data:image/png;base64,%%%invalid',
          ),
          baseUrl: 'https://example.com',
          token: '',
        ),
      ),
    );
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'reloads local bytes even when attachment id and URL are unchanged',
    (tester) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      );

      Widget app(List<int>? localBytes) => MaterialApp(
        home: AttachmentImage(
          attachment: ChatAttachment(
            id: '',
            name: 'image',
            type: 'image',
            localBytes: localBytes,
          ),
          baseUrl: 'https://example.com',
          token: '',
        ),
      );

      await tester.pumpWidget(app(null));
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);

      await tester.pumpWidget(app(bytes));
      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as MemoryImage).bytes, orderedEquals(bytes));
    },
  );
}
