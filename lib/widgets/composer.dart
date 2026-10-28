import 'package:flutter/material.dart';

import '../l10n.dart';

class Composer extends StatelessWidget {
  const Composer({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.transparent = false,
    required this.sending,
    required this.enabled,
    required this.uploading,
    required this.hintText,
    required this.onSend,
    required this.onStop,
    required this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// No own background or divider; used inside the assistant card.
  final bool transparent;
  final bool sending;
  final bool enabled;
  final bool uploading;
  final String hintText;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);

    return Container(
      decoration: transparent
          ? null
          : BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
      padding: transparent
          ? const EdgeInsets.fromLTRB(4, 0, 6, 6)
          : const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: s.t('attach'),
            onPressed: enabled && !sending && !uploading ? onAttach : null,
            icon: uploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_circle_outline),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: hintText,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: transparent ? 9 : 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filled(
              tooltip: sending ? s.t('stop') : s.t('send'),
              onPressed: sending ? onStop : (enabled ? onSend : null),
              icon: Icon(sending ? Icons.stop : Icons.arrow_upward),
            ),
          ),
        ],
      ),
    );
  }
}
