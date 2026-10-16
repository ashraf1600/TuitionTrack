import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'science_text.dart';

const _channel = MethodChannel('tuitiontrack/clipboard');

/// What is on the clipboard, as text the question editors understand.
///
/// Copied web pages, Word and Google Docs also carry HTML. When it has
/// something plain text would lose — typeset maths (with its LaTeX), MathML,
/// H₂O, x² — that HTML is turned into text with LaTeX and Unicode scripts.
/// Otherwise the plain text is used, tidied.
Future<String?> readClipboardForQuestions() async {
  String? html;
  String? text;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final clip = await _channel.invokeMapMethod<String, dynamic>('read');
      html = clip?['html'] as String?;
      text = clip?['text'] as String?;
    } catch (_) {
      // Older builds without the channel: fall back to Flutter's plain text.
    }
  }
  if (html != null && html.trim().isNotEmpty && hasRichScience(html)) {
    final converted = htmlToQuestionText(html);
    if (converted.trim().isNotEmpty) return converted;
  }
  text ??= (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  return text == null ? null : tidyPastedText(text);
}
