import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../widgets/attachment_view.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final Session session;
  final VoidCallback onLogout;

  Future<void> _confirmLogout(BuildContext context) async {
    final s = Strings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('logoutTitle')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('logout')),
          ),
        ],
      ),
    );
    if (confirmed == true) onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final name = session.name.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Scaffold(
      appBar: AppBar(title: Text(s.t('account'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Center(
            child: _Avatar(
              name: initial,
              avatarUrl: session.avatarUrl,
              baseUrl: session.baseUrl,
              token: session.token,
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text(name, style: theme.textTheme.titleLarge)),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(s.t('email')),
                  subtitle: Text(session.email),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(s.t('serverLabel')),
                  subtitle: Text(session.baseUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.logout),
            label: Text(s.t('logout')),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.name,
    required this.avatarUrl,
    required this.baseUrl,
    required this.token,
  });

  final String name;
  final String avatarUrl;
  final String baseUrl;
  final String token;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = CircleAvatar(
      radius: 40,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        name,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
    if (avatarUrl.isEmpty) return initial;

    return ClipOval(
      child: SizedBox(
        width: 80,
        height: 80,
        child: AttachmentImage(
          attachment: ChatAttachment(
            id: '',
            name: 'avatar',
            type: 'image',
            url: avatarUrl,
          ),
          baseUrl: baseUrl,
          token: token,
          fallback: initial,
          width: 80,
          height: 80,
        ),
      ),
    );
  }
}
