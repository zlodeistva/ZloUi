import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/l10n.dart';
import 'package:zloui/widgets/composer.dart';

Widget _app({
  required TextEditingController controller,
  bool listening = false,
  VoidCallback? onMic,
  VoidCallback? onSend,
  bool sending = false,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: Strings.supportedLocales,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Composer(
        controller: controller,
        sending: sending,
        enabled: true,
        uploading: false,
        hintText: 'Message…',
        onSend: onSend ?? () {},
        onStop: () {},
        onAttach: () {},
        listening: listening,
        onMic: onMic,
      ),
    ),
  );
}

void main() {
  group('Composer voice input', () {
    testWidgets('shows a mic button when voice input is available', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(controller: controller, onMic: () {}));

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byTooltip('Voice input'), findsOneWidget);
    });

    testWidgets('hides the mic button without a handler', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_app(controller: controller));

      expect(find.byIcon(Icons.mic_none), findsNothing);
      expect(find.byIcon(Icons.mic), findsNothing);
    });

    testWidgets('tapping the mic toggles dictation', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var taps = 0;

      await tester.pumpWidget(
        _app(controller: controller, onMic: () => taps++),
      );

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('shows the listening state and stops on tap', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var taps = 0;

      await tester.pumpWidget(
        _app(controller: controller, listening: true, onMic: () => taps++),
      );

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsNothing);
      expect(find.byTooltip('Stop listening'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('disables the mic while a reply is streaming', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var taps = 0;

      await tester.pumpWidget(
        _app(controller: controller, sending: true, onMic: () => taps++),
      );

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump();

      expect(taps, 0);
    });
  });
}
