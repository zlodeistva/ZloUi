import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';

import '../api.dart';
import '../models.dart';

class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({
    super.key,
    required this.attachments,
    required this.baseUrl,
    required this.token,
    this.onRemove,
    this.compact = false,
  });

  final List<ChatAttachment> attachments;
  final String baseUrl;
  final String token;
  final ValueChanged<ChatAttachment>? onRemove;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in attachments)
            AttachmentTile(
              attachment: attachment,
              baseUrl: baseUrl,
              token: token,
              onRemove: onRemove == null ? null : () => onRemove!(attachment),
            ),
        ],
      ),
    );
  }
}

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.baseUrl,
    required this.token,
    this.onRemove,
  });

  final ChatAttachment attachment;
  final String baseUrl;
  final String token;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = attachment.isImage;

    final preview = isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AttachmentImage(
              attachment: attachment,
              baseUrl: baseUrl,
              token: token,
              width: 72,
              height: 72,
            ),
          )
        : _fileIcon(theme);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              preview,
              if (!isImage)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          attachment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                        if (attachment.size > 0)
                          Text(
                            formatBytes(attachment.size),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fileIcon(ThemeData theme) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(Icons.description_outlined, color: theme.colorScheme.primary),
  );
}

/// Attachment image: local bytes, a data URL or a file from the server.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({
    super.key,
    required this.attachment,
    required this.baseUrl,
    required this.token,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    this.viewable = false,
  });

  final Widget? fallback;

  /// Tapping opens the image full screen with a save button.
  final bool viewable;
  final ChatAttachment attachment;
  final String baseUrl;
  final String token;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.url != widget.attachment.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final attachment = widget.attachment;
    final local = attachment.localBytes;
    if (local != null) {
      setState(() => _bytes = Uint8List.fromList(local));
      return;
    }

    final url = attachment.url;
    if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma > 0) {
        try {
          setState(() => _bytes = base64Decode(url.substring(comma + 1)));
          return;
        } catch (_) {}
      }
    }

    if (attachment.id.isEmpty && url.isEmpty) {
      setState(() => _failed = true);
      return;
    }

    try {
      final api = OpenWebUiApi(baseUrl: widget.baseUrl, token: widget.token);
      final isAbsolute =
          url.startsWith('http://') || url.startsWith('https://');
      final path = isAbsolute || url.startsWith('/')
          ? url
          : '/api/v1/files/${attachment.id.isNotEmpty ? attachment.id : url}/content';
      final bytes = await api.fetchImage(path);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      final image = _buildImage();
      if (!widget.viewable) return image;
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) =>
                ImageViewerPage(bytes: _bytes!, name: widget.attachment.name),
          ),
        ),
        child: image,
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildImage() {
    {
      return Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, _, _) =>
            widget.fallback ?? const Icon(Icons.broken_image_outlined),
      );
    }
  }

  Widget _buildPlaceholder() {
    if (_failed) {
      if (widget.fallback != null) return widget.fallback!;
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Icon(Icons.broken_image_outlined),
      );
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  String get _extension {
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
    if (bytes.length > 3 && bytes[0] == 0x47 && bytes[1] == 0x49) return 'gif';
    if (bytes.length > 11 && bytes[8] == 0x57 && bytes[9] == 0x45) {
      return 'webp';
    }
    return 'png';
  }

  Future<void> _save(BuildContext context) async {
    final s = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final base = name.isEmpty || name == 'image' || name == 'avatar'
        ? 'image_${DateTime.now().millisecondsSinceEpoch}'
        : name.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '');
    try {
      final saved = await FilePicker.saveFile(
        fileName: '$base.$_extension',
        bytes: bytes,
        mimeType: 'image/$_extension',
      );
      if (saved != null) {
        messenger.showSnackBar(SnackBar(content: Text(s.t('imageSaved'))));
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(s.t('imageSaveFailed', args: {'error': '$error'})),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: s.t('saveImage'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _save(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
