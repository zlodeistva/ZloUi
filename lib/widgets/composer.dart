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
    this.listening = false,
    this.onMic,
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

  /// A listen session is running; the mic button stops it.
  final bool listening;

  /// Toggles voice input; null hides the mic button.
  final VoidCallback? onMic;

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
                suffixIcon: onMic == null
                    ? null
                    : _MicButton(
                        listening: listening,
                        tooltip: s.t(listening ? 'voiceStop' : 'voiceInput'),
                        onPressed: sending || !enabled ? null : onMic,
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

/// Mic button inside the text field: idle icon, pulsing accent while listening.
class _MicButton extends StatefulWidget {
  const _MicButton({
    required this.listening,
    required this.tooltip,
    required this.onPressed,
  });

  final bool listening;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.listening) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.listening == oldWidget.listening) return;
    if (widget.listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = widget.listening;
    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      icon: FadeTransition(
        opacity: listening
            ? Tween<double>(begin: 0.45, end: 1).animate(_pulse)
            : const AlwaysStoppedAnimation(1),
        child: Icon(
          listening ? Icons.mic : Icons.mic_none,
          color: listening ? scheme.primary : null,
        ),
      ),
    );
  }
}
