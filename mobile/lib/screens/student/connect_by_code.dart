import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
import '../../core/i18n.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// Phase 1: unassigned state — 6-char tutor_code with focus animation,
/// CircularProgressIndicator while sending, Pending UI after success.
class ConnectByCodeCard extends StatefulWidget {
  const ConnectByCodeCard({super.key, required this.onSent});
  final Future<void> Function() onSent;

  @override
  State<ConnectByCodeCard> createState() => _ConnectByCodeCardState();
}

class _ConnectByCodeCardState extends State<ConnectByCodeCard> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    HapticFeedback.lightImpact();
    final code = normalizeInviteCode(_code.text);
    if (code == null) {
      showToast(context, tr('Enter the 4–8 character code from your tutor.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await attempt(
        context,
        () => context.read<Repo>().connectByCode(code),
        success: tr('Request sent. Waiting for your tutor.'),
      );
      if (ok) {
        _code.clear();
        await widget.onSent();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Connect with invite code'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.tt.textPrimary)),
          const SizedBox(height: 4),
          Text(tr('Ask your tutor for their invite code.'), style: TextStyle(color: context.tt.textSecondary, fontSize: 14, height: 1.5)),
          gap16,
          FieldLabel(tr('Invite code')),
          TextField(
            controller: _code,
            focusNode: _focus,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
            style: TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 2.8, color: context.tt.textPrimary),
            decoration: InputDecoration(
              counterText: '',
              hintText: tr('e.g. KX7Q2M'),
              hintStyle: TextStyle(fontFamily: 'monospace', fontSize: 20, letterSpacing: 2.8, color: context.tt.textTertiary),
              prefixIcon: Icon(Icons.key_rounded, color: context.tt.textTertiary),
              fillColor: context.tt.isDark ? context.tt.background : context.tt.cardRaised,
            ),
            onSubmitted: (_) => _send(),
          ),
          gap16,
          SizedBox(
            height: 52,
            child: _busy
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                : FilledButton.icon(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text(tr('Send Request')),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shown after a successful POST while status == PENDING.
class PendingConnectionView extends StatelessWidget {
  const PendingConnectionView({super.key, required this.tutorName});
  final String tutorName;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Pending Connection'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(tr('Waiting for {p0} to accept.', {'p0': tutorName}), style: TextStyle(color: context.tt.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          Pill(tr('PENDING'), color: AppColors.warning, icon: Icons.hourglass_empty),
        ],
      ),
    );
  }
}
