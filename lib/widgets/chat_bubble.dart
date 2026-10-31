import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../models.dart';
import 'attachment_view.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.baseUrl,
    required this.token,
    required this.showProgress,
    this.streaming = false,
    this.onCopy,
    this.onRegenerate,
  });

  final ChatMessage message;
  final String baseUrl;
  final String token;
  final bool showProgress;

  /// The reply is still being written: show an indicator after the text.
  final bool streaming;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final isUser = message.role == 'user';
    final isNotice = message.isNotice;

    final color = isNotice
        ? theme.colorScheme.surfaceContainerHighest
        : isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isNotice
        ? theme.colorScheme.onSurfaceVariant
        : isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    final children = <Widget>[];
    final visibleToolCalls = message.toolCalls
        .where((call) => call.name != 'ask_user')
        .toList();

    if (isUser && message.attachments.isNotEmpty) {
      children.add(
        AttachmentStrip(
          attachments: message.attachments,
          baseUrl: baseUrl,
          token: token,
          compact: true,
        ),
      );
      if (message.content.isNotEmpty) children.add(const SizedBox(height: 8));
    }

    if (!isUser && message.attachments.isNotEmpty) {
      final images = message.attachments.where((file) => file.isImage);
      final files = message.attachments.where((file) => !file.isImage);
      for (final image in images) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AttachmentImage(
                attachment: image,
                baseUrl: baseUrl,
                token: token,
                fit: BoxFit.contain,
                viewable: true,
              ),
            ),
          ),
        );
      }
      if (files.isNotEmpty) {
        children.add(
          AttachmentStrip(
            attachments: files.toList(),
            baseUrl: baseUrl,
            token: token,
            compact: true,
          ),
        );
      }
    }

    if (message.reasoning.isNotEmpty) {
      children.add(
        ReasoningBlock(
          text: message.reasoning,
          running: !message.done && message.content.isEmpty,
        ),
      );
      if (message.content.isNotEmpty || visibleToolCalls.isNotEmpty) {
        children.add(const SizedBox(height: 8));
      }
    }

    for (final call in visibleToolCalls) {
      children.add(ToolCallBlock(call: call, messageDone: message.done));
      children.add(const SizedBox(height: 6));
    }

    if (message.statusText != null &&
        message.statusText!.isNotEmpty &&
        !message.done) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.statusDone)
                Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: textColor.withValues(alpha: 0.75),
                )
              else
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.statusText!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (showProgress) {
      children.add(
        const SizedBox(
          width: 40,
          height: 20,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    } else if (message.content.isNotEmpty) {
      if (isUser) {
        children.add(
          SelectableText(
            message.content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: textColor,
              height: 1.35,
            ),
          ),
        );
      } else {
        children.add(
          MarkdownBody(
            data: _linkCitations(message.content, message.sources),
            selectable: true,
            onTapLink: (text, href, title) {
              if (href != null) _openLink(href);
            },
            styleSheet: _markdownStyle(theme, textColor),
            sizedImageBuilder: (config) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AttachmentImage(
                attachment: ChatAttachment(
                  id: '',
                  name: config.alt ?? 'image',
                  type: 'image',
                  url: config.uri.toString(),
                ),
                baseUrl: baseUrl,
                token: token,
                fit: BoxFit.contain,
                viewable: true,
              ),
            ),
          ),
        );
      }
    }

    if (!isUser && streaming && !showProgress) {
      children.add(const SizedBox(height: 6));
      children.add(
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: textColor.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    if (!isUser && message.sources.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(SourcesBlock(sources: message.sources));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    final bubble = Material(
      color: color,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRegenerate == null
            ? null
            : () => _showMessageMenu(context, s, onRegenerate!),
        borderRadius: radius,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: bubble,
        ),
        if (!isUser &&
            !isNotice &&
            (message.content.isNotEmpty || visibleToolCalls.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onCopy != null)
                  _MiniButton(
                    tooltip: s.t('copy'),
                    icon: Icons.copy_rounded,
                    onPressed: onCopy!,
                  ),
                if (onRegenerate != null)
                  _MiniButton(
                    tooltip: s.t('regenerate'),
                    icon: Icons.refresh_rounded,
                    onPressed: onRegenerate!,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Turns source references like [1] into tappable links.
  static String _linkCitations(String text, List<SourceLink> sources) {
    if (sources.isEmpty) return text;
    final parts = text.split('```');
    for (var i = 0; i < parts.length; i += 2) {
      parts[i] = parts[i].replaceAllMapped(RegExp(r'\[(\d{1,3})\](?![(\[:])'), (
        match,
      ) {
        final index = int.parse(match.group(1)!);
        if (index < 1 || index > sources.length) return match.group(0)!;
        final url = sources[index - 1].url.replaceAll(')', '%29');
        return '[[$index]]($url)';
      });
    }
    return parts.join('```');
  }

  MarkdownStyleSheet _markdownStyle(ThemeData theme, Color textColor) {
    final mono = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: textColor,
    );
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.35),
      a: TextStyle(
        color: theme.colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      code: mono,
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: textColor.withValues(alpha: 0.8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 3),
        ),
      ),
      h1: theme.textTheme.titleLarge?.copyWith(color: textColor),
      h2: theme.textTheme.titleMedium?.copyWith(color: textColor),
      h3: theme.textTheme.titleSmall?.copyWith(color: textColor),
      listBullet: theme.textTheme.bodyMedium?.copyWith(color: textColor),
    );
  }
}

void _showMessageMenu(
  BuildContext context,
  Strings s,
  VoidCallback onRegenerate,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ListTile(
          leading: const Icon(Icons.refresh_rounded),
          title: Text(s.t('regenerate')),
          onTap: () {
            Navigator.pop(sheetContext);
            onRegenerate();
          },
        ),
      );
    },
  );
}

Future<void> _openLink(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(icon),
    );
  }
}

class SourcesBlock extends StatelessWidget {
  const SourcesBlock({super.key, required this.sources});

  final List<SourceLink> sources;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.t('sources'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < sources.length; i++)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: CircleAvatar(
                  radius: 9,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    sources[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onPressed: () => _openLink(sources[i].url),
              ),
          ],
        ),
      ],
    );
  }
}

class ReasoningBlock extends StatefulWidget {
  const ReasoningBlock({super.key, required this.text, this.running = false});

  final String text;
  final bool running;

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final preview = widget.text.trim().split('\n').first;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (widget.running)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _expanded
                          ? s.t('hideReasoning')
                          : '${s.t('reasoning')} · $preview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SelectableText(
                widget.text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ToolCallBlock extends StatefulWidget {
  const ToolCallBlock({
    super.key,
    required this.call,
    this.messageDone = false,
  });

  final ToolCall call;

  /// The reply is finished: a call without a result is no longer running.
  final bool messageDone;

  @override
  State<ToolCallBlock> createState() => _ToolCallBlockState();
}

class _ToolCallBlockState extends State<ToolCallBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = Strings.of(context);
    final call = widget.call;
    final running = !call.isDone && !widget.messageDone;
    final failed = call.status == 'failed' || call.status == 'incomplete';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: failed
              ? theme.colorScheme.error.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  else
                    Icon(
                      failed ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16,
                      color: failed
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      call.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  Text(
                    running ? s.t('toolCall') : s.t('toolResult'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            if (call.arguments.isNotEmpty)
              _ToolSection(
                title: 'arguments',
                text: prettyJson(call.arguments),
              ),
            if (call.result != null && call.result!.isNotEmpty)
              _ToolSection(title: 'output', text: prettyJson(call.result!)),
          ],
        ],
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
