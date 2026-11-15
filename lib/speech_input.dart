import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voice input for the composer, backed by the platform speech recognizer.
///
/// Only one listen session runs at a time. Partial results are reported while
/// the user speaks so the text field fills in as words are recognized.
class SpeechInput {
  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;

  /// No recognizer on this device; asking again will not help.
  bool _unavailable = false;

  /// Resolved recognition locale, cached per interface language.
  String? _localeLanguage;
  String? _localeId;

  /// Callbacks of the current session. The plugin takes its status and error
  /// listeners only once, in initialize, so they forward to these.
  void Function()? _onDone;
  void Function(String errorKey)? _onError;

  bool get isListening => _initialized && _speech.isListening;

  /// Starts a listen session.
  ///
  /// [baseText] is the text already in the composer; recognized words are
  /// appended to it. [languageCode] is the interface language used to pick a
  /// recognition locale. Returns an error key when the session could not be
  /// started, or null on success.
  Future<String?> start({
    required String languageCode,
    required String baseText,
    required void Function(String text) onText,
    required void Function() onDone,
    required void Function(String errorKey) onError,
  }) async {
    _onDone = onDone;
    _onError = onError;
    if (!_initialized) {
      if (_unavailable) return 'speechUnavailable';
      final available = await _speech.initialize(
        onError: (error) => _onError?.call(_errorKey(error)),
        onStatus: (status) {
          if (status == SpeechToText.doneStatus ||
              status == SpeechToText.notListeningStatus) {
            _onDone?.call();
          }
        },
      );
      if (!available) {
        // The plugin also returns false when the microphone was denied, so
        // tell the two cases apart to point the user at the right fix.
        final granted = await _speech.hasPermission;
        if (!granted) return 'speechPermission';
        _unavailable = true;
        return 'speechUnavailable';
      }
      _initialized = true;
    }

    final localeId = await _localeFor(languageCode);
    final prefix = baseText.isEmpty || baseText.endsWith(' ')
        ? baseText
        : '$baseText ';
    try {
      await _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          onText('$prefix$words');
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          localeId: localeId,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(minutes: 5),
        ),
      );
    } on SpeechToTextNotInitializedException {
      return 'speechUnavailable';
    } catch (_) {
      return 'speechFailed';
    }
    return null;
  }

  /// Ends the session and delivers the last recognized words.
  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _speech.stop();
    } catch (_) {}
  }

  /// Ends the session without delivering a result.
  Future<void> cancel() async {
    if (!_initialized) return;
    try {
      await _speech.cancel();
    } catch (_) {}
  }

  /// Picks a locale for [languageCode], falling back to the system default
  /// when the device does not offer one.
  Future<String?> _localeFor(String languageCode) async {
    if (languageCode.isEmpty) return null;
    if (_localeLanguage == languageCode) return _localeId;
    String? resolved;
    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith(
          languageCode.toLowerCase(),
        )) {
          resolved = locale.localeId;
          break;
        }
      }
    } catch (_) {}
    _localeLanguage = languageCode;
    _localeId = resolved;
    return resolved;
  }

  String _errorKey(SpeechRecognitionError error) {
    switch (error.errorMsg) {
      case 'error_permission':
        return 'speechPermission';
      case 'error_no_match':
      case 'error_speech_timeout':
        return 'speechNoMatch';
      default:
        return 'speechFailed';
    }
  }
}
