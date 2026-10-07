import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/json.dart';
import '../../core/repo.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

const _days = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

int _minutes(String time) {
  final parts = time.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

String _hhmm(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

/// Create a tuition group, or edit one. Pops with `true` when saved.
class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key, this.tuition});
  final Json? tuition;

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.tuition?.str('title') ?? '');
  late final _subject = TextEditingController(text: widget.tuition?.str('subject') ?? '');
  late final _description = TextEditingController(text: widget.tuition?.str('description') ?? '');
  late final _fee = TextEditingController(text: widget.tuition == null ? '' : trimNumber(widget.tuition!.number('total_fee')));
  late final _length = TextEditingController(text: '${widget.tuition?.integer('cycle_length') ?? 12}');
  late final List<Json> _routine = [
    for (final slot in widget.tuition?.maps('routine') ?? const <Json>[])
      {
        'day': slot.str('day'),
        'start_time': slot.str('start_time', slot.str('time', '18:00')),
        'end_time': slot.str('end_time', '19:30'),
      },
  ];
  String? _error;

  bool get _editing => widget.tuition != null;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _description.dispose();
    _fee.dispose();
    _length.dispose();
    super.dispose();
  }

  Future<void> _addSlot() async {
    var day = _days.firstWhere((d) => !_routine.any((s) => s['day'] == d), orElse: () => 'Sunday');
    var start = const TimeOfDay(hour: 18, minute: 0);
    var end = const TimeOfDay(hour: 19, minute: 30);
    final slot = await showModalBottomSheet<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Add a class day', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                gap12,
                DropdownButtonFormField<String>(
                  initialValue: day,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: [for (final d in _days) DropdownMenuItem(value: d, child: Text(d))],
                  onChanged: (value) => setSheet(() => day = value ?? day),
                ),
                gap12,
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: start, helpText: 'Class starts');
                          if (picked != null) setSheet(() => start = picked);
                        },
                        child: Text('Starts ${to12h(_hhmm(start))}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: end, helpText: 'Class ends');
                          if (picked != null) setSheet(() => end = picked);
                        },
                        child: Text('Ends ${to12h(_hhmm(end))}'),
                      ),
                    ),
                  ],
                ),
                gap16,
                FilledButton(
                  onPressed: () => Navigator.pop(context, {'day': day, 'start_time': _hhmm(start), 'end_time': _hhmm(end)}),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (slot == null || !mounted) return;
    final s = _minutes(slot.str('start_time'));
    final e = _minutes(slot.str('end_time'));
    if (e <= s) {
      showToast(context, 'The class must end after it starts.', error: true);
      return;
    }
    // Two classes of the same group cannot overlap on a day.
    final clash = _routine.any((other) =>
        other['day'] == slot['day'] && s < _minutes(other.str('end_time', '23:59')) && _minutes(other.str('start_time')) < e);
    if (clash) {
      showToast(context, 'That time overlaps another class on ${slot['day']}.', error: true);
      return;
    }
    setState(() {
      _routine.add(slot);
      _routine.sort((a, b) {
        final byDay = _days.indexOf(a.str('day')).compareTo(_days.indexOf(b.str('day')));
        return byDay != 0 ? byDay : a.str('start_time').compareTo(b.str('start_time'));
      });
    });
  }

  Future<void> _save() async {
    if (!checkForm(context, _form)) return;
    final repo = context.read<Repo>();
    final form = <String, dynamic>{
      'title': _title.text.trim(),
      'subject': _subject.text.trim(),
      'description': _description.text.trim(),
      'total_fee': num.tryParse(_fee.text.trim()) ?? 0,
      'cycle_length': int.tryParse(_length.text.trim()) ?? 12,
      'routine': _routine,
    };
    setState(() => _error = null);
    try {
      _editing ? await repo.updateTuition(widget.tuition!.str('id'), form) : await repo.createTuition(form);
      if (!mounted) return;
      showToast(context, _editing ? 'Group updated.' : 'Group created.');
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = num.tryParse(_fee.text.trim()) ?? 0;
    final length = int.tryParse(_length.text.trim()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit group' : 'New tuition group')),
      body: Form(
        key: _form,
        child: PageBody(
          children: [
            if (_error != null) ...[Banner2(_error!, color: AppColors.danger, icon: Icons.error_outline), gap12],
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Class 10 Math Batch'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Give the group a name' : null,
            ),
            gap12,
            TextFormField(controller: _subject, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Subject (optional)')),
            gap12,
            TextFormField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description (optional)')),
            gap12,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Fee per cycle (৳)', helperText: 'For the whole group'),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final value = num.tryParse((v ?? '').trim());
                      if (value == null) return 'Enter an amount';
                      return value < 0 ? 'Cannot be negative' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _length,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Classes per cycle'),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final value = int.tryParse((v ?? '').trim());
                      if (value == null || value < 1) return 'At least 1';
                      return value > 500 ? 'At most 500' : null;
                    },
                  ),
                ),
              ],
            ),
            if (fee > 0 && length > 0) ...[
              gap8,
              Text(
                'You earn ${taka(fee / length)} for each class you mark as done.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
            SectionTitle(
              'Weekly routine',
              subtitle: 'Used to remind you to record each class.',
              trailing: TextButton.icon(onPressed: _addSlot, icon: const Icon(Icons.add, size: 18), label: const Text('Add day')),
            ),
            if (_routine.isEmpty)
              const Text('No class days added yet.', style: TextStyle(color: AppColors.muted))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _routine.length; i++) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.schedule),
                        title: Text(_routine[i].str('day')),
                        subtitle: Text('${to12h(_routine[i].str('start_time'))} – ${to12h(_routine[i].str('end_time'))}'),
                        trailing: IconButton(
                          tooltip: 'Remove ${_routine[i].str('day')}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _routine.removeAt(i)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            gap24,
            BusyButton(onPressed: _save, label: _editing ? 'Save changes' : 'Create group', icon: Icons.check),
          ],
        ),
      ),
    );
  }
}
