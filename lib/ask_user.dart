import 'dart:convert';

class AskUserOption {
  const AskUserOption({required this.label, required this.description});

  final String label;
  final String description;

  factory AskUserOption.fromJson(Map json) => AskUserOption(
    label: (json['label'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
  );
}

class AskUserQuestion {
  const AskUserQuestion({
    required this.id,
    required this.header,
    required this.question,
    required this.options,
    this.allowOther = true,
  });

  final String id;
  final String header;
  final String question;
  final List<AskUserOption> options;
  final bool allowOther;
}

enum AskUserMode { saved, live }

class AskUserPrompt {
  const AskUserPrompt({
    required this.questions,
    required this.allowOther,
    required this.mode,
    this.timeoutMs,
    this.interactionId,
  });

  final List<AskUserQuestion> questions;
  final bool allowOther;
  final AskUserMode mode;
  final int? timeoutMs;
  final String? interactionId;

  static AskUserPrompt? fromArguments(
    Object? raw, {
    AskUserMode mode = AskUserMode.saved,
    int? timeoutMs,
    String? interactionId,
  }) {
    Object? value = raw;
    while (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        break;
      }
    }
    if (value is! Map) return null;

    final rawQuestions = value['questions'];
    if (rawQuestions is! List || rawQuestions.isEmpty) return null;

    final allowOther = value['allow_other'] != false;
    final questions = <AskUserQuestion>[];
    for (var index = 0; index < rawQuestions.length; index++) {
      final rawQuestion = rawQuestions[index];
      if (rawQuestion is! Map) continue;
      final rawId = (rawQuestion['id'] ?? '').toString();
      final id = rawId.isEmpty ? 'q${index + 1}' : rawId;

      final options = <AskUserOption>[];
      final rawOptions = rawQuestion['options'];
      if (rawOptions is List) {
        for (final rawOption in rawOptions) {
          if (rawOption is Map) {
            options.add(AskUserOption.fromJson(rawOption));
          }
        }
      }

      questions.add(
        AskUserQuestion(
          id: id,
          header: (rawQuestion['header'] ?? '').toString(),
          question: (rawQuestion['question'] ?? '').toString(),
          options: options,
          allowOther: rawQuestion['allow_other'] is bool
              ? rawQuestion['allow_other'] as bool
              : allowOther,
        ),
      );
    }

    if (questions.isEmpty) return null;
    return AskUserPrompt(
      questions: questions,
      allowOther: allowOther,
      mode: mode,
      timeoutMs: timeoutMs,
      interactionId: interactionId,
    );
  }

  static AskUserPrompt? fromEventData(Map<String, dynamic> data) {
    final interactionId = (data['interaction_id'] ?? '').toString();
    final timeout = (data['timeout_ms'] as num?)?.toInt();
    return fromArguments(
      data,
      mode: AskUserMode.live,
      timeoutMs: timeout,
      interactionId: interactionId.isEmpty ? null : interactionId,
    );
  }
}

class AskUserAnswer {
  const AskUserAnswer.option({
    required this.optionIndex,
    required this.label,
    required this.description,
  }) : text = null;

  const AskUserAnswer.other(String this.text)
    : optionIndex = null,
      label = null,
      description = null;

  final int? optionIndex;
  final String? label;
  final String? description;
  final String? text;

  Map<String, dynamic> toJson() => text != null
      ? {'type': 'other', 'text': text}
      : {
          'type': 'option',
          'option_index': optionIndex,
          'label': label,
          'description': description,
        };
}

class PendingAskUser {
  const PendingAskUser({
    required this.messageId,
    required this.callId,
    required this.prompt,
    required this.mode,
    this.ack,
  });

  final String messageId;
  final String callId;
  final AskUserPrompt prompt;
  final AskUserMode mode;
  final void Function(Object? response)? ack;
}
