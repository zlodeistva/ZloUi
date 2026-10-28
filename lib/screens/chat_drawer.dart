import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';

class ChatDrawer extends StatefulWidget {
  const ChatDrawer({
    super.key,
    required this.currentChatId,
    required this.loadChats,
    required this.loadArchived,
    required this.loadPinned,
    required this.searchChats,
    required this.onOpenChat,
    required this.onNewChat,
    required this.onDelete,
    required this.onRename,
    required this.onPin,
    required this.onArchive,
    required this.onClone,
  });

  final String? currentChatId;
  final Future<List<ChatSummary>> Function(int page) loadChats;
  final Future<List<ChatSummary>> Function(int page) loadArchived;
  final Future<List<ChatSummary>> Function() loadPinned;
  final Future<List<ChatSummary>> Function(String query) searchChats;
  final Future<void> Function(String id) onOpenChat;
  final VoidCallback onNewChat;
  final Future<void> Function(ChatSummary chat) onDelete;
  final Future<void> Function(ChatSummary chat) onRename;
  final Future<void> Function(ChatSummary chat) onPin;
  final Future<void> Function(ChatSummary chat) onArchive;
  final Future<void> Function(ChatSummary chat) onClone;

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<ChatDrawer> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<ChatSummary> _chats = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _done = false;
  int _page = 1;
  bool _showArchived = false;
  String? _error;
  String _query = '';

  /// Incremented on every reload so stale responses are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<List<ChatSummary>> _fetch(int page) =>
      _showArchived ? widget.loadArchived(page) : widget.loadChats(page);

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var list = _query.isEmpty
          ? await _fetch(1)
          : await widget.searchChats(_query);
      // Pinned chats go first: the regular list does not mark them.
      if (_query.isEmpty && !_showArchived) {
        try {
          final pinned = await widget.loadPinned();
          final ids = pinned.map((chat) => chat.id).toSet();
          list = [...pinned, ...list.where((chat) => !ids.contains(chat.id))];
        } catch (_) {}
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _chats
          ..clear()
          ..addAll(list);
        _page = 1;
        _done = _query.isNotEmpty || list.isEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _done || _query.isNotEmpty) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final list = await _fetch(_page + 1);
      if (!mounted || generation != _generation) return;
      final known = _chats.map((chat) => chat.id).toSet();
      final fresh = list.where((chat) => !known.contains(chat.id)).toList();
      setState(() {
        if (fresh.isEmpty) {
          _done = true;
        } else {
          _chats.addAll(fresh);
          _page += 1;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _afterAction(Future<void> Function() action) async {
    await action();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _showArchived ? s.t('archived') : s.t('chats'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: _showArchived
                        ? s.t('hideArchived')
                        : s.t('showArchived'),
                    onPressed: () {
                      setState(() {
                        _showArchived = !_showArchived;
                        _query = '';
                        _searchController.clear();
                      });
                      _reload();
                    },
                    icon: Icon(
                      _showArchived
                          ? Icons.inventory_2
                          : Icons.inventory_2_outlined,
                    ),
                  ),
                  IconButton(
                    tooltip: s.t('refresh'),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onNewChat();
                },
                icon: const Icon(Icons.add),
                label: Text(s.t('newChat')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: s.t('searchChats'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  _query = value.trim();
                  _reload();
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildList(s, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(Strings s, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 12),
          Center(
            child: OutlinedButton(
              onPressed: _reload,
              child: Text(s.t('retry')),
            ),
          ),
        ],
      );
    }
    if (_chats.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _showArchived ? s.t('noArchivedChats') : s.t('noChats'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _chats.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _chats.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final chat = _chats[index];
          return _ChatTile(
            chat: chat,
            selected: chat.id == widget.currentChatId,
            archivedView: _showArchived,
            onTap: () {
              Navigator.pop(context);
              widget.onOpenChat(chat.id);
            },
            onDelete: () => _afterAction(() => widget.onDelete(chat)),
            onRename: () => _afterAction(() => widget.onRename(chat)),
            onPin: () => _afterAction(() => widget.onPin(chat)),
            onArchive: () => _afterAction(() => widget.onArchive(chat)),
            onClone: () => _afterAction(() => widget.onClone(chat)),
          );
        },
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.selected,
    required this.archivedView,
    required this.onTap,
    required this.onDelete,
    required this.onRename,
    required this.onPin,
    required this.onArchive,
    required this.onClone,
  });

  final ChatSummary chat;
  final bool selected;
  final bool archivedView;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onPin;
  final VoidCallback onArchive;
  final VoidCallback onClone;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);

    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.35,
      ),
      leading: Icon(
        chat.pinned ? Icons.push_pin : Icons.chat_bubble_outline,
        size: 20,
      ),
      title: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: chat.updatedAt > 0 ? Text(_formatDate(chat.updatedAt)) : null,
      onTap: onTap,
      trailing: PopupMenuButton<String>(
        tooltip: '',
        onSelected: (value) {
          switch (value) {
            case 'rename':
              onRename();
            case 'pin':
              onPin();
            case 'archive':
              onArchive();
            case 'clone':
              onClone();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'rename',
            child: _menuItem(Icons.edit_outlined, s.t('rename')),
          ),
          PopupMenuItem(
            value: 'pin',
            child: _menuItem(
              chat.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              chat.pinned ? s.t('unpin') : s.t('pin'),
            ),
          ),
          PopupMenuItem(
            value: 'archive',
            child: _menuItem(
              archivedView ? Icons.unarchive_outlined : Icons.archive_outlined,
              archivedView ? s.t('unarchive') : s.t('archive'),
            ),
          ),
          PopupMenuItem(
            value: 'clone',
            child: _menuItem(Icons.copy_all_outlined, s.t('clone')),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: _menuItem(Icons.delete_outline, s.t('delete'), error: true),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, {bool error = false}) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }

  String _formatDate(int seconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final today =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (today) return '${two(date.hour)}:${two(date.minute)}';
    return '${two(date.day)}.${two(date.month)}.${date.year}';
  }
}
