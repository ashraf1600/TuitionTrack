import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/chat.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../widgets/kit.dart' show shortWeekday;
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';
import 'broadcast_screen.dart';
import 'chat_screen.dart';

/// Opens the chat with [userId] (a tutor or student), making it if it is new.
Future<void> openChatWith(BuildContext context, String userId) async {
  final api = ChatApi(context.read<Session>().api);
  ChatSummary? chat;
  final ok = await attempt(context, () async {
    chat = await api.start(userId);
  });
  if (!ok || chat == null || !context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: chat!.id, person: chat!.other)),
  );
}

/// The chat button in the top bar, with how many messages wait unread.
class ChatButton extends StatefulWidget {
  const ChatButton({super.key});

  @override
  State<ChatButton> createState() => _ChatButtonState();
}

class _ChatButtonState extends State<ChatButton> with WidgetsBindingObserver {
  Timer? _timer;

  ApiClient get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ChatUnread.instance.refresh(_api);
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ChatUnread.instance.refresh(_api);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) ChatUnread.instance.refresh(_api);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ChatUnread.instance,
      builder: (context, unread, _) => IconButton(
        tooltip: unread == 0 ? tr('Messages') : tr('{n} unread messages', {'n': unread}),
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(localDigits(unread > 99 ? '99+' : '$unread')),
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        onPressed: () async {
          HapticFeedback.lightImpact();
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ChatsScreen()));
          if (context.mounted) ChatUnread.instance.refresh(_api);
        },
      ),
    );
  }
}

/// Every chat, newest first, and a way to start one with any of your tutors or students.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  late final ChatApi _api = ChatApi(context.read<Session>().api);
  List<ChatSummary>? _chats;
  List<ChatContact> _contacts = const [];
  String? _error;
  String _search = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final results = await Future.wait([_api.chats(), _api.contacts()]);
      if (!mounted) return;
      final chats = results[0] as ({List<ChatSummary> chats, int unread});
      ChatUnread.instance.value = chats.unread;
      setState(() {
        _chats = chats.chats;
        _contacts = results[1] as List<ChatContact>;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted && !quiet) setState(() => _error = error.message);
    }
  }

  Future<void> _open(ChatSummary chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: chat.id, person: chat.other, unreadOnOpen: chat.unread)),
    );
    await _load(quiet: true);
  }

  Future<void> _openContact(ChatContact contact) async {
    if (contact.conversationId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => ChatScreen(conversationId: contact.conversationId!, person: contact.person)),
      );
    } else {
      await openChatWith(context, contact.person.id);
    }
    await _load(quiet: true);
  }

  Future<void> _newChat() async {
    HapticFeedback.lightImpact();
    final picked = await showModalBottomSheet<ChatContact>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ContactPicker(contacts: _contacts),
    );
    if (picked != null && mounted) await _openContact(picked);
  }

  @override
  Widget build(BuildContext context) {
    final chats = _chats;
    final isTutor = context.read<Session>().isTutor;
    final shown = chats == null || _search.isEmpty
        ? chats
        : chats.where((c) => c.other.name.toLowerCase().contains(_search.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Messages'))),
      floatingActionButton: (chats?.isNotEmpty ?? false) && _contacts.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _newChat,
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('New message')),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: chats == null
            ? ListView(children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Text(_error!, textAlign: TextAlign.center),
                      gap12,
                      OutlinedButton(onPressed: _load, child: Text(tr('Try again'))),
                    ]),
                  )
                else
                  const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
              ])
            : chats.isEmpty
                ? _NoChats(contacts: _contacts, isTutor: isTutor, onOpen: _openContact)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      if (isTutor) _BroadcastEntry(onSent: () => _load(quiet: true)),
                      if (chats.length > 6)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: TextField(
                            onChanged: (v) => setState(() => _search = v.trim()),
                            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Search by name')),
                          ),
                        ),
                      for (final chat in shown!) _ChatRow(chat: chat, onTap: () => _open(chat)),
                    ],
                  ),
      ),
    );
  }
}

/// "10:32 AM" today, "Yesterday", "Mon" this week, then "21 Oct".
String chatTimeLabel(DateTime? at) {
  if (at == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return fmtTime(at);
  if (days == 1) return tr('Yesterday');
  if (days < 7) return shortWeekday(at);
  return fmtShortDate(at);
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.onTap});
  final ChatSummary chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final unread = chat.unread > 0;
    final last = chat.last;
    final preview = last == null
        ? ''
        : '${last.mine ? tr('You: ') : ''}${last.body.trim().isNotEmpty ? last.body.trim().split('\n').first : tr('📷 Photo')}';
    final seenColor = tt.isDark ? const Color(0xFF5FD3C6) : const Color(0xFF1F7A72);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            PersonAvatar(name: chat.other.name, photo: chat.other.photo, radius: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(chat.other.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w700 : FontWeight.w600, color: tt.textPrimary)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        chatTimeLabel(chat.lastAt),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                          color: unread ? tt.primary : tt.textTertiary,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (last != null && last.mine) ...[
                        Icon(chat.lastSeenByOther ? Icons.done_all_rounded : Icons.done_rounded,
                            size: 16, color: chat.lastSeenByOther ? seenColor : tt.textTertiary),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: unread ? tt.textPrimary : tt.textSecondary, fontWeight: unread ? FontWeight.w500 : FontWeight.w400),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: tt.primary, borderRadius: BorderRadius.circular(11)),
                          child: Text(
                            localDigits(chat.unread > 99 ? '99+' : '${chat.unread}'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.onPrimary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No chats yet: everyone you can message, one tap to start.
class _NoChats extends StatelessWidget {
  const _NoChats({required this.contacts, required this.isTutor, required this.onOpen});
  final List<ChatContact> contacts;
  final bool isTutor;
  final ValueChanged<ChatContact> onOpen;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 32),
      children: [
        Icon(Icons.forum_outlined, size: 44, color: tt.textTertiary),
        gap12,
        Text(tr('No messages yet'), textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tt.textPrimary)),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            contacts.isEmpty
                ? (isTutor ? tr('Once students join you, you can message them here.') : tr('Once a tutor accepts you, you can message them here.'))
                : (isTutor ? tr('Pick a student to start a chat.') : tr('Pick your tutor to start a chat.')),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: tt.textSecondary),
          ),
        ),
        if (contacts.isNotEmpty) ...[
          gap16,
          if (isTutor) _BroadcastEntry(onSent: () {}),
          for (final c in contacts) _ContactRow(contact: c, onTap: () => onOpen(c)),
        ],
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onTap});
  final ChatContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: PersonAvatar(name: contact.person.name, photo: contact.person.photo, radius: 22),
      title: Text(contact.person.name, style: TextStyle(fontWeight: FontWeight.w600, color: tt.textPrimary)),
      subtitle: Text(contact.person.isTutor ? tr('Your tutor') : tr('Student'), style: TextStyle(color: tt.textSecondary)),
      trailing: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: tt.primary),
    );
  }
}

class _ContactPicker extends StatefulWidget {
  const _ContactPicker({required this.contacts});
  final List<ChatContact> contacts;

  @override
  State<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends State<_ContactPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final shown = widget.contacts.where((c) => c.person.name.toLowerCase().contains(_search.toLowerCase())).toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('New message'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            if (widget.contacts.length > 8)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _search = v.trim()),
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: tr('Search by name')),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final c in shown) _ContactRow(contact: c, onTap: () => Navigator.pop(context, c))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Message a whole tuition": the tutor's way to tell every student at once.
class _BroadcastEntry extends StatelessWidget {
  const _BroadcastEntry({required this.onSent});
  final VoidCallback onSent;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: tt.primaryContainer.withValues(alpha: tt.isDark ? 0.6 : 1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final sent = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const BroadcastScreen()));
            if (sent == true) onSent();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: tt.isDark ? const Color(0xFF2B4A6B) : tt.card, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.campaign_outlined, color: tt.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Message a whole tuition'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: tt.textPrimary)),
                      const SizedBox(height: 2),
                      Text(tr('One message to every student; replies come back privately'),
                          style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: tt.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
