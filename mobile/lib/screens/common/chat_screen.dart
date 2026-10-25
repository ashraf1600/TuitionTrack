import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/chat.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../widgets/kit.dart' show longDate;
import '../../widgets/math_text.dart';
import '../../widgets/science_paste.dart';
import '../../widgets/science_toolbar.dart';
import '../../widgets/theme.dart';
import '../../widgets/ui.dart';

/// One conversation with a tutor or a student.
///
/// Messages appear the moment they are sent (a clock until the server has
/// them, then ✓, and ✓✓ once the other person has opened the chat). A message
/// that could not be sent stays with "Tap to retry". New messages are fetched
/// every few seconds while the chat is open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.conversationId, this.person, this.unreadOnOpen = 0});
  final String conversationId;

  /// Shown in the title straight away; refreshed from the server.
  final ChatPerson? person;

  /// Messages that were unread when the chat was opened: a "new messages" line goes above them.
  final int unreadOnOpen;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 3);

  late final ApiClient _client = context.read<Session>().api;
  late final ChatApi _api = ChatApi(_client);
  final _messages = <ChatMessage>[];
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  ChatPerson? _person;
  bool _loading = true;
  String? _error;
  bool _hasMore = false;
  bool _loadingOlder = false;
  bool _canSend = true;
  bool _science = false;
  bool _polling = false;
  bool _resumed = true;
  DateTime? _otherReadAt;
  Timer? _poll;

  /// The message being answered (shown above the text box until sent).
  ChatMessage? _replyTo;

  /// The first message that was new when the chat opened.
  int? _newFromId;

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _text.addListener(() => setState(() {}));
    _load();
    _poll = Timer.periodic(_pollEvery, (_) => _fetchNew());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) _fetchNew();
  }

  int get _lastId => _messages.fold(0, (best, m) => m.id > best ? m.id : best);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fresh details of the other person ("Active 5 min ago", phone for tutors).
      try {
        final conv = await _api.conversation(widget.conversationId);
        _person = conv.other;
        _canSend = conv.canSend;
      } on ApiException {
        if (_person == null) rethrow;
      }
      final page = await _api.messages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        if (widget.unreadOnOpen > 0) {
          var seen = 0;
          for (final m in page.messages.reversed) {
            if (m.mine) continue;
            seen++;
            if (seen == widget.unreadOnOpen) {
              _newFromId = m.id;
              break;
            }
          }
        }
        _hasMore = page.hasMore;
        _canSend = page.canSend;
        _otherReadAt = page.otherReadAt;
        _loading = false;
      });
      _markRead();
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  /// New messages since the newest one here (and whether they were seen).
  Future<void> _fetchNew() async {
    if (_polling || _loading || !_resumed || !mounted || _error != null) return;
    _polling = true;
    try {
      final page = await _api.messages(widget.conversationId, after: _lastId);
      if (!mounted) return;
      final fromOther = _merge(page.messages);
      setState(() {
        _otherReadAt = page.otherReadAt ?? _otherReadAt;
        _canSend = page.canSend;
      });
      if (fromOther) {
        _markRead();
        HapticFeedback.selectionClick();
      }
    } on ApiException {
      // A missed poll is fine; the next one catches up.
    } finally {
      _polling = false;
    }
  }

  /// Adds messages from the server, replacing the local copy of one sent from
  /// here. Answers whether any came from the other person.
  bool _merge(List<ChatMessage> incoming) {
    var fromOther = false;
    for (final m in incoming) {
      if (_messages.any((x) => x.id == m.id && m.id != 0)) continue;
      final local = m.clientRef.isEmpty ? -1 : _messages.indexWhere((x) => x.id == 0 && x.clientRef == m.clientRef);
      if (local >= 0) {
        _messages[local] = m;
      } else {
        _messages.add(m);
        if (!m.mine) fromOther = true;
      }
    }
    _messages.sort((a, b) {
      // Not yet sent ones stay at the bottom, in the order written.
      if (a.id == 0 || b.id == 0) return a.createdAt.compareTo(b.createdAt);
      return a.id.compareTo(b.id);
    });
    return fromOther;
  }

  void _onScroll() {
    // The list is upside down: the top of the chat is the end of the scroll.
    if (_hasMore && !_loadingOlder && _scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadOlder();
  }

  Future<void> _loadOlder() async {
    final oldest = _messages.where((m) => m.id > 0).fold<int?>(null, (low, m) => low == null || m.id < low ? m.id : low);
    if (oldest == null) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await _api.messages(widget.conversationId, before: oldest);
      if (!mounted) return;
      setState(() {
        _messages.insertAll(0, page.messages.where((m) => !_messages.any((x) => x.id == m.id)));
        _hasMore = page.hasMore;
      });
    } on ApiException {
      // Scrolling up again tries again.
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _markRead() {
    unawaited(() async {
      try {
        await _api.markRead(widget.conversationId);
        await ChatUnread.instance.refresh(_client);
      } on ApiException {
        // Read marks are best effort.
      }
    }());
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  void _send() {
    final body = _text.text.trim();
    if (body.isEmpty || !_canSend) return;
    HapticFeedback.lightImpact();
    final message = ChatMessage(
      id: 0,
      body: body,
      mine: true,
      createdAt: DateTime.now(),
      clientRef: newClientRef(),
      state: SendState.sending,
      replyTo: _quoteOf(_replyTo),
    );
    setState(() {
      _messages.add(message);
      _replyTo = null;
    });
    _text.clear();
    _jumpToBottom();
    _deliver(message);
  }

  Future<void> _deliver(ChatMessage message) async {
    try {
      final saved = message.localImage != null
          ? await _api.sendPhoto(widget.conversationId,
              bytes: message.localImage!, filename: 'photo.jpg', body: message.body, clientRef: message.clientRef, replyTo: message.replyTo?.id)
          : await _api.send(widget.conversationId, body: message.body, clientRef: message.clientRef, replyTo: message.replyTo?.id);
      if (!mounted) return;
      setState(() => _merge([saved]));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => message.state = SendState.failed);
      if (error.status == 403) {
        setState(() => _canSend = false);
        showToast(context, error.message, error: true);
      }
    }
  }

  static ChatQuote? _quoteOf(ChatMessage? m) =>
      m == null || m.id == 0 ? null : ChatQuote(id: m.id, body: m.body, hasImage: m.hasImage, mine: m.mine);

  void _reply(ChatMessage message) {
    if (message.id == 0 || !_canSend) return;
    HapticFeedback.selectionClick();
    setState(() => _replyTo = message);
    _focus.requestFocus();
  }

  /// The + button: a photo (camera or gallery), or the science keys.
  Future<void> _more() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(tr('Take a photo')), onTap: () => Navigator.pop(sheet, 'camera')),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(tr('Choose from gallery')), onTap: () => Navigator.pop(sheet, 'gallery')),
            ListTile(
              leading: const Icon(Icons.functions_rounded),
              title: Text(_science ? tr('Hide science keys') : tr('Science keys')),
              subtitle: Text(tr('x², H₂O, fractions, Greek letters, units')),
              onTap: () => Navigator.pop(sheet, 'science'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'science') {
      setState(() => _science = !_science);
      if (_science) _focus.requestFocus();
      return;
    }
    await _pickPhoto(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    if (!await launchUrl(uri) && mounted) showToast(context, tr('Could not start a call.'), error: true);
  }

  void _retry(ChatMessage message) {
    HapticFeedback.lightImpact();
    setState(() => message.state = SendState.sending);
    _deliver(message);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    XFile? file;
    try {
      // Big enough to read a page of handwriting, small enough to send quickly.
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    } catch (_) {
      if (mounted) showToast(context, tr('Could not open the camera or gallery. Check the app permissions.'), error: true);
      return;
    }
    if (file == null || !mounted) return;
    final Uint8List bytes = await file.readAsBytes();
    final caption = _text.text.trim();
    _text.clear();
    final message = ChatMessage(
      id: 0,
      body: caption,
      mine: true,
      createdAt: DateTime.now(),
      clientRef: newClientRef(),
      state: SendState.sending,
      localImage: bytes,
      replyTo: _quoteOf(_replyTo),
    );
    setState(() {
      _messages.add(message);
      _replyTo = null;
    });
    _jumpToBottom();
    _deliver(message);
  }

  void _jumpToBottom() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  // ── Building ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final person = _person;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: person == null
            ? Text(tr('Messages'))
            : Row(
                children: [
                  PersonAvatar(name: person.name, photo: person.photo, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        Text(
                          activeLabel(person.lastSeen) ?? (person.isTutor ? tr('Your tutor') : tr('Student')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: activeLabel(person.lastSeen) == tr('Active now') ? tt.success : tt.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (person?.phone != null)
            IconButton(
              tooltip: tr('Call {name}', {'name': Raw(person!.name)}),
              icon: const Icon(Icons.call_outlined),
              onPressed: () => _call(person.phone!),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _body(context)),
          if (!_loading && _error == null) _canSend ? _composer(context) : _closed(context),
          if (_science && _canSend) const ScienceToolbar(),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              gap12,
              OutlinedButton(onPressed: _load, child: Text(tr('Try again'))),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return _EmptyChat(
        person: _person,
        onSuggestion: (text) {
          _text.text = text;
          _text.selection = TextSelection.collapsed(offset: text.length);
          _focus.requestFocus();
        },
      );
    }

    // Rows in reading order: a day label whenever the day changes, then messages.
    final rows = <Object>[];
    DateTime? day;
    for (final m in _messages) {
      final d = DateTime(m.createdAt.year, m.createdAt.month, m.createdAt.day);
      if (day != d) {
        rows.add(d);
        day = d;
      }
      rows.add(m);
    }
    final seenUpTo = _otherReadAt;
    final lastMine = _messages.lastWhere((m) => m.mine && m.id > 0, orElse: () => ChatMessage(id: -1, body: '', mine: true, createdAt: DateTime(0)));
    final lastIsMine = _messages.isNotEmpty && _messages.last.mine;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: rows.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == rows.length) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        final i = rows.length - 1 - index;
        final row = rows[i];
        if (row is DateTime) return _DayLabel(day: row);
        final m = row as ChatMessage;
        final before = i > 0 && rows[i - 1] is ChatMessage ? rows[i - 1] as ChatMessage : null;
        final after = i + 1 < rows.length && rows[i + 1] is ChatMessage ? rows[i + 1] as ChatMessage : null;
        bool joined(ChatMessage? other) =>
            other != null && other.mine == m.mine && other.createdAt.difference(m.createdAt).abs() < const Duration(minutes: 5);
        final seen = m.mine && m.id > 0 && seenUpTo != null && !m.createdAt.isAfter(seenUpTo);
        final bubble = _Bubble(
          message: m,
          joinedAbove: joined(before) && m.id != _newFromId,
          joinedBelow: joined(after),
          seen: seen,
          onRetry: () => _retry(m),
          onReply: _canSend ? () => _reply(m) : null,
          otherName: _person?.name ?? '',
        );
        final showSeen = lastIsMine && identical(m, lastMine) && seen;
        if (m.id != _newFromId && !showSeen) return bubble;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (m.id == _newFromId) const _NewMessagesLine(),
            bubble,
            if (showSeen)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 4),
                child: Text(tr('Seen'), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: _seenColor(context))),
              ),
          ],
        );
      },
    );
  }

  Widget _composer(BuildContext context) {
    final tt = context.tt;
    final canSend = _text.text.trim().isNotEmpty;
    final reply = _replyTo;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reply != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: tt.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border(left: BorderSide(color: _seenColor(context), width: 3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(reply.mine ? tr('Replying to yourself') : tr('Replying to {name}', {'name': Raw(_person?.name ?? '')}),
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _seenColor(context))),
                            Text(reply.body.isNotEmpty ? reply.body : tr('📷 Photo'),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Cancel reply'),
                        onPressed: () => setState(() => _replyTo = null),
                        icon: Icon(Icons.close_rounded, size: 20, color: tt.textTertiary),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton.filledTonal(
                    tooltip: tr('Photo or science keys'),
                    onPressed: _more,
                    style: IconButton.styleFrom(minimumSize: const Size(44, 44), backgroundColor: tt.card, foregroundColor: _science ? tt.primary : tt.onPrimaryContainer),
                    icon: Icon(_science ? Icons.functions_rounded : Icons.add_rounded, size: 22),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(color: tt.card, borderRadius: BorderRadius.circular(22)),
                      alignment: Alignment.centerLeft,
                      child: TextField(
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        contextMenuBuilder: sciencePasteMenu,
                        style: TextStyle(fontSize: 15, color: tt.textPrimary),
                        decoration: InputDecoration(
                          hintText: tr('Message'),
                          filled: false,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedScale(
                    scale: canSend ? 1 : 0.88,
                    duration: const Duration(milliseconds: 150),
                    child: IconButton.filled(
                      tooltip: tr('Send'),
                      onPressed: canSend ? _send : null,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        backgroundColor: tt.primary,
                        foregroundColor: tt.onPrimary,
                        disabledBackgroundColor: tt.cardRaised,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _closed(BuildContext context) {
    final tt = context.tt;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tt.cardRaised, borderRadius: BorderRadius.circular(14)),
        child: Text(
          tr('You are no longer connected, so new messages cannot be sent. Old messages stay here.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: tt.textSecondary),
        ),
      ),
    );
  }
}

/// "Today", "Yesterday" or "Monday, 21 October", centred between messages.
class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? tr('Today')
        : day == today.subtract(const Duration(days: 1))
            ? tr('Yesterday')
            : longDate(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: tt.cardRaised, borderRadius: BorderRadius.circular(12)),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tt.textSecondary)),
        ),
      ),
    );
  }
}

/// Teal for "seen" ticks and reply quotes; readable on both themes.
Color _seenColor(BuildContext context) => context.tt.isDark ? const Color(0xFF5FD3C6) : const Color(0xFF1F7A72);

/// My bubbles: a deep blue in the dark theme (calmer than the bright primary), a pale blue in the light one.
Color _mineFill(BuildContext context) => context.tt.isDark ? const Color(0xFF2B4A6B) : context.tt.primaryContainer;

/// "──── New messages ────" above the first message that was unread.
class _NewMessagesLine extends StatelessWidget {
  const _NewMessagesLine();

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: tt.primary.withValues(alpha: 0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(tr('New messages'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: tt.primary)),
          ),
          Expanded(child: Divider(color: tt.primary.withValues(alpha: 0.4))),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.joinedAbove, required this.joinedBelow, required this.seen, required this.onRetry, this.onReply, this.otherName = ''});
  final ChatMessage message;

  /// Shown on quotes of the other person's messages.
  final String otherName;
  final bool joinedAbove;
  final bool joinedBelow;
  final bool seen;
  final VoidCallback onRetry;
  final VoidCallback? onReply;

  void _actions(BuildContext context) {
    if (message.id == 0) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(tr('Reply')),
                onTap: () {
                  Navigator.pop(sheet);
                  onReply!();
                },
              ),
            if (message.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(tr('Copy text')),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (sheet.mounted) Navigator.pop(sheet);
                  if (context.mounted) showToast(context, tr('Copied.'));
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final mine = message.mine;
    final failed = message.state == SendState.failed;
    final ink = tt.textPrimary;
    final quiet = mine ? tt.textSecondary : tt.textTertiary;
    const big = Radius.circular(18);
    const small = Radius.circular(6);
    final radius = BorderRadius.only(
      topLeft: !mine && joinedAbove ? small : big,
      bottomLeft: !mine && joinedBelow ? small : big,
      topRight: mine && joinedAbove ? small : big,
      bottomRight: mine && joinedBelow ? small : big,
    );
    final time = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fmtTime(message.createdAt), style: TextStyle(fontSize: 11, color: quiet, fontFeatures: tabular)),
        if (mine) ...[
          const SizedBox(width: 3),
          Icon(
            switch (message.state) {
              SendState.sending => Icons.schedule_rounded,
              SendState.failed => Icons.error_outline_rounded,
              SendState.sent => seen ? Icons.done_all_rounded : Icons.done_rounded,
            },
            size: 15,
            color: failed ? tt.danger : (seen ? _seenColor(context) : quiet),
          ),
        ],
      ],
    );
    final quote = message.replyTo;
    final hasText = message.body.isNotEmpty;
    final bubble = Container(
      decoration: BoxDecoration(
        color: failed ? tt.danger.withValues(alpha: 0.25) : (mine ? _mineFill(context) : tt.card),
        borderRadius: radius,
      ),
      padding: message.hasImage ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(12, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null)
            Container(
              margin: EdgeInsets.only(bottom: 6, left: message.hasImage ? 4 : 0, right: message.hasImage ? 4 : 0, top: message.hasImage ? 4 : 0),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: tt.isDark ? 0.22 : 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: _seenColor(context), width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quote.mine ? tr('You') : otherName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _seenColor(context))),
                  Text(quote.body.isNotEmpty ? quote.body : tr('📷 Photo'),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: tt.textSecondary)),
                ],
              ),
            ),
          if (message.hasImage) _Photo(message: message, radius: radius),
          // The time sits at the end of the last line when it fits, else on its own line.
          Padding(
            padding: message.hasImage ? const EdgeInsets.fromLTRB(8, 6, 6, 2) : EdgeInsets.zero,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 10,
              runSpacing: 2,
              children: [
                if (hasText) MathText(message.body, style: TextStyle(fontSize: 15, height: 1.35, color: ink)),
                Padding(padding: const EdgeInsets.only(bottom: 1), child: time),
              ],
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.only(top: joinedAbove ? 2 : 8),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
            child: GestureDetector(
              onLongPress: () => _actions(context),
              onTap: failed ? onRetry : null,
              // Swipe a message to the right to reply, as in other chat apps.
              onHorizontalDragEnd: onReply == null || message.id == 0
                  ? null
                  : (details) {
                      if ((details.primaryVelocity ?? 0) > 300) onReply!();
                    },
              child: bubble,
            ),
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(tr('Not sent · Tap to retry'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tt.danger)),
            ),
        ],
      ),
    );
  }
}

/// A photo in a message; tap to see it full screen.
class _Photo extends StatelessWidget {
  const _Photo({required this.message, required this.radius});
  final ChatMessage message;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final url = message.image == null ? '' : context.read<Session>().api.mediaUrl(message.image);
    final Widget picture = message.localImage != null
        ? Image.memory(message.localImage!, fit: BoxFit.cover)
        : Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const SizedBox(height: 180, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            errorBuilder: (_, _, _) => SizedBox(height: 120, child: Center(child: Text(tr('Picture could not be loaded')))),
          );
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
            body: InteractiveViewer(
              maxScale: 6,
              child: Center(child: message.localImage != null ? Image.memory(message.localImage!) : Image.network(url)),
            ),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 280, minWidth: 180), child: picture),
      ),
    );
  }
}

/// A new chat: who it is with and a few ways to start.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.person, required this.onSuggestion});
  final ChatPerson? person;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final name = person?.name ?? '';
    final toTutor = person?.isTutor ?? false;
    final suggestions = toTutor
        ? [tr('Assalamu alaikum, Sir'), tr('I have a question about the homework.'), tr("I can't come to class today.")]
        : [tr('Assalamu alaikum'), tr("Please finish today's homework."), tr('Class time has changed today.')];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Center(child: PersonAvatar(name: name, photo: person?.photo, radius: 40)),
        gap16,
        Text(
          name.isEmpty ? tr('Start the conversation') : tr('Say hello to {name}', {'name': Raw(name)}),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: tt.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          toTutor
              ? tr('Ask about classes, homework or anything you did not understand. You can send photos too.')
              : tr('Send reminders, answer questions or share a photo of a problem.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: tt.textSecondary),
        ),
        gap24,
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions)
              ActionChip(
                label: Text(s),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onSuggestion(s);
                },
              ),
          ],
        ),
      ],
    );
  }
}
