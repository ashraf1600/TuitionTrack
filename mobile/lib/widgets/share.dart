import 'dart:io';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/json.dart';
import '../core/repo.dart';
import '../core/session.dart';
import 'ui.dart';

/// Where the app can be downloaded, as the server announces it (empty when unknown).
Future<String> _downloadLink(BuildContext context) async {
  try {
    final meta = await context.read<Repo>().meta();
    return (meta.obj('app') ?? {}).str('download_url');
  } catch (_) {
    return '';
  }
}

/// The share sheet (WhatsApp, Messenger, SMS…) with an invitation to join the tutor.
Future<void> shareInviteCode(BuildContext context, String code) async {
  final session = context.read<Session>();
  final link = await _downloadLink(context);
  final name = session.displayName;
  final text = [
    tr('Join my tuition on TuitionTrack.'),
    tr('Invite code: {code}', {'code': Raw(code)}),
    if (link.isNotEmpty) tr('Download the app: {link}', {'link': Raw(link)}),
    tr('Open the app, choose "I\'m a student", and enter the code. — {name}', {'name': name}),
  ].join('\n');
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: tr('Join my tuition on TuitionTrack')));
    // The first-run checklist ticks off "Share your invite code" from this.
    await session.settings.setString(inviteSharedKey, 'yes');
  } catch (_) {
    if (context.mounted) showToast(context, tr('Could not open sharing on this phone.'), error: true);
  }
}

/// Settings key set once the tutor has shared their invite code.
const inviteSharedKey = 'invite_shared';

/// Shares a payment receipt for a paid cycle: a picture plus the same words as text.
Future<void> shareReceipt(BuildContext context, {required Json tuition, required Json cycle}) async {
  final session = context.read<Session>();
  final paidAt = cycle.date('paid_at');
  final students = cycle.integer('student_count');
  final amount = cycle.numberOrNull('earned_revenue') ?? cycle.numberOrNull('total_fee');
  final rows = <(String, String)>[
    (tr('Tuition'), tuition.str('title')),
    (tr('Cycle'), tr('#{n} · {done}/{total} classes', {
      'n': cycle.integer('cycle_number'),
      'done': cycle.integer('completed_classes'),
      'total': cycle.integer('total_classes'),
    })),
    if (amount != null)
      (students > 1 ? tr('Amount (all {n} students)', {'n': students}) : tr('Amount'), taka(amount)),
    (tr('Paid on'), paidAt == null ? '—' : fmtDate(paidAt)),
    (tr('Received by'), session.displayName),
    if (cycle.str('payment_note').isNotEmpty) (tr('Note'), cycle.str('payment_note')),
  ];
  final text = [tr('Payment receipt — TuitionTrack'), for (final (label, value) in rows) '$label: $value'].join('\n');
  try {
    final png = await _receiptImage(tr('Payment receipt'), rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}receipt-${cycle.str('id')}.png');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(ShareParams(
      text: text,
      subject: tr('Payment receipt'),
      files: [XFile(file.path, mimeType: 'image/png')],
    ));
  } catch (_) {
    // A phone that cannot attach the picture still gets the text.
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: tr('Payment receipt')));
    } catch (_) {
      if (context.mounted) showToast(context, tr('Could not open sharing on this phone.'), error: true);
    }
  }
}

/// Draws a simple receipt card (white, readable when forwarded and printed).
Future<List<int>> _receiptImage(String title, List<(String, String)> rows) async {
  const width = 900.0;
  const pad = 56.0;
  const rowHeight = 72.0;
  final height = pad * 2 + 150 + rows.length * rowHeight + 60;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

  canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
  canvas.drawRect(const Rect.fromLTWH(0, 0, width, 14), Paint()..color = const Color(0xFF059669));

  void text(String value, double x, double y, {double size = 30, FontWeight weight = FontWeight.w400, Color color = const Color(0xFF0F172A), double maxWidth = width - pad * 2, TextAlign align = TextAlign.left}) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(fontSize: size, fontWeight: weight, color: color)),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final dx = align == TextAlign.right ? x + maxWidth - painter.width : x;
    painter.paint(canvas, Offset(dx, y));
  }

  text('TuitionTrack', pad, pad, size: 28, weight: FontWeight.w700, color: const Color(0xFF4F46E5));
  text(title, pad, pad + 44, size: 44, weight: FontWeight.w800);
  final paidPaint = Paint()..color = const Color(0xFFD1FAE5);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(width - pad - 170, pad + 44, 170, 56), const Radius.circular(28)), paidPaint);
  text(tr('PAID'), width - pad - 170, pad + 54, size: 28, weight: FontWeight.w800, color: const Color(0xFF047857), maxWidth: 170, align: TextAlign.center);

  var y = pad + 150;
  final line = Paint()
    ..color = const Color(0xFFE2E8F0)
    ..strokeWidth = 2;
  for (final (label, value) in rows) {
    canvas.drawLine(Offset(pad, y - 14), Offset(width - pad, y - 14), line);
    text(label, pad, y, size: 28, color: const Color(0xFF64748B), maxWidth: 330);
    text(value, pad + 340, y, size: 30, weight: FontWeight.w700, maxWidth: width - pad * 2 - 340, align: TextAlign.right);
    y += rowHeight;
  }
  text(tr('Sent from the TuitionTrack app'), pad, height - pad - 10, size: 22, color: const Color(0xFF94A3B8));

  final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}
