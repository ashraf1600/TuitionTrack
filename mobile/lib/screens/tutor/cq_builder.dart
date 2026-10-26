import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/json.dart';
import '../../widgets/math_text.dart';
import '../../widgets/media.dart';
import '../../widgets/science_paste.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// Board-style part letters: ক খ গ ঘ in Bangla, a b c d in English.
List<String> get cqPartLetters => isBangla ? const ['ক', 'খ', 'গ', 'ঘ', 'ঙ', 'চ', 'ছ', 'জ'] : const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// The usual board pattern: knowledge 1, understanding 2, application 3, higher skills 4.
const _defaultMarks = [1, 2, 3, 4];

final _random = Random.secure();

/// A random v4 UUID, so a creative question and its marking-scheme row share one id the server accepts.
String newUuid() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// A new creative question: empty stem and the four standard parts.
Json blankCq() => {
      'id': newUuid(),
      'stem': '',
      'image_url': '',
      'parts': [
        for (var i = 0; i < 4; i++) {'label': cqPartLetters[i], 'text': '', 'marks': _defaultMarks[i]},
      ],
    };

num cqMarks(Json q) => q.maps('parts').fold<num>(0, (sum, p) => sum + p.number('marks'));

num cqTotal(List<Json> cq) => cq.fold<num>(0, (sum, q) => sum + cqMarks(q));

/// One marking-scheme row per creative question (its id is the question's id), so the tutor marks each CQ out of its total.
List<Json> cqScheme(List<Json> cq) => [
      for (final (i, q) in cq.indexed) {'id': q.str('id'), 'label': 'CQ ${i + 1}', 'marks': cqMarks(q)},
    ];

/// The paper as plain text, turned into HTML for the website and older app versions.
String cqToPlainText(List<Json> cq) {
  final out = <String>[];
  for (final (i, q) in cq.indexed) {
    out.add('${i + 1}. ${q.str('stem').trim()}');
    if (q.str('image_url').isNotEmpty) out.add('[picture: ${q.str('image_url')}]');
    out.add([
      for (final p in q.maps('parts')) '${p.str('label')}. ${p.str('text').trim()} [${trimNumber(p.number('marks'))}]',
    ].join('\n'));
  }
  return out.join('\n\n');
}

/// What still stops the paper from being published, e.g. "CQ 2: part গ is empty".
List<String> cqProblems(List<Json> cq) {
  final out = <String>[];
  for (final (i, q) in cq.indexed) {
    final n = i + 1;
    if (q.str('stem').trim().isEmpty && q.str('image_url').isEmpty) out.add(tr('CQ {n}: write the stem or add a picture', {'n': n}));
    final parts = q.maps('parts');
    if (parts.isEmpty) out.add(tr('CQ {n}: add at least one part', {'n': n}));
    for (final p in parts) {
      if (p.str('text').trim().isEmpty) out.add(tr('CQ {n}: part {p} is empty', {'n': n, 'p': Raw(p.str('label'))}));
      if (p.number('marks') <= 0) out.add(tr('CQ {n}: part {p} needs marks', {'n': n, 'p': Raw(p.str('label'))}));
    }
  }
  return out;
}

class _Part {
  _Part(Json p)
      : label = p.str('label'),
        text = TextEditingController(text: p.str('text')),
        marks = TextEditingController(text: trimNumber(p.number('marks', 1)));
  String label;
  final TextEditingController text;
  final TextEditingController marks;

  Json toJson() => {'label': label, 'text': text.text, 'marks': num.tryParse(marks.text.trim()) ?? 0};

  void dispose() {
    text.dispose();
    marks.dispose();
  }
}

class _Cq {
  _Cq(Json q)
      : id = q.str('id').isEmpty ? newUuid() : q.str('id'),
        stem = TextEditingController(text: q.str('stem')),
        image = q.str('image_url'),
        parts = [for (final p in q.maps('parts')) _Part(p)];
  final String id;
  final TextEditingController stem;
  String image;
  final List<_Part> parts;

  Json toJson() => {'id': id, 'stem': stem.text, 'image_url': image, 'parts': [for (final p in parts) p.toJson()]};

  void dispose() {
    stem.dispose();
    for (final p in parts) {
      p.dispose();
    }
  }
}

/// Builds the creative (CQ) part of an exam the way a board paper looks: each
/// question is a stem (উদ্দীপক), an optional picture, and parts ক খ গ ঘ with
/// their marks. Starts with the standard 1 + 2 + 3 + 4; parts can be added or
/// removed. Reports every change through [onChanged].
class CqBuilder extends StatefulWidget {
  const CqBuilder({super.key, required this.initial, required this.onChanged});
  final List<Json> initial;
  final ValueChanged<List<Json>> onChanged;

  @override
  State<CqBuilder> createState() => _CqBuilderState();
}

class _CqBuilderState extends State<CqBuilder> {
  late final List<_Cq> _items = [for (final q in widget.initial) _Cq(q)];

  @override
  void dispose() {
    for (final q in _items) {
      q.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged([for (final q in _items) q.toJson()]);
  }

  void _add() {
    _items.add(_Cq(blankCq()));
    _changed();
  }

  Future<void> _remove(int index) async {
    final q = _items[index];
    final hasText = q.stem.text.trim().isNotEmpty || q.parts.any((p) => p.text.text.trim().isNotEmpty);
    if (hasText) {
      final ok = await confirm(context, title: tr('Remove CQ {n}?', {'n': index + 1}), message: tr('Its stem and parts are deleted.'), confirmLabel: tr('Remove'));
      if (!ok || !mounted) return;
    }
    _items.removeAt(index).dispose();
    _changed();
  }

  void _addPart(_Cq q) {
    final letters = cqPartLetters;
    if (q.parts.length >= letters.length) return;
    q.parts.add(_Part({'label': letters[q.parts.length], 'text': '', 'marks': 1}));
    _changed();
  }

  void _removePart(_Cq q, int index) {
    q.parts.removeAt(index).dispose();
    // Keep the letters in order: ক খ গ … after a part is removed.
    for (final (i, p) in q.parts.indexed) {
      p.label = cqPartLetters[i];
    }
    _changed();
  }

  Future<void> _addPicture(_Cq q) async {
    final urls = await pickAndUpload(context, multiple: false);
    if (urls.isEmpty || !mounted) return;
    q.image = urls.first;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, q) in _items.indexed) ...[
          _card(i, q, tt),
          gap12,
        ],
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: Text(_items.isEmpty ? tr('Add a creative question') : tr('Add another creative question')),
        ),
      ],
    );
  }

  Widget _card(int index, _Cq q, TtTokens tt) {
    final marks = q.parts.fold<num>(0, (sum, p) => sum + (num.tryParse(p.marks.text.trim()) ?? 0));
    return Material(
      color: tt.cardRaised,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(tr('CQ {n}', {'n': index + 1}), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary)),
                const SizedBox(width: 8),
                Pill(tr('{p0} marks', {'p0': trimNumber(marks)}), color: AppColors.success),
                const Spacer(),
                IconButton(
                  tooltip: tr('Add a picture'),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
                  onPressed: () => _addPicture(q),
                ),
                IconButton(
                  tooltip: tr('Remove CQ {n}', {'n': index + 1}),
                  icon: Icon(Icons.delete_outline, size: 20, color: tt.textTertiary),
                  onPressed: () => _remove(index),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextField(
                controller: q.stem,
                contextMenuBuilder: sciencePasteMenu,
                minLines: 2,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _changed(),
                decoration: InputDecoration(
                  labelText: tr('Stem (উদ্দীপক)'),
                  hintText: tr('The passage, data or situation the parts are about'),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (q.image.isNotEmpty) ...[
              gap8,
              Stack(
                children: [
                  Padding(padding: const EdgeInsets.only(right: 8), child: ServerImage(q.image, height: 140, label: tr('CQ {n} picture', {'n': index + 1}))),
                  Positioned(
                    top: 4,
                    right: 12,
                    child: IconButton.filledTonal(
                      tooltip: tr('Remove the picture'),
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        q.image = '';
                        _changed();
                      },
                    ),
                  ),
                ],
              ),
            ],
            gap8,
            for (final (p, part) in q.parts.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(top: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: tt.primaryContainer, shape: BoxShape.circle),
                      child: Text(part.label, style: TextStyle(fontWeight: FontWeight.w700, color: tt.onPrimaryContainer)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: part.text,
                        contextMenuBuilder: sciencePasteMenu,
                        minLines: 1,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(hintText: tr('Question {p}', {'p': Raw(part.label)}), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: TextField(
                        controller: part.marks,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => _changed(),
                        decoration: InputDecoration(labelText: tr('Marks'), isDense: true),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Remove part {p}', {'p': Raw(part.label)}),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close, size: 18, color: tt.textTertiary),
                      onPressed: q.parts.length <= 1 ? null : () => _removePart(q, p),
                    ),
                  ],
                ),
              ),
            if (q.parts.length < cqPartLetters.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addPart(q),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr('Add part')),
                ),
              ),
            if (_needsPreview(q)) ...[
              gap8,
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: tt.card, borderRadius: BorderRadius.circular(10)),
                  child: CqQuestionView(q.toJson(), number: index + 1),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _needsPreview(_Cq q) {
    final all = [q.stem.text, for (final p in q.parts) p.text.text].join(' ');
    return all.contains(r'$') || all.contains(r'\') || all.contains('^') || all.contains('_');
  }
}

/// One creative question as printed on the paper: number, stem, picture, then
/// each part with its marks on the right. Used by the student's paper and the
/// tutor's preview.
class CqQuestionView extends StatelessWidget {
  const CqQuestionView(this.question, {super.key, required this.number});
  final Json question;
  final int number;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final body = TextStyle(fontSize: 15, height: 1.55, color: tt.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 26,
              child: Text('${localDigits('$number')}.', style: body.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: question.str('stem').trim().isEmpty
                  ? const SizedBox.shrink()
                  : MathText(question.str('stem').trim(), style: body),
            ),
          ],
        ),
        if (question.str('image_url').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 8, 0, 0),
            child: ServerImage(question.str('image_url'), label: tr('CQ {n} picture', {'n': number})),
          ),
        const SizedBox(height: 6),
        for (final p in question.maps('parts'))
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 4, 0, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 26, child: Text('${p.str('label')}.', style: body.copyWith(fontWeight: FontWeight.w600))),
                Expanded(child: MathText(p.str('text').trim(), style: body)),
                const SizedBox(width: 10),
                Text(localDigits(trimNumber(p.number('marks'))), style: body.copyWith(fontWeight: FontWeight.w600, color: tt.textSecondary)),
              ],
            ),
          ),
      ],
    );
  }
}
