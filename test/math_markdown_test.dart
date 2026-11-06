import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/widgets/math_markdown.dart';

Widget _app(String data) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MarkdownBody(
          data: prepareMathMarkdown(data),
          inlineSyntaxes: [MathInlineSyntax()],
          builders: {'math': MathMarkdownBuilder()},
        ),
      ),
    ),
  );
}

void main() {
  group('prepareMathMarkdown', () {
    test('converts \\( \\) to dollars', () {
      expect(prepareMathMarkdown(r'a \( x^2 \) b'), r'a $x^2$ b');
    });

    test('converts line-anchored \\[ \\] to display math', () {
      final out = prepareMathMarkdown('text\n\\[\\frac{1}{2}\\]\nmore');
      expect(out, contains(r'$$\frac{1}{2}$$'));
    });

    test('converts math fences to display math', () {
      final out = prepareMathMarkdown('```math\n\\frac{a}{b}\n```');
      expect(out, contains(r'$$\frac{a}{b}$$'));
      expect(out, isNot(contains('```')));
    });

    test('keeps regular code blocks and code spans untouched', () {
      const code = '```dart\nfinal a = r"\\(x\\)";\n```\nand `\\(y\\)`';
      expect(prepareMathMarkdown(code), code);
    });
  });

  group('rendering', () {
    testWidgets('renders inline fraction', (tester) async {
      await tester.pumpWidget(_app(r'Half is $\frac{1}{2}$ of one.'));
      expect(find.byType(Math), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders display math', (tester) async {
      await tester.pumpWidget(_app('Result:\n\n\$\$\\frac{a+b}{c}\$\$\n'));
      expect(find.byType(Math), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders bracket notation', (tester) async {
      await tester.pumpWidget(_app('\\(\\frac{1}{3}\\) and\n\\[x^2\\]'));
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('does not treat prices as math', (tester) async {
      await tester.pumpWidget(_app(r'It costs $5 and then $10 more.'));
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('falls back to source on invalid tex', (tester) async {
      await tester.pumpWidget(_app(r'Broken $\frac{1$ here.'));
      expect(tester.takeException(), isNull);
    });
  });
}
