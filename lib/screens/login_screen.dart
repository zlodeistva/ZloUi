import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.store, required this.onLoggedIn});

  final AppStore store;
  final ValueChanged<Session> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverController;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: widget.store.baseUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final baseUrl = OpenWebUiApi.normalizeBaseUrl(_serverController.text);
      final session = await OpenWebUiApi(baseUrl: baseUrl, token: '').signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await widget.store.saveSession(session);
      if (!mounted) return;
      widget.onLoggedIn(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final s = Strings.of(context);
        _error = error is ApiException
            ? error.message
            : '${s.t('error')}: $error';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.forum_rounded,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.t('appTitle'),
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.t('loginSubtitle'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _serverController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: s.t('server'),
                        hintText: s.t('serverHint'),
                        prefixIcon: const Icon(Icons.dns_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return s.t('serverRequired');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: s.t('email'),
                        prefixIcon: const Icon(Icons.mail_outline),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return s.t('emailRequired');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: s.t('password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? s.t('showPassword')
                              : s.t('hidePassword'),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return s.t('passwordRequired');
                        }
                        return null;
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 20,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(_loading ? s.t('signingIn') : s.t('signIn')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
