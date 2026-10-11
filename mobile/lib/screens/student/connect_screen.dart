import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'connect_by_code.dart';

/// Everything about joining a tutor, kept off the home screen: the invite
/// code, requests waiting for an answer, and finding a tutor by name.
class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to a tutor')),
      body: Loader<(List<Json>, List<Json>)>(
        load: () async {
          final results = await Future.wait([repo.connections(), repo.tuitions()]);
          return (results[0], results[1]);
        },
        builder: (context, data, reload) {
          final (connections, tuitions) = data;
          final pending = connections.where((c) => c.str('status') == 'PENDING').toList();
          return PageBody(
            children: [
              for (final c in pending) ...[
                PendingConnectionView(tutorName: c.str('tutor_display_name').isNotEmpty ? c.str('tutor_display_name') : c.str('tutor_name')),
                gap8,
              ],
              ConnectByCodeCard(onSent: reload),
              gap8,
              _TutorConnect(connections: connections, tuitions: tuitions, reload: reload),
            ],
          );
        },
      ),
    );
  }
}

class _TutorConnect extends StatelessWidget {
  const _TutorConnect({required this.connections, required this.tuitions, required this.reload});
  final List<Json> connections;
  final List<Json> tuitions;
  final Future<void> Function() reload;

  Future<void> _find(BuildContext context) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FindTutorSheet(existing: connections),
    );
    if (sent == true) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'My tutors',
          icon: Icons.handshake_outlined,
          trailing: TextButton.icon(onPressed: () => _find(context), icon: const Icon(Icons.search, size: 18), label: const Text('Find a tutor')),
        ),
        // A tutor who added this student straight into a group never received a request from them.
        for (final name in {
          for (final t in tuitions)
            if (!connections.any((c) => c.str('tutor_name') == t.str('tutor_name'))) t.str('tutor_name'),
        }) ...[
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(name),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Align(alignment: Alignment.centerLeft, child: Pill('Your tutor', color: AppColors.success)),
              ),
            ),
          ),
          gap8,
        ],
        if (connections.isEmpty && tuitions.isEmpty)
          const EmptyState(
            icon: Icons.person_search_outlined,
            title: 'No tutor yet',
            message: 'Find your tutor and send a request. They decide whether to accept.',
          )
        else if (connections.isNotEmpty)
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < connections.length; i++) ...[
                  if (i > 0) const Divider(),
                  Builder(builder: (context) {
                    final c = connections[i];
                    final status = c.str('status');
                    final (label, color) = switch (status) {
                      'ACCEPTED' => ('Connected', AppColors.success),
                      'REJECTED' => ('Declined', AppColors.danger),
                      _ => ('Waiting for the tutor', AppColors.warning),
                    };
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(c.str('tutor_name')),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Align(alignment: Alignment.centerLeft, child: Pill(label, color: color)),
                      ),
                      trailing: status == 'PENDING'
                          ? TextButton(
                              onPressed: () async {
                                final ok = await confirm(
                                  context,
                                  title: 'Withdraw this request?',
                                  message: 'Your request to ${c.str('tutor_name')} will be removed.',
                                  confirmLabel: 'Withdraw',
                                  danger: true,
                                );
                                if (!ok || !context.mounted) return;
                                if (await attempt(context, () => repo.withdrawConnection(c.str('id')), success: 'Request withdrawn.')) {
                                  await reload();
                                }
                              },
                              child: const Text('Withdraw'),
                            )
                          : status == 'REJECTED'
                              ? TextButton(
                                  onPressed: () async {
                                    if (await attempt(context, () => repo.sendConnection(c.str('tutor_id'), ''), success: 'Request sent again.')) {
                                      await reload();
                                    }
                                  },
                                  child: const Text('Ask again'),
                                )
                              : null,
                    );
                  }),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FindTutorSheet extends StatefulWidget {
  const _FindTutorSheet({required this.existing});
  final List<Json> existing;

  @override
  State<_FindTutorSheet> createState() => _FindTutorSheetState();
}

class _FindTutorSheetState extends State<_FindTutorSheet> {
  final _message = TextEditingController();
  List<Json>? _tutors;
  String _search = '';
  Json? _picked;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final search = _search;
    try {
      final tutors = await context.read<Repo>().tutors(search);
      if (mounted && search == _search) setState(() => _tutors = tutors);
    } on ApiException catch (error) {
      if (mounted) showToast(context, error.message, error: true);
    }
  }

  String? _statusWith(String tutorId) {
    for (final c in widget.existing) {
      if (c.str('tutor_id') == tutorId) return c.str('status');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repo>();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: _picked != null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Send a request to ${_picked!.str('name')}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  gap12,
                  TextField(
                    controller: _message,
                    maxLength: 500,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Message (optional)',
                      hintText: 'e.g. Class 10, I need help with algebra.',
                    ),
                  ),
                  gap12,
                  BusyButton(
                    label: 'Send request',
                    icon: Icons.send,
                    onPressed: () async {
                      final ok = await attempt(
                        context,
                        () => repo.sendConnection(_picked!.str('id'), _message.text.trim()),
                        success: 'Request sent. Your tutor will see it.',
                      );
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
                  ),
                  TextButton(onPressed: () => setState(() => _picked = null), child: const Text('Choose a different tutor')),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Find a tutor', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  gap12,
                  TextField(
                    decoration: const InputDecoration(labelText: 'Search by name, username or subject', prefixIcon: Icon(Icons.search)),
                    onChanged: (value) {
                      // Debounce: one request per pause, not per keystroke.
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), () {
                        if (!mounted) return;
                        _search = value.trim();
                        _load();
                      });
                    },
                  ),
                  gap12,
                  Expanded(
                    child: _tutors == null
                        ? const Center(child: CircularProgressIndicator())
                        : _tutors!.isEmpty
                            ? Center(child: Text('No tutors match that search.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                            : ListView.separated(
                                itemCount: _tutors!.length,
                                separatorBuilder: (_, _) => const Divider(),
                                itemBuilder: (context, index) {
                                  final tutor = _tutors![index];
                                  final status = _statusWith(tutor.str('id'));
                                  final blocked = status == 'PENDING' || status == 'ACCEPTED';
                                  final subjects = tutor.strings('subjects');
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    enabled: !blocked,
                                    leading: const CircleAvatar(child: Icon(Icons.person)),
                                    title: Text(tutor.str('name')),
                                    subtitle: Text([
                                      '@${tutor.str('username')}',
                                      if (subjects.isNotEmpty) subjects.join(', '),
                                      if (status == 'PENDING') 'request sent',
                                      if (status == 'ACCEPTED') 'already connected',
                                    ].join(' · ')),
                                    trailing: blocked ? null : const Icon(Icons.chevron_right),
                                    onTap: blocked ? null : () => setState(() => _picked = tutor),
                                  );
                                },
                              ),
                  ),
                ],
              ),
      ),
    );
  }
}

