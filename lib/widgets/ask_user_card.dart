import 'package:flutter/material.dart';

import '../ask_user.dart';
import '../l10n.dart';

class AskUserCard extends StatefulWidget {
  const AskUserCard({
    super.key,
    required this.pending,
    required this.onSubmit,
    required this.onCancel,
  });

  final PendingAskUser pending;
  final ValueChanged<Map<String, dynamic>> onSubmit;
  final VoidCallback onCancel;

  @override
  State<AskUserCard> createState() => _AskUserCardState();
}

class _AskUserCardState extends State<AskUserCard> {
  final Map<String, int> _selectedOptions = {};
  final Map<String, bool> _useOther = {};
  final Map<String, TextEditingController> _otherControllers = {};
  final Map<String, FocusNode> _otherFocusNodes = {};

  @override
  void initState() {
    super.initState();
    _createControllers();
  }

  @override
  void didUpdateWidget(covariant AskUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pending.callId != widget.pending.callId ||
        oldWidget.pending.messageId != widget.pending.messageId) {
      _disposeControllers();
      _selectedOptions.clear();
      _useOther.clear();
      _createControllers();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _createControllers() {
    for (final question in widget.pending.prompt.questions) {
      if (question.allowOther) {
        _otherControllers[question.id] = TextEditingController();
        _otherFocusNodes[question.id] = FocusNode();
      }
    }
  }

  void _disposeControllers() {
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    _otherControllers.clear();
    for (final node in _otherFocusNodes.values) {
      node.dispose();
    }
    _otherFocusNodes.clear();
  }

  AskUserAnswer? _answerFor(AskUserQuestion question) {
    final index = _selectedOptions[question.id];
    if (index != null && index < question.options.length) {
      final option = question.options[index];
      return AskUserAnswer.option(
        optionIndex: index,
        label: option.label,
        description: option.description,
      );
    }
    if (question.allowOther && _useOther[question.id] == true) {
      final text = _otherControllers[question.id]?.text.trim() ?? '';
      if (text.isNotEmpty) return AskUserAnswer.other(text);
    }
    return null;
  }

  bool get _complete =>
      widget.pending.prompt.questions.every((q) => _answerFor(q) != null);

  void _submit() {
    final answers = <String, dynamic>{};
    for (final question in widget.pending.prompt.questions) {
      final answer = _answerFor(question);
      if (answer == null) return;
      answers[question.id] = answer.toJson();
    }
    widget.onSubmit(answers);
  }

  void _selectOption(AskUserQuestion question, int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedOptions[question.id] = index;
      _useOther[question.id] = false;
    });
  }

  void _selectOther(AskUserQuestion question) {
    if (_useOther[question.id] == true) return;
    setState(() {
      _useOther[question.id] = true;
      _selectedOptions.remove(question.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final theme = Theme.of(context);
    final questions = widget.pending.prompt.questions;

    final maxHeight = MediaQuery.of(context).size.height * 0.45;

    return Flexible(
      flex: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < questions.length; i++)
                    _buildQuestion(
                      context,
                      s,
                      theme,
                      questions[i],
                      index: i,
                      total: questions.length,
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton(
                        onPressed: widget.onCancel,
                        child: Text(s.t('cancel')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _complete ? _submit : null,
                        child: Text(s.t('askUserSubmit')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    Strings s,
    ThemeData theme,
    AskUserQuestion question, {
    required int index,
    required int total,
  }) {
    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(question.header, style: theme.textTheme.titleSmall),
              ),
              if (total > 1)
                Text(
                  '${index + 1}/$total',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (question.question.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              question.question,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          for (
            var optionIndex = 0;
            optionIndex < question.options.length;
            optionIndex++
          )
            _OptionRow(
              option: question.options[optionIndex],
              selected: _selectedOptions[question.id] == optionIndex,
              recommended: optionIndex == 0,
              recommendedLabel: s.t('askUserRecommended'),
              onTap: () => _selectOption(question, optionIndex),
            ),
          if (question.allowOther)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _selectOther(question);
                _otherFocusNodes[question.id]?.requestFocus();
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _useOther[question.id] == true
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.t('askUserOther'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _otherControllers[question.id],
                        focusNode: _otherFocusNodes[question.id],
                        onTap: () => _selectOther(question),
                        onChanged: (_) {
                          _selectOther(question);
                          setState(() {});
                        },
                        textInputAction: TextInputAction.done,
                        style: theme.textTheme.bodySmall,
                        decoration: InputDecoration(
                          hintText: s.t('askUserOtherHint'),
                          isDense: true,
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.recommended,
    required this.recommendedLabel,
    required this.onTap,
  });

  final AskUserOption option;
  final bool selected;
  final bool recommended;
  final String recommendedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              option.label,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (recommended) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                recommendedLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (option.description.isNotEmpty)
                        Text(
                          option.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
