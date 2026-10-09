import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/connect.dart';
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
  bool _focused = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

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
      showToast(context, 'Enter the 4–8 character code from your tutor.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await attempt(
        context,
        () => context.read<Repo>().connectByCode(code),
        success: 'Request sent. Waiting for your tutor.',
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
          const Text('Connect with invite code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Ask your tutor for their invite code.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          gap12,
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (_focused ? AppColors.primary : AppColors.muted).withValues(alpha: 0.25),
                  blurRadius: _focused ? 18 : 8,
                ),
              ],
            ),
            child: TextField(
              controller: _code,
              focusNode: _focus,
              maxLength: 8,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]'))],
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'e.g. KX7Q2M',
                prefixIcon: Icon(Icons.key_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          gap12,
          SizedBox(
            height: 50,
            child: _busy
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)))
                : FilledButton.icon(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    label: const Text('Send Request'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
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
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pending Connection', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Waiting for $tutorName to accept.', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          const Pill('PENDING', color: AppColors.warning, icon: Icons.hourglass_empty),
        ],
      ),
    );
  }
}
