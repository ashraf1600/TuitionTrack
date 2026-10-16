import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../core/science_text.dart';
import '../theme/tt_theme.dart';

// Every way maths arrives from ChatGPT, textbooks and the website's editor:
//   $$…$$ and \[…\] (display)   ·   \(…\) and $…$ (inline)
// The inline-$ form must hug its content, so prices like "$5 and $10" stay as text.
final _mathPattern = mathPattern;
final _moneyOnly = RegExp(r'^\s*\d+([.,]\d+)?\s*$');

class MathSegment {
  MathSegment.text(this.text)
      : isMath = false,
        display = false;
  MathSegment.math(this.text, {required this.display}) : isMath = true;

  final String text;
  final bool isMath;
  final bool display;
}

/// Splits text into plain runs and formulas.
List<MathSegment> splitMath(String source) {
  final segments = <MathSegment>[];
  var cursor = 0;
  for (final match in _mathPattern.allMatches(source)) {
    final inline = match[4];
    if (inline != null && _moneyOnly.hasMatch(inline)) continue; // "$ 5000 $" is money
    if (match.start > cursor) segments.add(MathSegment.text(source.substring(cursor, match.start)));
    final display = match[1] != null || match[2] != null;
    segments.add(MathSegment.math((match[1] ?? match[2] ?? match[3] ?? inline!).trim(), display: display));
    cursor = match.end;
  }
  if (cursor < source.length) segments.add(MathSegment.text(source.substring(cursor)));
  return segments;
}

Widget _formula(String tex, TextStyle style, {required bool display}) {
  final math = Math.tex(
    // Chemistry (\ce), units, Unicode symbols and numbered environments made renderable.
    prepareTex(tex),
    textStyle: style,
    mathStyle: display ? MathStyle.display : MathStyle.text,
    // Still not valid LaTeX: show it as readable text, not raw commands.
    onErrorFallback: (error) => Text(texToPlain(tex), style: style),
  );
  // A long formula scrolls sideways instead of overflowing the screen.
  return SingleChildScrollView(scrollDirection: Axis.horizontal, child: math);
}

/// ChatGPT's Markdown headings ("### Title") as bold lines ("**Title**").
String _headingsAsBold(String text) => text.replaceAllMapped(
      RegExp(r'^[ \t]*#{1,6}[ \t]+(.+?)[ \t]*$', multiLine: true),
      (m) => '**${m[1]}**',
    );

/// Plain text (an MCQ question, an option, an explanation, a pasted CQ) with
/// its LaTeX typeset. Doubled backslashes from JSON are made single, LaTeX
/// without $…$ is found, **bold** and # headings from ChatGPT are shown bold,
/// and `code` is never read as maths. The stored text itself is not changed.
class MathText extends StatelessWidget {
  const MathText(this.text, {super.key, this.style, this.maxLines});

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final source = normalizeEscapes(text);
    final plainOnly = !source.contains(r'$') &&
        !source.contains(r'\') &&
        !source.contains('^') &&
        !source.contains('_') &&
        !source.contains('**') &&
        !source.contains('`') &&
        !source.contains('#');
    if (plainOnly) {
      return Text(source, style: base, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis);
    }

    final spans = <InlineSpan>[];
    var bold = false;
    void addText(String value) {
      // "**" switches bold on and off; the markers themselves are not shown.
      final pieces = value.split('**');
      for (var i = 0; i < pieces.length; i++) {
        if (i > 0) bold = !bold;
        if (pieces[i].isEmpty) continue;
        spans.add(TextSpan(text: pieces[i], style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null));
      }
    }

    for (final part in splitCode(source)) {
      if (part.code) {
        spans.add(TextSpan(
          text: part.text,
          style: TextStyle(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) * 0.92, backgroundColor: context.tt.cardRaised),
        ));
        continue;
      }
      final segments = splitMath(wrapBareLatex(_headingsAsBold(part.text)));
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        if (!segment.isMath) {
          addText(segment.text);
        } else if (segment.display) {
          // A display formula sits on its own line.
          final before = i > 0 ? segments[i - 1].text : '';
          final after = i + 1 < segments.length ? segments[i + 1].text : '';
          if (spans.isNotEmpty && !before.endsWith('\n')) spans.add(const TextSpan(text: '\n'));
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _formula(segment.text, base, display: true)));
          if (i + 1 < segments.length && !after.startsWith('\n')) spans.add(const TextSpan(text: '\n'));
        } else {
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _formula(segment.text, base, display: false)));
        }
      }
    }
    return Text.rich(
      TextSpan(children: spans, style: base),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

String _css(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The written paper's HTML ready to show: escaped backslashes made single,
/// LaTeX without $…$ found (only in the text between tags), ChatGPT's
/// **bold** and # headings shown bold, and every formula tagged for typesetting.
/// Code and preformatted blocks are left exactly as they are.
String prepareHtmlForDisplay(String html) {
  final held = <String>[];
  String hold(String block) {
    held.add(block);
    return '\u0000${held.length - 1}\u0000';
  }

  var out = normalizeEscapes(html).replaceAllMapped(
    RegExp(r'<(pre|code)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    (m) => hold(m[0]!),
  );
  // Delimited formulas first: a display formula may span paragraphs (<p>$$</p><p>…</p><p>$$</p>).
  out = tagMathInHtml(out);
  // Then LaTeX pasted without $…$: only the text between tags is looked at.
  out = out.replaceAllMapped(RegExp(r'(^|>)([^<]+)(?=<|$)'), (m) => '${m[1]}${wrapBareLatex(m[2]!)}');
  out = tagMathInHtml(out);
  out = out
      .replaceAllMapped(RegExp(r'<p>\s*#{1,6}\s+([\s\S]*?)</p>', caseSensitive: false), (m) => '<p><strong>${m[1]}</strong></p>')
      .replaceAllMapped(RegExp(r'\*\*(?=\S)([^<>\n]*?\S)\*\*'), (m) => '<strong>${m[1]}</strong>');
  return out.replaceAllMapped(RegExp('\u0000(\\d+)\u0000'), (m) => held[int.parse(m[1]!)]);
}

String _decodeEntities(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

/// Marks every formula in rich-text HTML with a custom tag the HTML widget can turn into typeset maths.
String tagMathInHtml(String html) {
  return html.replaceAllMapped(_mathPattern, (match) {
    final inline = match[4];
    if (inline != null && _moneyOnly.hasMatch(inline)) return match[0]!;
    final display = match[1] != null || match[2] != null;
    final raw = (match[1] ?? match[2] ?? match[3] ?? inline!)
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'</?[a-zA-Z][^>]*>'), '');
    final encoded = base64Url.encode(utf8.encode(_decodeEntities(raw).trim()));
    return '<tex-math data-tex="$encoded" data-display="${display ? 1 : 0}"></tex-math>';
  });
}

/// The written paper, a model solution — rich text from the website's editor, with maths typeset
/// and pictures loaded from the server.
class HtmlMath extends StatelessWidget {
  const HtmlMath(this.html, {super.key, required this.baseUrl, this.style});

  final String html;

  /// The server origin, so "/media/…" pictures resolve.
  final String baseUrl;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final tt = context.tt;
    return HtmlWidget(
      prepareHtmlForDisplay(html),
      baseUrl: Uri.tryParse(baseUrl),
      textStyle: base,
      customWidgetBuilder: (element) {
        if (element.localName != 'tex-math') return null;
        String tex;
        try {
          tex = utf8.decode(base64Url.decode(element.attributes['data-tex'] ?? ''));
        } catch (_) {
          return null;
        }
        final display = element.attributes['data-display'] == '1';
        final child = _formula(tex, base, display: display);
        if (display) return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Center(child: child));
        return InlineCustomWidget(alignment: PlaceholderAlignment.middle, child: child);
      },
      customStylesBuilder: (element) {
        switch (element.localName) {
          case 'th':
          case 'td':
            return {'border': '1px solid ${_css(tt.border)}', 'padding': '6px'};
          case 'a':
            return {'color': _css(tt.primary)};
          case 'code':
          case 'pre':
            return {'background-color': _css(tt.cardRaised)};
        }
        return null;
      },
    );
  }
}

String _escapeHtml(String text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Turns what a tutor typed on the phone into the paragraph HTML the server stores.
/// Blank lines start a new paragraph; "[picture: /media/…]" lines become images.
String plainTextToHtml(String text) {
  final blocks = text.replaceAll('\r\n', '\n').trim().split(RegExp(r'\n\s*\n'));
  final out = StringBuffer();
  for (final block in blocks) {
    if (block.trim().isEmpty) continue;
    final picture = RegExp(r'^\[picture:\s*(\S+)\s*\]$').firstMatch(block.trim());
    if (picture != null) {
      out.write('<p><img src="${_escapeHtml(picture[1]!)}" alt="picture"></p>');
    } else {
      out.write('<p>${_escapeHtml(block.trim()).replaceAll('\n', '<br>')}</p>');
    }
  }
  return out.toString();
}

class EditableHtml {
  EditableHtml(this.text, {required this.lossy});
  final String text;

  /// True when the HTML has formatting (tables, lists, headings) that plain text cannot keep.
  final bool lossy;
}

/// The reverse of [plainTextToHtml], for editing an existing paper on the phone.
EditableHtml htmlToPlainText(String html) {
  if (html.trim().isEmpty || html.trim() == '<p></p>') return EditableHtml('', lossy: false);
  final lossy = RegExp(r'<(table|ul|ol|h[1-6]|blockquote|pre|strong|b|em|i|u|s|mark|sub|sup|a)\b', caseSensitive: false).hasMatch(html);
  var text = html
      .replaceAllMapped(RegExp(r'''<img[^>]*src=["']([^"']+)["'][^>]*>''', caseSensitive: false), (m) => '\n\n[picture: ${m[1]}]\n\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr|blockquote|pre)>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</(td|th)>', caseSensitive: false), '  ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  text = _decodeEntities(text).replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  return EditableHtml(text, lossy: lossy);
}
