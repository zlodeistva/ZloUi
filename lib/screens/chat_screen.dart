import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api.dart';
import '../ask_user.dart';
import '../chat_codec.dart';
import '../l10n.dart';
import '../models.dart';
import '../store.dart';
import '../stream_events.dart';
import '../widgets/ask_user_card.dart';
import '../widgets/attachment_view.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/composer.dart';
import 'chat_drawer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.store,
    required this.session,
    required this.onSessionUpdated,
    required this.onUnauthorized,
    this.assistSignal,
    this.assistantMode = false,
    this.onAssistantClose,
    this.onAssistantOpenApp,
  });

  /// Compact floating digital assistant window instead of the full screen.
  final bool assistantMode;
  final VoidCallback? onAssistantClose;
  final ValueChanged<String?>? onAssistantOpenApp;

  final ValueListenable<AssistRequest>? assistSignal;
  final AppStore store;
  final Session session;
  final ValueChanged<Session> onSessionUpdated;
  final VoidCallback onUnauthorized;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final OpenWebUiApi _api;
  late final TextEditingController _inputController;
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  List<ModelOption> _models = const [];
  String _model = '';
  bool _loadingModels = true;
  String? _modelsError;
  ServerConfig _config = const ServerConfig();
  List<ToolInfo> _tools = const [];
  Set<String> _selectedToolIds = {};
  bool _toolsTouched = false;
  final _composerFocus = FocusNode();
  bool _featuresTouched = false;
  ChatFeatures _features = const ChatFeatures();

  String? _chatId;
  String? _title;
  bool _sending = false;
  bool _loadingChat = false;
  StreamSubscription<ChatEvent>? _events;
  io.Socket? _socket;
  ChatMessage? _streamingMessage;

  /// Replies stopped by the user: late events for them are ignored.
  final Set<String> _stoppedMessageIds = {};
  String? _sessionId;
  Completer<void>? _socketReady;
  String? _lastAssistantId;
  String? _eventChatId;

  // ask_user
  AskUserPrompt? _liveAskUser;
  String? _liveAskUserMessageId;
  String? _liveAskUserInteractionId;
  void Function(Object?)? _liveAskUserAck;
  Timer? _askUserTimeout;
  final Set<String> _answeredAskUserCalls = {};

  ChatPrefs? _prefs;
  Future<void>? _prefsFuture;
  late bool _temporary = widget.assistantMode;
  bool _touchedTemporary = false;

  final List<ChatAttachment> _attachments = [];
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _api = OpenWebUiApi(
      baseUrl: widget.session.baseUrl,
      token: widget.session.token,
    );
    _model = widget.store.model;
    _inputController = TextEditingController();
    widget.assistSignal?.addListener(_onAssist);
    _connectSocket();
    _loadInitialData();
    _refreshPrefs();
  }

  /// Launched as the digital assistant: empty chat, input focused.
  Future<void> _onAssist() async {
    final chatId = widget.assistSignal?.value.chatId;
    if (chatId != null && chatId.isNotEmpty) {
      await _openChat(chatId);
      return;
    }
    await _newChat();
    if (mounted) _composerFocus.requestFocus();
  }

  @override
  void dispose() {
    widget.assistSignal?.removeListener(_onAssist);
    _composerFocus.dispose();
    _askUserTimeout?.cancel();
    _liveAskUserAck?.call({
      'status': 'cancelled',
      'answers': <String, dynamic>{},
    });
    _liveAskUserAck = null;
    _events?.cancel();
    _socket?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _connectSocket() {
    _socket = _api.connectSocket(
      onEvent: _handleEvent,
      onError: (error) {
        // The socket only reports progress; continue without it on failure.
        debugPrint('socket error: $error');
      },
      onConnect: () {
        if (!mounted) return;
        setState(() => _sessionId = _socket?.id);
        _socketReady?.complete();
        _socketReady = null;
      },
      onDisconnect: () {
        if (!mounted) return;
        _clearLiveAskUser(notify: false);
        setState(() => _sessionId = null);
        // Events of the running reply go to the old session and are lost.
        if (_sending) {
          _applyError(
            Strings.of(context).t('connectionLost'),
            _streamingMessage,
          );
        }
      },
    );
    _sessionId = _socket?.id;
  }

  void _handleEvent(ChatEvent event, [void Function(Object?)? ack]) {
    if (!mounted) return;

    if (event.type == 'request:user_input') {
      _handleLiveAskUser(event, ack);
      return;
    }
    if (event.type == 'request:interaction:done') {
      final interactionId = event.data?['interaction_id']?.toString();
      if (interactionId != null && interactionId == _liveAskUserInteractionId) {
        _clearLiveAskUser();
      }
      return;
    }

    if (_chatId == null &&
        event.chatId.isNotEmpty &&
        !_isEphemeralChatId(event.chatId)) {
      _eventChatId = event.chatId;
    }

    final isStreamingMessage =
        event.messageId.isNotEmpty && event.messageId == _streamingMessage?.id;
    final isActiveChat =
        isStreamingMessage ||
        (_chatId != null && event.chatId == _chatId) ||
        (_chatId == null &&
            (event.chatId.startsWith('temporary:') ||
                event.chatId.startsWith('local:')));

    if (event.type == 'chat:title') {
      final title = event.text;
      if (isActiveChat && title != null && title.isNotEmpty) {
        setState(() => _title = title);
      }
      return;
    }

    if (!isActiveChat) return;

    final message = _findMessage(event.messageId);
    if (message != null && _stoppedMessageIds.contains(message.id)) return;

    switch (event.type) {
      case 'chat:completion':
        _applyCompletion(event.data, message);
      case 'response:completion':
        _applyResponseCompletion(event.data, message);
      case 'status':
        if (message != null && event.data != null) {
          final description = (event.data!['description'] ?? '').toString();
          final done = event.data!['done'] == true;
          final hidden = event.data!['hidden'] == true;
          setState(() {
            message.statusText = hidden ? null : description;
            message.statusDone = done;
          });
        }
      case 'source' || 'citation':
        if (message != null) {
          final links = sourceLinksFrom(event.payload);
          if (links.isNotEmpty) {
            setState(() {
              final known = message.sources.map((link) => link.url).toSet();
              message.sources = [
                ...message.sources,
                ...links.where((link) => !known.contains(link.url)),
              ];
            });
          }
        }
      case 'chat:tasks:cancel':
        _handleCancelled(message);
      case 'chat:active':
        final active = event.data?['active'];
        if (active == false && _sending) {
          _finishSending(message);
        }
      case 'chat:message:error':
        final reason = errorFromPayload(event.data);
        if (reason != null) _applyError(reason, message);
      case 'chat:message:delta' || 'message':
        final content = event.data?['content'];
        if (message != null && content is String) {
          setState(() => message.content += content);
          _scrollToBottom();
        }
      case 'chat:message' || 'replace':
        final content = event.data?['content'];
        if (message != null && content is String) {
          setState(() => message.content = content);
        }
      case 'chat:message:files' || 'files':
        final files = event.data?['files'];
        if (message != null && files is List) {
          setState(() {
            message.attachments = [
              for (final file in files)
                if (file is Map)
                  ChatAttachment.fromJson(Map<String, dynamic>.from(file)),
            ];
          });
        }
    }
  }

  /// Replies arrive only through the socket: wait until it is connected.
  Future<bool> _ensureSocket() async {
    if (_sessionId != null) return true;
    final ready = _socketReady ??= Completer<void>();
    try {
      await ready.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // Reported by the caller.
    }
    return mounted && _sessionId != null;
  }

  bool _isEphemeralChatId(String id) =>
      id.startsWith('temporary:') || id.startsWith('local:');

  void _handleLiveAskUser(ChatEvent event, void Function(Object?)? ack) {
    final data = event.data;
    if (data == null || ack == null) return;
    final prompt = AskUserPrompt.fromEventData(data);
    if (prompt == null) {
      ack({'status': 'cancelled', 'answers': <String, dynamic>{}});
      return;
    }

    _askUserTimeout?.cancel();
    final timeout = prompt.timeoutMs;
    if (timeout != null && timeout > 0) {
      _askUserTimeout = Timer(Duration(milliseconds: timeout), () {
        if (!mounted) return;
        _clearLiveAskUser(notify: true);
      });
    }

    setState(() {
      _liveAskUser = prompt;
      _liveAskUserMessageId = event.messageId;
      _liveAskUserInteractionId = prompt.interactionId;
      _liveAskUserAck = ack;
    });
  }

  void _clearLiveAskUser({bool notify = false}) {
    final ack = _liveAskUserAck;
    _askUserTimeout?.cancel();
    _askUserTimeout = null;
    if (notify && ack != null) {
      ack({'status': 'cancelled', 'answers': <String, dynamic>{}});
    }
    if (!mounted) {
      _liveAskUser = null;
      _liveAskUserMessageId = null;
      _liveAskUserInteractionId = null;
      _liveAskUserAck = null;
      return;
    }
    setState(() {
      _liveAskUser = null;
      _liveAskUserMessageId = null;
      _liveAskUserInteractionId = null;
      _liveAskUserAck = null;
    });
  }

  PendingAskUser? get _pendingAskUser {
    final live = _liveAskUser;
    final liveMessageId = _liveAskUserMessageId;
    if (live != null && liveMessageId != null) {
      return PendingAskUser(
        messageId: liveMessageId,
        callId: _liveAskUserInteractionId ?? '',
        prompt: live,
        mode: AskUserMode.live,
        ack: _liveAskUserAck,
      );
    }

    for (final message in _messages.reversed) {
      if (!message.isAssistant) continue;
      for (final call in message.toolCalls) {
        if (call.name != 'ask_user' || call.status != 'pending') continue;
        if (_answeredAskUserCalls.contains(call.id)) continue;
        final prompt = AskUserPrompt.fromArguments(call.arguments);
        if (prompt == null) continue;
        return PendingAskUser(
          messageId: message.id,
          callId: call.id,
          prompt: prompt,
          mode: AskUserMode.saved,
        );
      }
    }
    return null;
  }

  ChatMessage? _messageById(String id) {
    for (final message in _messages.reversed) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _markAskUserCall(ChatMessage message, String callId, String status) {
    for (final item in message.output) {
      if (item['type'] != 'function_call') continue;
      final itemId = (item['call_id'] ?? item['id'])?.toString();
      if (itemId == callId) item['status'] = status;
    }
    for (final call in message.toolCalls) {
      if (call.id == callId) call.status = status;
    }
  }

  Future<void> _submitAskUser(
    PendingAskUser pending,
    Map<String, dynamic> answers,
  ) async {
    if (pending.mode == AskUserMode.live) {
      final ack = pending.ack;
      _clearLiveAskUser();
      if (ack != null) ack({'status': 'answered', 'answers': answers});
      return;
    }

    final chatId = _chatId ?? _eventChatId;
    if (chatId == null || chatId.isEmpty) {
      if (!mounted) return;
      _showMessage(
        Strings.of(context)
            .t('askUserFailed', args: {'error': 'chat is not saved yet'}),
      );
      return;
    }

    final message = _messageById(pending.messageId);
    _answeredAskUserCalls.add(pending.callId);
    setState(() {
      if (message != null) {
        _markAskUserCall(message, pending.callId, 'completed');
        message.done = false;
        _streamingMessage = message;
      }
      _sending = true;
    });
    await _resolveAskUser(chatId: chatId, pending: pending, answers: answers);
  }

  Future<void> _cancelAskUser(PendingAskUser pending) async {
    if (pending.mode == AskUserMode.live) {
      _clearLiveAskUser(notify: true);
      return;
    }

    final chatId = _chatId ?? _eventChatId;
    if (chatId == null || chatId.isEmpty) return;
    final message = _messageById(pending.messageId);
    _answeredAskUserCalls.add(pending.callId);
    setState(() {
      if (message != null) {
        _markAskUserCall(message, pending.callId, 'rejected');
        message.done = false;
        _streamingMessage = message;
      }
      _sending = true;
    });
    await _resolveAskUser(chatId: chatId, pending: pending, action: 'reject');
  }

  Future<void> _resolveAskUser({
    required String chatId,
    required PendingAskUser pending,
    String action = 'answer',
    Map<String, dynamic>? answers,
  }) async {
    try {
      await _api.resolveToolCall(
        chatId: chatId,
        messageId: pending.messageId,
        callId: pending.callId,
        action: action,
        answers: answers,
      );
    } on ApiException catch (error) {
      _answeredAskUserCalls.remove(pending.callId);
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
        return;
      }
      _showMessage(
        Strings.of(context).t('askUserFailed', args: {'error': error.message}),
      );
      await _reloadCurrentChat();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _streamingMessage = null;
      });
    } catch (error) {
      _answeredAskUserCalls.remove(pending.callId);
      if (!mounted) return;
      _showMessage(
        Strings.of(context).t('askUserFailed', args: {'error': '$error'}),
      );
      await _reloadCurrentChat();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _streamingMessage = null;
      });
    }
  }

  Future<void> _reloadCurrentChat() async {
    final id = _chatId ?? _eventChatId;
    if (id == null || id.isEmpty || _isEphemeralChatId(id)) return;
    try {
      final loaded = await _api.getChat(id);
      if (!mounted || id != (_chatId ?? _eventChatId)) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded.messages);
        _chatId = loaded.id.isEmpty ? id : loaded.id;
        _title = loaded.title;
        _lastAssistantId = loaded.messages
            .where((message) => message.isAssistant)
            .lastOrNull
            ?.id;
        _answeredAskUserCalls.clear();
      });
      _scrollToBottom(animate: false);
    } catch (_) {}
  }

  ChatMessage? _findMessage(String id) {
    if (id.isEmpty) {
      return _streamingMessage ??
          (_messages.isNotEmpty ? _messages.last : null);
    }
    for (final message in _messages.reversed) {
      if (message.id == id) return message;
    }
    return _streamingMessage;
  }

  void _applyResponseCompletion(
    Map<String, dynamic>? data,
    ChatMessage? message,
  ) {
    if (data == null || message == null) return;
    setState(() {
      message.output = applyResponseEvent(message.output, data);
      final text = outputText(message.output);
      if (text.isNotEmpty) message.content = text;
      message.reasoning = outputReasoning(message.output);
      message.toolCalls = _toolCallsFrom(message.output);
    });
    _scrollToBottom();
  }

  void _applyCompletion(Map<String, dynamic>? data, ChatMessage? message) {
    if (data == null) return;

    if (message == null) {
      // The reply came without a known id: use the last assistant message.
      for (final candidate in _messages.reversed) {
        if (candidate.isAssistant) {
          message = candidate;
          break;
        }
      }
      if (message == null) return;
    }

    if (message.isAssistant && message.id.isNotEmpty) {
      _lastAssistantId = message.id;
    }
    if (data['sources'] != null) {
      final links = sourceLinksFrom(data['sources']);
      if (links.isNotEmpty) {
        final target = message;
        setState(() {
          final known = target.sources.map((link) => link.url).toSet();
          target.sources = [
            ...target.sources,
            ...links.where((link) => !known.contains(link.url)),
          ];
        });
      }
    }

    final output = data['output'];
    if (output is List) {
      setState(() {
        message!.output = [
          for (final item in output)
            if (item is Map) Map<String, dynamic>.from(item),
        ];
        final text = outputText(message.output);
        if (text.isNotEmpty) message.content = text;
        message.reasoning = outputReasoning(message.output);
        message.toolCalls = _toolCallsFrom(message.output);
        final hasPendingAskUser = message.toolCalls.any(
          (call) => call.name == 'ask_user' && call.status == 'pending',
        );
        if (hasPendingAskUser) {
          _sending = false;
          _streamingMessage = null;
        }
        if (data['usage'] is Map) {
          message.usage = Map<String, dynamic>.from(data['usage'] as Map);
        }
      });
      _scrollToBottom();
      return;
    }

    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map) {
        final delta = choice['delta'];
        final choiceMessage = choice['message'];
        if (choiceMessage is Map && choiceMessage['content'] is String) {
          setState(
            () => message!.content += choiceMessage['content'] as String,
          );
        } else if (delta is Map && delta['content'] is String) {
          setState(() => message!.content += delta['content'] as String);
        }
      }
      _scrollToBottom();
    }

    if (data['content'] is String) {
      setState(() => message!.content = data['content'] as String);
    }

    final error = errorFromPayload(data);
    if (error != null) _applyError(error, message);

    if (data['done'] == true) {
      _finishSending(message);
    }
  }

  List<ToolCall> _toolCallsFrom(List<Map<String, dynamic>> output) {
    return ChatCodec.parseOutput(output, '').toolCalls;
  }

  void _handleCancelled(ChatMessage? message) {
    setState(() {
      _sending = false;
      _streamingMessage = null;
      if (message != null) {
        message.done = true;
        if (message.content.isEmpty && message.toolCalls.isEmpty) {
          message
            ..content = Strings(Localizations.localeOf(context).languageCode)
                .t('generationStopped')
            ..isNotice = true;
        }
      }
    });
  }

  void _applyError(String reason, ChatMessage? message) {
    final s = Strings.of(context);
    setState(() {
      if (message == null || message.content.isEmpty) {
        if (message != null) {
          message
            ..content = '${s.t('errorPrefix')}: $reason'
            ..isNotice = true
            ..done = true;
        } else {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: '${s.t('errorPrefix')}: $reason',
              isNotice: true,
            ),
          );
        }
      } else {
        _messages.add(
          ChatMessage(
            role: 'assistant',
            content: '${s.t('errorPrefix')}: $reason',
            isNotice: true,
          ),
        );
      }
      _sending = false;
      _streamingMessage = null;
    });
    _scrollToBottom();
  }

  Future<void> _loadInitialData() async {
    await Future.wait([_loadModels(), _loadConfig(), _refreshProfile()]);
  }

  Future<void> _refreshProfile() async {
    try {
      final session = await _api.refreshProfile(widget.session);
      await widget.store.saveSession(session);
      if (mounted) widget.onSessionUpdated(session);
    } on ApiException catch (error) {
      if (error.isUnauthorized) _handleUnauthorized();
    } catch (_) {}
  }

  /// Enables the tools the server turns on for the model by default, until
  /// the user changes the selection manually.
  void _applyDefaultTools() {
    final model = _models.where((option) => option.id == _model).firstOrNull;
    if (model == null) return;
    if (!_featuresTouched) {
      final ids = model.defaultFeatureIds.toSet();
      _features = _features.copyWith(
        webSearch: ids.contains('web_search') && _webSearchAvailable,
        codeInterpreter:
            ids.contains('code_interpreter') && _codeInterpreterAvailable,
        imageGeneration:
            ids.contains('image_generation') && _imageGenerationAvailable,
      );
    }
    if (_toolsTouched || _tools.isEmpty) return;
    final available = _tools.map((tool) => tool.id).toSet();
    _selectedToolIds = {
      for (final id in model.toolIds)
        if (available.contains(id)) id,
    };
  }

  Future<void> _loadModels() async {
    try {
      final models = await _api.fetchModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        _modelsError = null;
        if (models.isNotEmpty && !models.any((option) => option.id == _model)) {
          _model = models.first.id;
        }
        _applyDefaultTools();
      });
      if (_model.isNotEmpty) await widget.store.saveModel(_model);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
        return;
      }
      setState(() {
        _loadingModels = false;
        _modelsError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _modelsError = '$error';
      });
    }
  }

  Future<void> _loadConfig() async {
    try {
      final config = await _api.fetchConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _applyDefaultTools();
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) _handleUnauthorized();
    } catch (_) {}

    try {
      final tools = await _api.fetchTools();
      if (!mounted) return;
      setState(() {
        _tools = tools;
        _applyDefaultTools();
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized) _handleUnauthorized();
    } catch (_) {}
  }

  Future<void> _refreshPrefs() {
    final future = _fetchPrefs();
    _prefsFuture = future;
    return future;
  }

  Future<void> _fetchPrefs() async {
    try {
      final prefs = await _api.fetchChatPrefs();
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _applyTemporaryDefault();
      });
    } on ApiException catch (error) {
      if (error.isUnauthorized && mounted) _handleUnauthorized();
    } catch (_) {}
  }

  void _applyTemporaryDefault() {
    if (widget.assistantMode) {
      // Assistant conversations are not saved on the server.
      _temporary = true;
      return;
    }
    final prefs = _prefs;
    if (prefs == null) return;
    final fresh = _messages.isEmpty && _chatId == null;
    if (!fresh) return;
    if (prefs.temporaryEnforced) {
      _temporary = true;
    } else if (!prefs.temporaryAllowed) {
      _temporary = false;
    } else if (!_touchedTemporary) {
      _temporary = prefs.temporaryByDefault;
    }
  }

  bool get _canToggleTemporary {
    final prefs = _prefs;
    return prefs != null && prefs.temporaryAllowed && !prefs.temporaryEnforced;
  }

  void _handleUnauthorized() {
    _clearLiveAskUser(notify: false);
    _events?.cancel();
    _socket?.dispose();
    widget.onUnauthorized();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<List<ChatSummary>> loadChats(int page) => _api.listChats(page: page);

  Future<List<ChatSummary>> loadPinned() => _api.listPinnedChats();

  Future<List<ChatSummary>> loadArchived(int page) =>
      _api.listArchivedChats(page: page);

  Future<List<ChatSummary>> searchChats(String query) =>
      _api.searchChats(query);

  Future<void> _openChat(String id) async {
    if (_loadingChat) return;
    if (id == _chatId) return;
    if (!await _confirmDiscardTemporary()) return;
    if (!mounted) return;
    if (_liveAskUser != null) _clearLiveAskUser(notify: true);
    if (_sending) _stop();

    setState(() => _loadingChat = true);
    try {
      final loaded = await _api.getChat(id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(loaded.messages);
        _chatId = loaded.id.isEmpty ? id : loaded.id;
        _title = loaded.title;
        _lastAssistantId = loaded.messages
            .where((message) => message.isAssistant)
            .lastOrNull
            ?.id;
        _temporary = false;
        _touchedTemporary = true;
        _eventChatId = null;
        _answeredAskUserCalls.clear();
        final model = loaded.model;
        if (model != null &&
            model.isNotEmpty &&
            (_models.isEmpty || _models.any((option) => option.id == model))) {
          _model = model;
        }
      });
      if (_model.isNotEmpty) widget.store.saveModel(_model);
      _scrollToBottom(animate: false);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
        return;
      }
      _showMessage(
        error.isNotFound
            ? Strings.of(context).t('chatNotFound')
            : Strings.of(context)
                  .t('openChatFailed', args: {'error': error.message}),
      );
    } finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  Future<void> _newChat({bool? temporary}) async {
    if (!await _confirmDiscardTemporary()) return;
    if (!mounted) return;
    if (_liveAskUser != null) _clearLiveAskUser(notify: true);
    if (_sending) _stop();

    setState(() {
      _messages.clear();
      _attachments.clear();
      _chatId = null;
      _eventChatId = null;
      _title = null;
      _lastAssistantId = null;
      _answeredAskUserCalls.clear();
      _toolsTouched = false;
      _featuresTouched = false;
      _applyDefaultTools();
      _touchedTemporary = temporary != null;
      final prefs = _prefs;
      if (prefs != null && prefs.temporaryEnforced) {
        _temporary = true;
      } else if (temporary != null) {
        _temporary = temporary;
      } else {
        _temporary = false;
        _applyTemporaryDefault();
      }
    });

    if (temporary == null) _refreshPrefs();
  }

  Future<void> _toggleTemporary() => _newChat(temporary: !_temporary);

  Future<bool> _confirmDiscardTemporary() async {
    if (!_temporary || _messages.isEmpty) return true;
    final s = Strings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('temporaryChatCloseTitle')),
        content: Text(s.t('temporaryChatCloseBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('close')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _renameChat(ChatSummary chat) async {
    final s = Strings.of(context);
    final controller = TextEditingController(text: chat.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('renameChat')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: s.t('rename'),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || result == chat.title) return;
    try {
      await _api.renameChat(chat.id, result);
      if (!mounted) return;
      if (chat.id == _chatId) setState(() => _title = result);
      _showMessage(s.t('save'));
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
      } else {
        _showMessage(s.t('saveFailed', args: {'error': error.message}));
      }
    }
  }

  Future<void> _deleteChat(ChatSummary chat) async {
    final s = Strings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deleteChatTitle')),
        content: Text(s.t('deleteChatBody', args: {'title': chat.title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deleteChat(chat.id);
      if (!mounted) return;
      if (chat.id == _chatId) {
        await _newChat();
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
      } else {
        _showMessage(error.message);
      }
    }
  }

  Future<void> _pinChat(ChatSummary chat) async {
    try {
      await _api.pinChat(chat.id);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
      } else {
        _showMessage(error.message);
      }
    }
  }

  Future<void> _archiveChat(ChatSummary chat) async {
    try {
      await _api.archiveChat(chat.id);
      if (!mounted) return;
      if (chat.id == _chatId) await _newChat();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
      } else {
        _showMessage(error.message);
      }
    }
  }

  Future<void> _cloneChat(ChatSummary chat) async {
    try {
      final id = await _api.cloneChat(chat.id, chat.title);
      if (!mounted) return;
      await _openChat(id);
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
      } else {
        _showMessage(error.message);
      }
    }
  }

  Future<void> _send() async {
    if (_sending || _loadingChat || _uploading) return;
    final text = _inputController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (_model.isEmpty) {
      _showMessage(Strings.of(context).t('selectModelFirst'));
      return;
    }

    final pending = _prefsFuture;
    if (_prefs == null && pending != null) {
      await pending;
      if (!mounted || _sending) return;
    }

    if (!await _ensureSocket()) {
      if (mounted) _showMessage(Strings.of(context).t('notConnected'));
      return;
    }
    if (!mounted || _sending) return;

    FocusScope.of(context).unfocus();

    final userMessage = ChatMessage(
      role: 'user',
      content: text,
      parentId: _lastAssistantId,
      attachments: List.of(_attachments),
    );
    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
      model: _model,
      done: false,
    );
    final history = [
      ..._messages.where(
        (m) =>
            !m.isNotice &&
            (m.content.trim().isNotEmpty || m.attachments.isNotEmpty),
      ),
      userMessage,
    ];

    setState(() {
      _messages
        ..add(userMessage)
        ..add(assistantMessage);
      _streamingMessage = assistantMessage;
      _sending = true;
      _attachments.clear();
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final temporaryChatId = _temporary
          ? 'temporary:${_sessionId ?? _socket?.id ?? ''}'
          : null;
      final newChatId = await _api.sendMessage(
        model: _model,
        history: history,
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        chatId: temporaryChatId ?? _chatId,
        sessionId: _sessionId,
        temporary: _temporary,
        parentId: _lastAssistantId,
        features: _features,
        toolIds: _selectedToolIds.toList(),
      );
      if (!mounted) return;
      if (!_temporary && newChatId != null) {
        setState(() => _chatId = newChatId);
      }
      if (assistantMessage.content.isNotEmpty) {
        _lastAssistantId = assistantMessage.id;
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
        return;
      }
      _applyError(error.message, assistantMessage);
    }
  }

  void _stop() {
    if (_liveAskUser != null) _clearLiveAskUser(notify: true);
    final chatId = _temporary
        ? 'temporary:${_sessionId ?? _socket?.id ?? ''}'
        : _chatId;
    final message = _streamingMessage;
    if (chatId != null) {
      _api.stopGeneration(chatId).catchError((_) {});
    }
    if (message != null) _stoppedMessageIds.add(message.id);
    setState(() {
      _sending = false;
      _streamingMessage = null;
      if (message != null) {
        message.done = true;
        if (message.content.isEmpty && message.toolCalls.isEmpty) {
          message
            ..content = Strings.of(context).t('generationStopped')
            ..isNotice = true;
        }
      }
    });
  }

  void _finishSending(ChatMessage? message) {
    if (!mounted || !_sending) return;
    setState(() {
      _sending = false;
      _streamingMessage = null;
      if (message != null) {
        message.done = true;
        if (message.content.isEmpty &&
            message.toolCalls.isEmpty &&
            message.reasoning.isEmpty) {
          message
            ..content = Strings.of(context).t('emptyResponse')
            ..isNotice = true;
        }
      }
    });
    _scrollToBottom();
  }

  Future<void> _regenerate(ChatMessage message) async {
    if (_sending) return;
    if (!await _ensureSocket()) {
      if (mounted) _showMessage(Strings.of(context).t('notConnected'));
      return;
    }
    if (!mounted || _sending) return;

    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;

    // Find the user message that precedes this reply.
    var userIndex = index - 1;
    while (userIndex >= 0 && _messages[userIndex].role != 'user') {
      userIndex--;
    }
    if (userIndex < 0) return;
    final userMessage = _messages[userIndex];

    setState(() {
      _messages.removeRange(userIndex + 1, _messages.length);
    });

    final assistantMessage = ChatMessage(
      role: 'assistant',
      content: '',
      model: _model,
      done: false,
    );
    setState(() {
      _messages.add(assistantMessage);
      _streamingMessage = assistantMessage;
      _sending = true;
    });
    _scrollToBottom();

    try {
      final temporaryChatId = _temporary
          ? 'temporary:${_sessionId ?? _socket?.id ?? ''}'
          : null;
      final newChatId = await _api.sendMessage(
        model: _model,
        history: _messages.sublist(0, userIndex + 1),
        userMessage: userMessage,
        assistantMessage: assistantMessage,
        chatId: temporaryChatId ?? _chatId,
        sessionId: _sessionId,
        temporary: _temporary,
        parentId: userMessage.parentId,
        features: _features,
        toolIds: _selectedToolIds.toList(),
      );
      if (!mounted) return;
      if (!_temporary && newChatId != null) {
        setState(() => _chatId = newChatId);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
        return;
      }
      _applyError(error.message, assistantMessage);
    }
  }

  Future<void> _pickAttachments({required bool imagesOnly}) async {
    if (_uploading) return;
    final s = Strings.of(context);
    final maxCount = _config.maxFileCount;
    if (maxCount != null && _attachments.length >= maxCount) {
      _showMessage(s.t('attachmentFailed'));
      return;
    }

    final files = await FilePicker.pickFiles(
      type: imagesOnly ? FileType.image : FileType.any,
    );
    if (files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      for (final file in files) {
        final bytes = await file.readAsBytes();

        final maxSize = _config.maxFileSize;
        if (maxSize != null && bytes.length > maxSize * 1024 * 1024) {
          _showMessage(s.t('attachmentFailed'));
          continue;
        }

        final contentType =
            lookupMimeType(file.name, headerBytes: bytes) ??
            (imagesOnly ? 'image/png' : 'application/octet-stream');

        if (_temporary) {
          // Temporary chat: files are not uploaded to the server.
          if (contentType.startsWith('image/')) {
            final dataUrl = 'data:$contentType;base64,${base64Encode(bytes)}';
            if (!mounted) return;
            setState(() {
              _attachments.add(
                ChatAttachment(
                  id: newId(),
                  name: file.name,
                  type: 'image',
                  url: dataUrl,
                  contentType: contentType,
                  size: bytes.length,
                  localBytes: bytes,
                ),
              );
            });
          } else {
            final decoded = _decodeText(bytes);
            if (decoded == null) {
              _showMessage(s.t('temporaryFilesUnsupported'));
              continue;
            }
            if (!mounted) return;
            setState(() {
              _attachments.add(
                ChatAttachment(
                  id: newId(),
                  name: file.name,
                  type: 'text',
                  contentType: contentType,
                  size: bytes.length,
                  content: decoded,
                ),
              );
            });
          }
        } else {
          final uploaded = await _api.uploadFile(
            filename: file.name,
            bytes: bytes,
            contentType: contentType,
          );
          if (!mounted) return;
          setState(() {
            _attachments.add(
              ChatAttachment(
                id: uploaded.id,
                name: uploaded.name,
                type: uploaded.type,
                url: uploaded.url,
                contentType: uploaded.contentType,
                size: uploaded.size,
                localBytes: uploaded.isImage ? bytes : null,
              ),
            );
          });
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isUnauthorized) {
        _handleUnauthorized();
      } else {
        _showMessage(s.t('attachmentFailed'));
      }
    } catch (error) {
      if (mounted) _showMessage(s.t('attachmentFailed'));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String? _decodeText(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      if (text.contains('\u0000')) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  bool get _webSearchAvailable =>
      _config.feature('enable_web_search') &&
      _config.permission('features.web_search');

  bool get _codeInterpreterAvailable =>
      _config.feature('enable_code_interpreter') &&
      _config.permission('features.code_interpreter');

  bool get _imageGenerationAvailable =>
      _config.feature('enable_image_generation') &&
      _config.permission('features.image_generation');

  bool get _memoryAvailable =>
      _config.feature('enable_memories') &&
      _config.permission('features.memories');

  Future<void> _showToolsSheet() async {
    final s = Strings.of(context);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Changes apply immediately, not when the sheet closes.
            void update(void Function() change) {
              final before = _features;
              setState(() {
                change();
                if (!identical(before, _features)) _featuresTouched = true;
              });
              setSheetState(() {});
            }

            final capabilities = [
              if (_webSearchAvailable)
                _FeatureTile(
                  icon: Icons.language,
                  title: s.t('webSearch'),
                  subtitle: s.t('webSearchHint'),
                  value: _features.webSearch,
                  onChanged: (value) => update(
                    () => _features = _features.copyWith(webSearch: value),
                  ),
                ),
              if (_codeInterpreterAvailable)
                _FeatureTile(
                  icon: Icons.terminal,
                  title: s.t('codeInterpreter'),
                  subtitle: s.t('codeInterpreterHint'),
                  value: _features.codeInterpreter,
                  onChanged: (value) => update(
                    () =>
                        _features = _features.copyWith(codeInterpreter: value),
                  ),
                ),
              if (_imageGenerationAvailable)
                _FeatureTile(
                  icon: Icons.image_outlined,
                  title: s.t('imageGeneration'),
                  subtitle: s.t('imageGenerationHint'),
                  value: _features.imageGeneration,
                  onChanged: (value) => update(
                    () =>
                        _features = _features.copyWith(imageGeneration: value),
                  ),
                ),
              if (_memoryAvailable)
                _FeatureTile(
                  icon: Icons.psychology_outlined,
                  title: s.t('memory'),
                  subtitle: s.t('memoryHint'),
                  value: _features.memory,
                  onChanged: (value) => update(
                    () => _features = _features.copyWith(memory: value),
                  ),
                ),
            ];

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (capabilities.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                        child: Text(
                          s.t('features'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ...capabilities,
                      const Divider(),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text(
                        s.t('tools'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (_tools.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Text(
                          s.t('noTools'),
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      for (final tool in _tools)
                        CheckboxListTile(
                          value: _selectedToolIds.contains(tool.id),
                          title: Text(tool.name),
                          subtitle: tool.description.isEmpty
                              ? null
                              : Text(
                                  tool.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          secondary: Icon(
                            tool.isMcp
                                ? Icons.hub_outlined
                                : Icons.build_outlined,
                          ),
                          onChanged: (value) => update(() {
                            final next = Set<String>.of(_selectedToolIds);
                            if (value == true) {
                              next.add(tool.id);
                            } else {
                              next.remove(tool.id);
                            }
                            _selectedToolIds = next;
                            _toolsTouched = true;
                          }),
                        ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showModelSheet() async {
    final s = Strings.of(context);
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                child: Row(
                  children: [
                    Text(
                      s.t('chooseModel'),
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: s.t('refresh'),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _loadModels();
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              if (_models.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(s.t('noModels')),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _models.length,
                    itemBuilder: (context, index) {
                      final option = _models[index];
                      final isSelected = option.id == _model;
                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(option.name),
                        selected: isSelected,
                        onTap: () => Navigator.pop(sheetContext, option.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      setState(() {
        _model = selected;
        _applyDefaultTools();
      });
      await widget.store.saveModel(selected);
    }
  }

  void _copyMessage(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    _showMessage(Strings.of(context).t('copied'));
  }

  Widget _assistantChip({
    required IconData icon,
    String? label,
    int badge = 0,
    bool flexible = false,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final chip = Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$badge',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return flexible ? Flexible(child: chip) : chip;
  }

  int get _activeToolCount =>
      _selectedToolIds.length +
      (_features.webSearch ? 1 : 0) +
      (_features.codeInterpreter ? 1 : 0) +
      (_features.imageGeneration ? 1 : 0);

  /// "Open full screen": saves the conversation on the server and opens it
  /// in the app.
  Future<void> _assistantOpenFull() async {
    final open = widget.onAssistantOpenApp;
    if (open == null) return;
    final messages = _messages.where((m) => !m.isNotice).toList();
    if (messages.isEmpty || _sending) {
      open(null);
      return;
    }
    try {
      final id = await _api.importChat(
        title: _title ?? messages.first.content,
        model: _model,
        messages: messages,
      );
      open(id);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        _handleUnauthorized();
        return;
      }
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('$error');
    }
  }

  Offset? _swipeStart;
  bool _swipeHandled = false;

  /// A swipe right anywhere opens the drawer. Raw pointer events are used so
  /// it does not conflict with scrolling or system gestures.
  Widget _swipeToDrawer(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _swipeStart = event.position;
        _swipeHandled = false;
      },
      onPointerMove: (event) {
        final start = _swipeStart;
        if (start == null || _swipeHandled) return;
        final dx = event.position.dx - start.dx;
        final dy = (event.position.dy - start.dy).abs();
        if (dx > 70 && dx > dy * 2) {
          _swipeHandled = true;
          FocusManager.instance.primaryFocus?.unfocus();
          _scaffoldKey.currentState?.openDrawer();
        }
      },
      onPointerUp: (_) => _swipeStart = null,
      onPointerCancel: (_) => _swipeStart = null,
      child: child,
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final pendingAskUser = _pendingAskUser;
    final modelName =
        _models.where((m) => m.id == _model).firstOrNull?.name ??
        (_model.isEmpty ? s.t('model') : _model);
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.4),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onAssistantClose,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  elevation: 6,
                  shadowColor: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 2, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _assistantChip(
                                      icon: Icons.tune,
                                      label: modelName,
                                      flexible: true,
                                      onTap: _showModelSheet,
                                    ),
                                    const SizedBox(width: 8),
                                    _assistantChip(
                                      icon: Icons.build_outlined,
                                      badge: _activeToolCount,
                                      onTap: _showToolsSheet,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: s.t('assistantOpenApp'),
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.open_in_full, size: 18),
                              onPressed: _assistantOpenFull,
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: widget.onAssistantClose,
                            ),
                          ],
                        ),
                      ),
                      if (_loadingModels || _loadingChat)
                        const LinearProgressIndicator(minHeight: 2),
                      if (_modelsError != null)
                        _ErrorBanner(
                          text: _modelsError!,
                          actionLabel: s.t('retry'),
                          onAction: _loadModels,
                        ),
                      if (_messages.isNotEmpty)
                        Flexible(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: height * 0.45,
                            ),
                            child: _messageList(
                              pendingAskUser,
                              shrinkWrap: true,
                            ),
                          ),
                        ),
                      if (_attachments.isNotEmpty)
                        AttachmentStrip(
                          attachments: _attachments,
                          baseUrl: widget.session.baseUrl,
                          token: widget.session.token,
                          onRemove: (attachment) =>
                              setState(() => _attachments.remove(attachment)),
                        ),
                      if (pendingAskUser != null)
                        AskUserCard(
                          key: ValueKey(
                            '${pendingAskUser.mode}-${pendingAskUser.messageId}-'
                            '${pendingAskUser.callId}',
                          ),
                          pending: pendingAskUser,
                          onSubmit: (answers) =>
                              _submitAskUser(pendingAskUser, answers),
                          onCancel: () => _cancelAskUser(pendingAskUser),
                        ),
                      Composer(
                        controller: _inputController,
                        focusNode: _composerFocus,
                        sending: _sending,
                        enabled: _model.isNotEmpty && pendingAskUser == null,
                        uploading: _uploading,
                        autofocus: true,
                        transparent: true,
                        hintText: _model.isEmpty
                            ? s.t('selectModelFirst')
                            : s.t('assistantHint'),
                        onSend: _send,
                        onStop: _stop,
                        onAttach: () => _showAttachMenu(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageList(
    PendingAskUser? pendingAskUser, {
    bool shrinkWrap = false,
  }) {
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: shrinkWrap,
      padding: shrinkWrap
          ? const EdgeInsets.fromLTRB(12, 6, 12, 8)
          : const EdgeInsets.fromLTRB(12, 12, 12, 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isLast = index == _messages.length - 1;
        return ChatBubble(
          message: message,
          baseUrl: widget.session.baseUrl,
          token: widget.session.token,
          streaming:
              _sending &&
              pendingAskUser == null &&
              isLast &&
              message.isAssistant,
          showProgress:
              _sending &&
              pendingAskUser == null &&
              isLast &&
              message.isAssistant &&
              message.content.isEmpty &&
              message.toolCalls.isEmpty &&
              message.reasoning.isEmpty,
          onCopy: () => _copyMessage(message),
          onRegenerate: message.isAssistant && !_sending && !_temporary
              ? () => _regenerate(message)
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.assistantMode) return _buildAssistant(context);
    final s = Strings.of(context);
    final modelLabel = _model.isEmpty ? s.t('model') : _model;
    final pendingAskUser = _pendingAskUser;
    final titleText = _temporary
        ? s.t('temporaryChat')
        : (_title ?? s.t('chat'));

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        titleSpacing: 4,
        title: Text(
          titleText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontSize: 16, height: 1.15),
        ),
        actions: [
          if (_canToggleTemporary)
            IconButton(
              tooltip: _temporary
                  ? s.t('temporaryChatExit')
                  : s.t('temporaryChat'),
              isSelected: _temporary,
              icon: const Icon(Icons.visibility_off_outlined),
              selectedIcon: const Icon(Icons.visibility_off),
              onPressed: _toggleTemporary,
            ),
          IconButton(
            tooltip: s.t('tools'),
            onPressed: _showToolsSheet,
            icon: Badge(
              isLabelVisible: _selectedToolIds.isNotEmpty,
              label: Text('${_selectedToolIds.length}'),
              child: const Icon(Icons.build_outlined),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: ChatDrawer(
        currentChatId: _chatId,
        loadChats: loadChats,
        loadArchived: loadArchived,
        loadPinned: loadPinned,
        searchChats: searchChats,
        onOpenChat: _openChat,
        onNewChat: () => _newChat(),
        onDelete: _deleteChat,
        onRename: _renameChat,
        onPin: _pinChat,
        onArchive: _archiveChat,
        onClone: _cloneChat,
      ),
      body: _swipeToDrawer(
        Column(
          children: [
            if (_loadingModels || _loadingChat)
              const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _assistantChip(
                  icon: Icons.tune,
                  label:
                      _models.where((m) => m.id == _model).firstOrNull?.name ??
                      modelLabel,
                  onTap: _showModelSheet,
                ),
              ),
            ),
            if (_modelsError != null)
              _ErrorBanner(
                text: _modelsError!,
                actionLabel: s.t('retry'),
                onAction: _loadModels,
              ),
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyState(
                      temporary: _temporary,
                      modelLabel: modelLabel,
                      onPickModel: _showModelSheet,
                    )
                  : _messageList(pendingAskUser),
            ),
            if (_attachments.isNotEmpty)
              AttachmentStrip(
                attachments: _attachments,
                baseUrl: widget.session.baseUrl,
                token: widget.session.token,
                onRemove: (attachment) =>
                    setState(() => _attachments.remove(attachment)),
              ),
            if (pendingAskUser != null)
              AskUserCard(
                key: ValueKey(
                  '${pendingAskUser.mode}-${pendingAskUser.messageId}-'
                  '${pendingAskUser.callId}',
                ),
                pending: pendingAskUser,
                onSubmit: (answers) => _submitAskUser(pendingAskUser, answers),
                onCancel: () => _cancelAskUser(pendingAskUser),
              ),
            Composer(
              controller: _inputController,
              focusNode: _composerFocus,
              sending: _sending,
              enabled: _model.isNotEmpty && pendingAskUser == null,
              uploading: _uploading,
              hintText: _model.isEmpty
                  ? s.t('selectModelFirst')
                  : s.t('messageHint'),
              onSend: _send,
              onStop: _stop,
              onAttach: () => _showAttachMenu(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAttachMenu() async {
    final s = Strings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(s.t('attachImage')),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAttachments(imagesOnly: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(s.t('attachFile')),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAttachments(imagesOnly: false);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.temporary,
    required this.modelLabel,
    required this.onPickModel,
  });

  final bool temporary;
  final String modelLabel;
  final VoidCallback onPickModel;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              temporary
                  ? Icons.visibility_off_outlined
                  : Icons.chat_bubble_outline_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              temporary ? s.t('temporaryEmptyTitle') : s.t('emptyChatTitle'),
              style: theme.textTheme.titleMedium,
            ),
            if (temporary) ...[
              const SizedBox(height: 8),
              Text(
                s.t('temporaryEmptySubtitle'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (modelLabel.isEmpty) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onPickModel,
                icon: const Icon(Icons.tune),
                label: Text(s.t('selectModel')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
