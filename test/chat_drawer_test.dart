import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zloui/models.dart';
import 'package:zloui/screens/chat_drawer.dart';

List<ChatSummary> _chats(int start, int count) => [
  for (var i = start; i < start + count; i++)
    ChatSummary(id: '$i', title: 'Chat $i', updatedAt: 0),
];

Widget _app({
  required Future<List<ChatSummary>> Function(int) loadChats,
  Future<List<ChatSummary>> Function()? loadPinned,
}) => MaterialApp(
  home: Scaffold(
    body: ChatDrawer(
      currentChatId: null,
      loadChats: loadChats,
      loadArchived: (_) async => [],
      loadPinned: loadPinned ?? () async => [],
      searchChats: (_) async => [],
      onOpenChat: (_) async {},
      onNewChat: () {},
      onDelete: (_) async {},
      onRename: (_) async {},
      onPin: (_) async {},
      onArchive: (_) async {},
      onClone: (_) async {},
    ),
  ),
);

Future<void> _scrollToEnd(WidgetTester tester) async {
  final list = tester.widget<ListView>(find.byType(ListView).last);
  list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads more when the first page does not fill the viewport', (
    tester,
  ) async {
    final pages = <int>[];
    await tester.pumpWidget(
      _app(
        loadChats: (page) async {
          pages.add(page);
          return switch (page) {
            1 => _chats(0, 1),
            2 => _chats(1, 1),
            _ => [],
          };
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(pages, [1, 2, 3]);
    expect(find.text('Chat 0'), findsOneWidget);
    expect(find.text('Chat 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries the same page after a transient pagination failure', (
    tester,
  ) async {
    final pages = <int>[];
    var failed = false;
    await tester.pumpWidget(
      _app(
        loadChats: (page) async {
          pages.add(page);
          if (page == 1) return _chats(0, 20);
          if (!failed) {
            failed = true;
            throw Exception('Connection interrupted');
          }
          return _chats(20, 20);
        },
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToEnd(tester);
    expect(pages, [1, 2]);

    final list = tester.widget<ListView>(find.byType(ListView).last);
    list.controller!.jumpTo(0);
    await tester.pump();
    await _scrollToEnd(tester);
    expect(pages, [1, 2, 2]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continues past a page containing only pinned duplicates', (
    tester,
  ) async {
    final pages = <int>[];
    await tester.pumpWidget(
      _app(
        loadChats: (page) async {
          pages.add(page);
          return switch (page) {
            1 => _chats(0, 20),
            2 => _chats(20, 20),
            3 => _chats(40, 20),
            _ => [],
          };
        },
        loadPinned: () async => _chats(20, 20),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollToEnd(tester);
    expect(pages, contains(2));

    // Trigger another scroll after the duplicate-only page.
    final list = tester.widget<ListView>(find.byType(ListView).last);
    list.controller!.jumpTo(0);
    await tester.pump();
    await _scrollToEnd(tester);
    expect(pages, contains(3));
  });

  testWidgets('ignores a stale pagination failure after refresh', (
    tester,
  ) async {
    final stale = Completer<List<ChatSummary>>();
    var pageTwoCalls = 0;
    await tester.pumpWidget(
      _app(
        loadChats: (page) {
          if (page == 1) return Future.value(_chats(0, 20));
          pageTwoCalls++;
          return pageTwoCalls == 1
              ? stale.future
              : Future.value(_chats(20, 20));
        },
      ),
    );
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).last);
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    expect(pageTwoCalls, 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    stale.completeError(Exception('Old request failed'));
    await tester.pumpAndSettle();

    final refreshedList = tester.widget<ListView>(find.byType(ListView).last);
    refreshedList.controller!.jumpTo(0);
    await tester.pump();
    await _scrollToEnd(tester);
    expect(pageTwoCalls, 2);
    expect(tester.takeException(), isNull);
  });
}
