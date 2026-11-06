import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

final _fenceStart = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*(\S*)');
final _inlineCode = RegExp(r'(`{1,3})[^`\n]+?\1');
final _bracketMath = RegExp(r'\\\[([\s\S]+?)\\\]');
final _parenMath = RegExp(r'\\\(([\s\S]+?)\\\)');
const _mathLanguages = {'math', 'latex', 'tex', 'katex'};

/// Rewrites the LaTeX notations that models use into the `$...$` and `$$...$$`
/// forms handled by [MathInlineSyntax]. Code blocks and code spans are kept.
String prepareMathMarkdown(String input) {
  if (!input.contains(r'\(') &&
      !input.contains(r'\[') &&
      !input.contains('```') &&
      !input.contains('~~~')) {
    return input;
  }

  final stash = <String>[];
  String hold(String text) {
    stash.add(text);
    return '\u0000${stash.length - 1}\u0000';
  }

  final lines = input.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final open = _fenceStart.firstMatch(lines[i]);
    if (open == null) {
      out.add(lines[i]);
      i++;
      continue;
    }
    final marker = open.group(1)!;
    final language = open.group(2)!.toLowerCase();
    var end = i + 1;
    while (end < lines.length) {
      final trimmed = lines[end].trim();
      if (trimmed.startsWith(marker) &&
          trimmed.replaceAll(marker[0], '').isEmpty) {
        break;
      }
      end++;
    }
    final closed = end < lines.length;
    if (closed && _mathLanguages.contains(language)) {
      final body = lines.sublist(i + 1, end).join('\n').trim();
      out.add(hold('\n\n\$\$$body\$\$\n\n'));
    } else {
      final last = closed ? end : lines.length - 1;
      out.add(hold(lines.sublist(i, last + 1).join('\n')));
    }
    i = (closed ? end : lines.length - 1) + 1;
  }

  var text = out.join('\n');
  text = text.replaceAllMapped(_inlineCode, (m) => hold(m.group(0)!));
  text = text.replaceAllMapped(_parenMath, (m) => '\$${m.group(1)!.trim()}\$');
  text = text.replaceAllMapped(_bracketMath, (m) {
    final body = m.group(1)!.trim();
    final before = text.substring(0, m.start);
    final after = text.substring(m.end);
    final lineStart = before.substring(before.lastIndexOf('\n') + 1);
    final nextBreak = after.indexOf('\n');
    final lineEnd = nextBreak == -1 ? after : after.substring(0, nextBreak);
    if (lineStart.trim().isEmpty && lineEnd.trim().isEmpty) {
      return '\n\n\$\$$body\$\$\n\n';
    }
    return '\$$body\$';
  });

  return text.replaceAllMapped(
    RegExp('\u0000(\\d+)\u0000'),
    (m) => stash[int.parse(m.group(1)!)],
  );
}

/// Matches `$$...$$` (display) and `$...$` (inline) and produces a `math`
/// element. The pattern avoids treating prices like "$5 and $6" as formulas.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax()
    : super(
        r'\$\$([^$]+?)\$\$(?![\w$])|\$([^\s$](?:[^$]*[^\s$])?)\$(?![\w$])',
        startCharacter: 0x24,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match.group(1) != null;
    final tex = (match.group(1) ?? match.group(2))!.trim();
    if (tex.isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    final element = md.Element.text('math', tex);
    if (display) element.attributes['display'] = 'block';
    parser.addNode(element);
    return true;
  }
}

class MathMarkdownBuilder extends MarkdownElementBuilder {
  MathMarkdownBuilder({this.style});

  final TextStyle? style;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return MathView(
      tex: element.textContent,
      display: element.attributes['display'] == 'block',
      style: style ?? parentStyle ?? preferredStyle,
    );
  }
}

class MathView extends StatelessWidget {
  const MathView({
    super.key,
    required this.tex,
    required this.display,
    this.style,
  });

  final String tex;
  final bool display;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final textStyle = style ?? DefaultTextStyle.of(context).style;
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: textStyle,
      onErrorFallback: (_) => Text(
        display ? '\$\$$tex\$\$' : '\$$tex\$',
        style: textStyle.copyWith(fontFamily: 'monospace'),
      ),
    );
    if (!display) return math;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FittedBox(fit: BoxFit.scaleDown, child: math),
    );
  }
}
