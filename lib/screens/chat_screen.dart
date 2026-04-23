import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_config.dart';
import '../chat_themes.dart';
import '../mc_crypto.dart';
import '../reaction_aliases.dart';
import '../reaction_state.dart';
import '../wire_message.dart';

const int _kMaxTranscriptMessages = 2000;
const Duration _kReconnectMax = Duration(seconds: 30);

const String _pref24h = 'marchat_chat_twenty_four_hour';
const String _prefTheme = 'marchat_chat_theme_id';

String _xmlEscapeForToast(String s) {
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// Windows PowerShell `-EncodedCommand` expects UTF-16LE of the script bytes.
String _powershellEncodedCommand(String script) {
  final bytes = <int>[];
  for (var i = 0; i < script.length; i++) {
    final u = script.codeUnitAt(i);
    bytes.add(u & 0xFF);
    bytes.add(u >> 8);
  }
  return base64Encode(bytes);
}

/// Short text for status line / logs when the socket drops or connect fails.
String _wsDisconnectReason(Object error) {
  if (error is WebSocketChannelException) {
    final inner = error.inner;
    if (inner != null) return _wsDisconnectReason(inner);
    final m = error.message;
    if (m != null && m.trim().isNotEmpty) return m.trim();
  }
  if (error is SocketException) {
    return error.message;
  }
  return error.toString();
}

enum _NotifyMode { none, bell, desktop, both }

class ChatScreen extends StatefulWidget {
  final MarchatClientConfig config;
  final MarchatGlobalE2E? e2e;
  final bool isAdmin;
  final String adminKey;

  const ChatScreen({
    super.key,
    required this.config,
    this.e2e,
    this.isAdmin = false,
    this.adminKey = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _socketSub;

  /// When true, socket `onDone`/`onError` must not call [setState] (e.g. [dispose] closed the sink).
  bool _suppressDisconnectUi = false;
  bool _connected = false;
  Timer? _reconnectTimer;
  Duration _reconnectDelay = const Duration(seconds: 1);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _inputFocus;

  final List<ChatWireMessage> _messages = [];
  List<String> _users = [];
  final Map<String, WireFileMeta> _receivedFiles = {};

  /// Target [ChatWireMessage.messageId] -> emoji -> reactors (marchat TUI parity).
  final Map<int, Map<String, Set<String>>> _reactionsByTarget = {};

  String _banner = '';
  Timer? _bannerTimer;
  String _statusLine = 'Connecting…';
  bool _sending = false;

  bool _twentyFourHour = true;
  int _themeIndex = 3;
  bool _showChannelsPanel = true;
  bool _showUsersPanel = true;
  bool _showHelp = false;

  int _selectedUserIndex = -1;
  String _selectedUser = '';

  String _activeChannel = 'general';
  String? _dmRecipient;

  bool _showMsgMeta = false;

  late final String _helpBodyText;

  bool _bellEnabled = true;
  bool _bellMentionOnly = false;
  _NotifyMode _notifyMode = _NotifyMode.bell;
  bool _desktopEnabled = false;
  DateTime _lastBell = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDesktop = DateTime.fromMillisecondsSinceEpoch(0);

  bool _quietOn = false;
  int _quietStart = 22;
  int _quietEnd = 8;
  bool _focusOn = false;
  DateTime? _focusUntil;

  McChatTheme get t => kMcBuiltinChatThemes[_themeIndex];

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode(onKeyEvent: _onInputBarKey);
    _helpBodyText = _buildHelpBody();
    _twentyFourHour = widget.config.twentyFourHour;
    final tid = widget.config.chatThemeId.toLowerCase();
    final idx = kMcBuiltinChatThemes.indexWhere((e) => e.id == tid);
    _themeIndex = idx >= 0 ? idx : 3;
    _connect();
  }

  Future<void> _persistChatDisplayPrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_pref24h, _twentyFourHour);
    await p.setString(_prefTheme, widget.config.chatThemeId);
  }

  String _buildHelpBody() {
    final sb = StringBuffer()
      ..writeln(
        'Session: ${widget.e2e != null ? "E2E (global key)" : "Plain text"}',
      )
      ..writeln(
        'With E2E loaded, the header shows E2E on next to the socket dot when connected; a * after the time means the payload was encrypted on the wire (TUI msginfo style).',
      )
      ..writeln(
        'Shortcuts: Ctrl+H help · Ctrl+T theme · Enter send · Shift+Enter new line',
      )
      ..writeln()
      ..writeln(':sendfile [path]  :savefile <name|id:n>  :code')
      ..writeln(':theme <id>  :themes  :time  :msginfo  :clear  :export [file]')
      ..writeln(
        ':bell  :bell-mention  :notify-mode …  :notify-desktop  :notify-status',
      )
      ..writeln(':quiet h h  :quiet-off  :focus [dur]  :focus-off')
      ..writeln(':dm [user [msg]]  :join  :leave  :channels')
      ..writeln(':edit :delete :search :react :pin :pinned')
      ..writeln(':q quit');
    if (widget.isAdmin) {
      sb
        ..writeln()
        ..writeln('Admin: :kick :ban :unban :allow :forcedisconnect')
        ..writeln(':cleardb :backup :stats  plugin :list :store …');
    }
    return sb.toString();
  }

  @override
  void dispose() {
    _suppressDisconnectUi = true;
    _reconnectTimer?.cancel();
    _bannerTimer?.cancel();
    final sub = _socketSub;
    _socketSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    _ch?.sink.close();
    _ch = null;
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _toast(String msg, {Duration d = const Duration(seconds: 4)}) {
    _bannerTimer?.cancel();
    setState(() => _banner = msg);
    _bannerTimer = Timer(d, () {
      if (mounted) setState(() => _banner = '');
    });
  }

  /// Enter sends; Shift+Enter stays default (newline in multiline field).
  KeyEventResult _onInputBarKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    if (_input.text.trim().isEmpty) return KeyEventResult.handled;
    unawaited(_submitInput());
    return KeyEventResult.handled;
  }

  // ── Connection ───────────────────────────────────────────────────────────

  Future<void> _connect() async {
    WebSocketChannel? newChannel;
    try {
      if (mounted) {
        setState(() {
          _statusLine = 'Connecting…';
          _connected = false;
        });
      }

      Uri uri = Uri.parse(widget.config.serverURL.trim());
      final qp = Map<String, String>.from(uri.queryParameters);
      if (!qp.containsKey('username')) {
        qp['username'] = widget.config.username;
      }
      uri = uri.replace(queryParameters: qp);

      newChannel = WebSocketChannel.connect(uri);
      await newChannel.ready;

      await _socketSub?.cancel();
      _socketSub = newChannel.stream.listen(
        _onSocketData,
        onError: (Object e, StackTrace st) {
          debugPrint('web socket stream error: $e\n$st');
          _onDisconnect(_wsDisconnectReason(e));
        },
        onDone: () => _onDisconnect('closed'),
        cancelOnError: true,
      );

      _ch = newChannel;
      final hs = <String, dynamic>{
        'username': widget.config.username,
        'admin': widget.isAdmin,
        if (widget.isAdmin && widget.adminKey.isNotEmpty)
          'admin_key': widget.adminKey,
      };
      _ch!.sink.add(jsonEncode(hs));

      if (mounted) {
        setState(() {
          _reconnectDelay = const Duration(seconds: 1);
        });
      }
    } catch (e, st) {
      debugPrint('web socket connect error: $e\n$st');
      _ch = null;
      await _socketSub?.cancel();
      _socketSub = null;
      try {
        await newChannel?.sink.close();
      } catch (_) {}
      _onDisconnect(_wsDisconnectReason(e));
    }
  }

  void _onDisconnect(String reason) {
    final sub = _socketSub;
    _socketSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    _ch?.sink.close();
    _ch = null;
    if (_suppressDisconnectUi || !mounted) return;
    setState(() {
      _connected = false;
      _statusLine = 'Disconnected ($reason); retrying…';
    });
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _connect);
    final next = (_reconnectDelay.inMilliseconds * 2).clamp(
      1000,
      _kReconnectMax.inMilliseconds,
    );
    _reconnectDelay = Duration(milliseconds: next);
  }

  void _onSocketData(dynamic raw) async {
    try {
      final data = jsonDecode(raw as String);
      if (data is! Map<String, dynamic>) return;

      if (!_connected && mounted) {
        setState(() {
          _connected = true;
          _statusLine = widget.e2e != null ? 'Connected (E2E)' : 'Connected';
        });
      }

      if (data['sender'] != null && (data['sender'] as String).isNotEmpty) {
        await _handleChatEnvelope(ChatWireMessage.fromJson(data));
        return;
      }

      if (data['type'] != null && data['data'] != null) {
        _handleServerEnvelope(data['type'] as String, data['data']);
      }
    } catch (e, st) {
      debugPrint('wire parse error: $e\n$st');
    }
  }

  void _handleServerEnvelope(String type, Object? payload) {
    switch (type) {
      case 'userlist':
        if (payload is Map && payload['users'] is List) {
          setState(() {
            _users = (payload['users'] as List).map((e) => '$e').toList();
          });
        }
        break;
      case 'auth_failed':
        if (payload is Map && payload['reason'] != null) {
          _toast(
            '[ERROR] Auth: ${payload['reason']}',
            d: const Duration(seconds: 12),
          );
        }
        break;
      default:
        break;
    }
  }

  Future<void> _handleChatEnvelope(ChatWireMessage m) async {
    if (m.type == WireTypes.typing || m.type == WireTypes.readReceipt) {
      return;
    }

    if (m.type == WireTypes.reaction) {
      if (!mounted) return;
      setState(() {
        applyMarchatReactionUpdate(
          byTarget: _reactionsByTarget,
          sender: m.sender,
          reaction: m.reaction,
        );
        _sending = false;
      });
      return;
    }

    var msg = m;

    if (widget.e2e != null && msg.encrypted) {
      try {
        if (msg.type == WireTypes.file && msg.file != null) {
          final dec = await widget.e2e!.decryptRaw(msg.file!.data);
          msg = msg.copyWith(
            file: WireFileMeta(
              filename: msg.file!.filename,
              size: dec.length,
              data: dec,
            ),
          );
        } else if (msg.content.isNotEmpty) {
          final plain = await widget.e2e!.decryptIncomingTextPayload(
            msg.content,
          );
          msg = msg.copyWith(content: plain);
        }
      } catch (e) {
        msg = msg.copyWith(
          content: '[ENCRYPTED - DECRYPT FAILED]',
          type: WireTypes.text,
          encrypted: false,
          clearFile: true,
          clearReaction: true,
        );
      }
    }

    if (msg.type == WireTypes.edit && msg.messageId != 0) {
      final idx = _messages.indexWhere((x) => x.messageId == msg.messageId);
      if (!mounted) return;
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: msg.content,
            edited: true,
            encrypted: msg.encrypted,
          );
          _sending = false;
        });
      }
      return;
    }

    if (msg.type == WireTypes.delete && msg.messageId != 0) {
      final idx = _messages.indexWhere((x) => x.messageId == msg.messageId);
      if (!mounted) return;
      if (idx >= 0) {
        setState(() {
          _messages[idx] = _messages[idx].copyWith(
            content: '[deleted]',
            type: WireTypes.delete,
          );
          _sending = false;
        });
      }
      return;
    }

    if (msg.type == WireTypes.file && msg.file != null) {
      final k = msg.messageId != 0
          ? 'id:${msg.messageId}'
          : 'fn:${msg.file!.filename}';
      _receivedFiles[k] = msg.file!;
    }

    _maybeNotify(msg);

    if (!mounted) return;
    setState(() {
      _messages.add(msg);
      if (_messages.length > _kMaxTranscriptMessages) {
        final dropped = _messages.removeAt(0);
        if (dropped.messageId != 0) {
          _reactionsByTarget.remove(dropped.messageId);
        }
      }
      _sending = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Notifications (TUI-aligned) ─────────────────────────────────────────

  bool _inQuietHours() {
    if (!_quietOn) return false;
    final h = DateTime.now().hour;
    if (_quietStart > _quietEnd) {
      return h >= _quietStart || h < _quietEnd;
    }
    return h >= _quietStart && h < _quietEnd;
  }

  bool _inFocus() {
    if (!_focusOn || _focusUntil == null) return false;
    return DateTime.now().isBefore(_focusUntil!);
  }

  bool _isMention(ChatWireMessage m) {
    final me = widget.config.username;
    return m.content.toLowerCase().contains('@${me.toLowerCase()}');
  }

  void _maybeNotify(ChatWireMessage m) {
    if (m.sender == widget.config.username) return;
    if (_inQuietHours() || _inFocus()) return;

    final isDm =
        m.type == WireTypes.dm &&
        m.recipient.toLowerCase() == widget.config.username.toLowerCase();
    final mention = _isMention(m);

    bool wantBell = false;
    if (_notifyMode == _NotifyMode.none || !_bellEnabled) {
      wantBell = false;
    } else if (_notifyMode == _NotifyMode.desktop) {
      wantBell = false;
    } else {
      if (_bellMentionOnly) {
        wantBell = mention || isDm;
      } else {
        wantBell = true;
      }
    }

    if (wantBell) {
      final now = DateTime.now();
      if (now.difference(_lastBell) > const Duration(milliseconds: 500)) {
        _lastBell = now;
        SystemSound.play(SystemSoundType.alert);
      }
    }

    bool wantDesktop = false;
    if (_desktopEnabled &&
        (_notifyMode == _NotifyMode.desktop ||
            _notifyMode == _NotifyMode.both)) {
      if (isDm || mention) wantDesktop = true;
    }
    if (wantDesktop) {
      final now = DateTime.now();
      if (now.difference(_lastDesktop) > const Duration(seconds: 2)) {
        _lastDesktop = now;
        unawaited(_desktopNotify(m.sender, m.content));
      }
    }
  }

  Future<void> _desktopNotify(String title, String body) async {
    if (!Platform.isWindows) return;
    final shortBody = body.length > 100 ? '${body.substring(0, 97)}...' : body;
    final xmlStr =
        '<toast><visual><binding template="ToastText02">'
        '<text id="1">${_xmlEscapeForToast(title)}</text>'
        '<text id="2">${_xmlEscapeForToast(shortBody)}</text>'
        '</binding></visual></toast>';
    final xb64 = base64Encode(utf8.encode(xmlStr));
    final script =
        '''
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
\$xb64 = '$xb64'
\$xtxt = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(\$xb64))
\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
\$xml.LoadXml(\$xtxt)
\$toast = New-Object Windows.UI.Notifications.ToastNotification \$xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("marchat").Show(\$toast)
''';
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-EncodedCommand',
        _powershellEncodedCommand(script),
      ]);
    } catch (_) {}
  }

  // ── Send ────────────────────────────────────────────────────────────────

  Future<void> _sendJson(Map<String, dynamic> m) async {
    if (_ch == null) {
      _toast('[ERROR] Not connected');
      return;
    }
    try {
      _ch!.sink.add(jsonEncode(m));
    } catch (e, st) {
      debugPrint('web socket send error: $e\n$st');
      _onDisconnect(_wsDisconnectReason(e));
    }
  }

  Future<void> _sendWire(ChatWireMessage m) async {
    await _sendJson(m.toJson());
  }

  Duration? _parseFocusDuration(String? s) {
    if (s == null || s.isEmpty) return const Duration(minutes: 30);
    final h = RegExp(r'(\d+)h').firstMatch(s);
    final m = RegExp(r'(\d+)m').firstMatch(s);
    final hours = h != null ? int.parse(h.group(1)!) : 0;
    final mins = m != null
        ? int.parse(m.group(1)!)
        : (h == null ? int.tryParse(s) ?? 30 : 0);
    if (hours == 0 && mins == 0) return null;
    return Duration(hours: hours, minutes: mins);
  }

  /// Local + structured commands (mirrors marchat `client/main.go` routing).
  Future<bool> _handleTypedCommand(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return true;

    if (text == ':q') {
      if (context.mounted) Navigator.of(context).pop();
      return true;
    }

    if (text == ':clear') {
      setState(() {
        _messages.clear();
        _reactionsByTarget.clear();
      });
      _toast('[OK] Chat cleared');
      return true;
    }

    if (text == ':time') {
      setState(() => _twentyFourHour = !_twentyFourHour);
      widget.config.twentyFourHour = _twentyFourHour;
      unawaited(_persistChatDisplayPrefs());
      _toast('[OK] Time format: ${_twentyFourHour ? "24h" : "12h"}');
      return true;
    }

    if (text == ':msginfo') {
      setState(() => _showMsgMeta = !_showMsgMeta);
      _toast('[OK] Message metadata: $_showMsgMeta');
      return true;
    }

    if (text == ':bell') {
      setState(() => _bellEnabled = !_bellEnabled);
      _toast('[OK] Bell ${_bellEnabled ? "on" : "off"}');
      if (_bellEnabled) SystemSound.play(SystemSoundType.alert);
      return true;
    }

    if (text == ':bell-mention') {
      setState(() => _bellMentionOnly = !_bellMentionOnly);
      _toast('[OK] Bell mention-only: $_bellMentionOnly');
      return true;
    }

    if (text.startsWith(':notify-mode ')) {
      final mode = text.substring(':notify-mode '.length).trim().toLowerCase();
      switch (mode) {
        case 'none':
          setState(() => _notifyMode = _NotifyMode.none);
          break;
        case 'bell':
          setState(() => _notifyMode = _NotifyMode.bell);
          break;
        case 'desktop':
          setState(() => _notifyMode = _NotifyMode.desktop);
          break;
        case 'both':
          setState(() => _notifyMode = _NotifyMode.both);
          break;
        default:
          _toast('[INFO] :notify-mode <none|bell|desktop|both>');
          return true;
      }
      _toast('[OK] Notify mode → $mode');
      return true;
    }

    if (text == ':notify-desktop') {
      setState(() => _desktopEnabled = !_desktopEnabled);
      _toast('[OK] Desktop notifications: $_desktopEnabled');
      return true;
    }

    if (text == ':notify-status') {
      final mode = _notifyMode.name;
      final desk = Platform.isWindows ? 'powershell toast' : 'OS-dependent';
      _toast(
        '[OK] mode:$mode | bell:$_bellEnabled(mention-only:$_bellMentionOnly) | '
        'desktop:$_desktopEnabled ($desk) | quiet:$_quietOn | focus:$_focusOn',
        d: const Duration(seconds: 8),
      );
      return true;
    }

    if (text.startsWith(':quiet ')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final a = int.tryParse(parts[1]);
        final b = int.tryParse(parts[2]);
        if (a != null && b != null && a >= 0 && a <= 23 && b >= 0 && b <= 23) {
          setState(() {
            _quietOn = true;
            _quietStart = a;
            _quietEnd = b;
          });
          _toast(
            '[OK] Quiet hours ${a.toString().padLeft(2, '0')}:00-${b.toString().padLeft(2, '0')}:00',
          );
          return true;
        }
      }
      _toast('[INFO] :quiet <start_h> <end_h>');
      return true;
    }

    if (text == ':quiet-off') {
      setState(() => _quietOn = false);
      _toast('[OK] Quiet hours disabled');
      return true;
    }

    if (text == ':focus' || text.startsWith(':focus ')) {
      final parts = text.split(RegExp(r'\s+'));
      final dur = parts.length > 1
          ? _parseFocusDuration(parts[1])
          : const Duration(minutes: 30);
      if (dur == null) {
        _toast('[ERROR] Invalid duration (try 30m, 1h)');
        return true;
      }
      setState(() {
        _focusOn = true;
        _focusUntil = DateTime.now().add(dur);
      });
      _toast('[OK] Focus mode ${_fmtDur(dur)}');
      return true;
    }

    if (text == ':focus-off') {
      setState(() {
        _focusOn = false;
        _focusUntil = null;
      });
      _toast('[OK] Focus mode off');
      return true;
    }

    if (text == ':themes') {
      _toast('[OK] Themes: ${mcBuiltinThemeIdsJoined()}');
      return true;
    }

    if (text.startsWith(':theme ')) {
      final name = text.substring(7).trim().toLowerCase();
      final def = mcThemeById(name);
      if (def == null) {
        _toast('[ERROR] Unknown theme "$name", use :themes');
        return true;
      }
      setState(() {
        _themeIndex = kMcBuiltinChatThemes.indexWhere((e) => e.id == def.id);
        widget.config.chatThemeId = def.id;
      });
      unawaited(_persistChatDisplayPrefs());
      _toast('[OK] Theme → ${def.name}');
      return true;
    }

    if (text == ':code') {
      await _openCodeSnippetDialog();
      return true;
    }

    if (text == ':sendfile' || text.startsWith(':sendfile ')) {
      final path = text.startsWith(':sendfile ')
          ? text.substring(':sendfile '.length).trim()
          : '';
      await _sendFile(path.isEmpty ? null : path);
      return true;
    }

    if (text.startsWith(':savefile ')) {
      await _saveFile(text.substring(':savefile '.length).trim());
      return true;
    }

    if (text == ':channels') {
      await _sendWire(
        ChatWireMessage(
          sender: widget.config.username,
          content: '',
          createdAt: DateTime.now(),
          type: WireTypes.listChannels,
        ),
      );
      return true;
    }

    if (text == ':leave') {
      setState(() => _activeChannel = 'general');
      await _sendWire(
        ChatWireMessage(
          sender: widget.config.username,
          content: '',
          createdAt: DateTime.now(),
          type: WireTypes.leaveChannel,
        ),
      );
      return true;
    }

    if (text.startsWith(':join ')) {
      final ch = text.substring(':join '.length).trim().toLowerCase();
      if (ch.isEmpty) {
        _toast('[INFO] :join <channel>');
        return true;
      }
      setState(() => _activeChannel = ch);
      await _sendWire(
        ChatWireMessage(
          sender: widget.config.username,
          content: '',
          createdAt: DateTime.now(),
          type: WireTypes.joinChannel,
          channel: ch,
        ),
      );
      return true;
    }

    if (text.startsWith(':search ')) {
      final q = text.substring(':search '.length).trim();
      if (q.isEmpty) {
        _toast('[INFO] :search <query>');
        return true;
      }
      await _sendWire(
        ChatWireMessage(
          sender: widget.config.username,
          content: q,
          createdAt: DateTime.now(),
          type: WireTypes.search,
        ),
      );
      return true;
    }

    if (text.startsWith(':dm')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length == 1) {
        setState(() => _dmRecipient = null);
        _toast('[OK] DM mode off');
        return true;
      }
      if (parts.length == 2) {
        final u = parts[1];
        if (_dmRecipient == u) {
          _toast('[OK] DM already: $u');
          return true;
        }
        setState(() => _dmRecipient = u);
        _toast('[OK] DM → $_dmRecipient');
        return true;
      }
      final target = parts[1];
      final body = parts.sublist(2).join(' ');
      await _sendWire(
        ChatWireMessage(
          sender: widget.config.username,
          content: body,
          createdAt: DateTime.now(),
          type: WireTypes.dm,
          recipient: target,
        ),
      );
      return true;
    }

    if (text.startsWith(':edit ')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 3) {
        _toast('[INFO] Usage: :edit <message_id> <new text>');
        return true;
      }
      final id = int.tryParse(parts[1]);
      if (id == null) {
        _toast('[ERROR] Invalid message ID');
        return true;
      }
      final newText = parts.sublist(2).join(' ');
      String content = newText;
      var enc = false;
      if (widget.e2e != null) {
        try {
          final w = await widget.e2e!.encryptOutgoingText(
            widget.config.username,
            newText,
          );
          content = w.content;
          enc = true;
        } catch (e) {
          _toast('[ERROR] Encrypt edit: $e');
          return true;
        }
      }
      await _sendJson({
        'sender': widget.config.username,
        'type': WireTypes.edit,
        'message_id': id,
        'content': content,
        if (enc) 'encrypted': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    }

    if (text.startsWith(':delete ')) {
      final id = int.tryParse(text.split(RegExp(r'\s+')).last);
      if (id == null) {
        _toast('[ERROR] Invalid message ID');
        return true;
      }
      await _sendJson({
        'sender': widget.config.username,
        'type': WireTypes.delete,
        'message_id': id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    }

    if (text.startsWith(':react ')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 3) {
        _toast('[INFO] Usage: :react <message_id> <emoji>');
        return true;
      }
      final id = int.tryParse(parts[1]);
      if (id == null) {
        _toast('[ERROR] Invalid message ID');
        return true;
      }
      final emoji = resolveReactionEmoji(parts[2]);
      await _sendJson({
        'sender': widget.config.username,
        'type': WireTypes.reaction,
        'reaction': {'emoji': emoji, 'target_id': id},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    }

    if (text.startsWith(':pin ')) {
      final id = int.tryParse(text.split(RegExp(r'\s+')).last);
      if (id == null) {
        _toast('[ERROR] Invalid message ID');
        return true;
      }
      await _sendJson({
        'sender': widget.config.username,
        'type': WireTypes.pin,
        'message_id': id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    }

    if (text == ':pinned') {
      await _sendJson({
        'sender': widget.config.username,
        'type': WireTypes.pin,
        'content': 'list',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    }

    if (text == ':export' || text.startsWith(':export ')) {
      var name = 'marchat-export.txt';
      if (text.startsWith(':export ')) {
        name = text.substring(':export '.length).trim();
        if (name.isEmpty) name = 'marchat-export.txt';
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export transcript',
        fileName: name,
      );
      if (path == null) {
        _toast('[WARN] Export cancelled');
        return true;
      }
      final sb = StringBuffer();
      for (final m in _messages) {
        final ts = m.createdAt.toLocal().toIso8601String();
        sb.writeln('[$ts] ${m.sender}: ${m.content}');
      }
      try {
        await File(path).writeAsString(sb.toString());
        _toast('[OK] Exported → $path');
      } catch (e) {
        _toast('[ERROR] Export failed: $e');
      }
      return true;
    }

    return false;
  }

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  Future<void> _submitInput([String? line]) async {
    final raw = line ?? _input.text;
    final text = raw.trim();
    if (text.isEmpty) return;

    if (await _handleTypedCommand(text)) {
      _input.clear();
      _inputFocus.requestFocus();
      return;
    }

    if (_ch == null) {
      _toast('[ERROR] Not connected');
      return;
    }

    if (text.startsWith(':')) {
      if (widget.isAdmin) {
        await _sendWire(
          ChatWireMessage(
            sender: widget.config.username,
            content: text,
            createdAt: DateTime.now(),
            type: WireTypes.adminCommand,
          ),
        );
        _input.clear();
        _inputFocus.requestFocus();
      } else {
        _toast('[ERROR] Unknown command');
      }
      return;
    }

    setState(() => _sending = true);

    try {
      if (_dmRecipient != null) {
        await _sendWire(
          ChatWireMessage(
            sender: widget.config.username,
            content: text,
            createdAt: DateTime.now(),
            type: WireTypes.dm,
            recipient: _dmRecipient!,
          ),
        );
      } else if (widget.e2e != null) {
        final enc = await widget.e2e!.encryptOutgoingText(
          widget.config.username,
          text,
        );
        await _sendWire(enc);
      } else {
        await _sendWire(
          ChatWireMessage.plainText(widget.config.username, text),
        );
      }
    } catch (e) {
      _toast('[ERROR] Send failed: $e');
    }

    _input.clear();
    _inputFocus.requestFocus();
    setState(() => _sending = false);
  }

  Future<void> _sendFile(String? pathOrNull) async {
    if (_ch == null) {
      _toast('[ERROR] Not connected');
      return;
    }
    try {
      Uint8List bytes;
      String name;
      if (pathOrNull != null && pathOrNull.isNotEmpty) {
        final f = File(pathOrNull);
        bytes = await f.readAsBytes();
        name = f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : 'file';
      } else {
        final pick = await FilePicker.platform.pickFiles(withData: true);
        if (pick == null || pick.files.isEmpty) return;
        final f = pick.files.first;
        name = f.name;
        bytes = f.bytes ?? await File(f.path!).readAsBytes();
      }
      const maxBytes = 1024 * 1024;
      if (bytes.length > maxBytes) {
        _toast('[ERROR] File too large (max 1 MiB)');
        return;
      }
      Uint8List wireBytes = bytes;
      var encFile = false;
      if (widget.e2e != null) {
        wireBytes = await widget.e2e!.encryptRaw(bytes);
        encFile = true;
      }
      await _sendWire(
        ChatWireMessage(
          sender: widget.config.username,
          content: '',
          createdAt: DateTime.now(),
          type: WireTypes.file,
          encrypted: encFile,
          file: WireFileMeta(
            filename: name,
            size: wireBytes.length,
            data: wireBytes,
          ),
        ),
      );
      _toast('[OK] Sent file $name');
    } catch (e) {
      _toast('[ERROR] File send: $e');
    }
  }

  Future<void> _saveFile(String arg) async {
    final s = arg.trim();
    WireFileMeta? f;
    if (s.startsWith('id:')) {
      final id = int.tryParse(s.substring(3));
      if (id != null) f = _receivedFiles['id:$id'];
    } else {
      f = _receivedFiles['fn:$s'] ?? _receivedFiles[s];
    }
    if (f == null) {
      _toast('[ERROR] No file "$s" in session cache');
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save file',
      fileName: f.filename,
    );
    if (path == null) return;
    try {
      await File(path).writeAsBytes(f.data);
      _toast('[OK] Saved → $path');
    } catch (e) {
      _toast('[ERROR] Save failed: $e');
    }
  }

  Future<void> _openCodeSnippetDialog() async {
    final lang = TextEditingController();
    final code = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code snippet'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: Column(
            children: [
              TextField(
                controller: lang,
                decoration: const InputDecoration(labelText: 'Language'),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Code…',
                  ),
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (code.text.isNotEmpty) {
                final block = '```${lang.text.trim()}\n${code.text}\n```';
                Navigator.pop(ctx);
                _submitInput(block);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _cycleTheme() {
    setState(() {
      _themeIndex = (_themeIndex + 1) % kMcBuiltinChatThemes.length;
      widget.config.chatThemeId = kMcBuiltinChatThemes[_themeIndex].id;
    });
    unawaited(_persistChatDisplayPrefs());
    _toast('[OK] Theme → ${t.name}');
  }

  /// Formats [dt] using the device local timezone for display.
  String _fmtClock(DateTime dt) {
    final local = dt.toLocal();
    if (_twentyFourHour) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final ap = local.hour < 12 ? 'AM' : 'PM';
    return '$h12:${local.minute.toString().padLeft(2, '0')} $ap';
  }

  double get _timeColumnWidth => _twentyFourHour ? 44.0 : 68.0;

  String _timeCellText(ChatWireMessage m) {
    final clock = _fmtClock(m.createdAt);
    if (widget.e2e != null && m.encrypted) return '$clock *';
    return clock;
  }

  Widget _header() {
    final title = _dmRecipient != null
        ? 'DM: $_dmRecipient'
        : '#$_activeChannel';
    return Container(
      height: 42,
      color: t.headerBg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Channels',
            onPressed: () =>
                setState(() => _showChannelsPanel = !_showChannelsPanel),
            icon: Icon(Icons.menu, color: t.headerFg, size: 20),
          ),
          Text(
            'marchat',
            style: TextStyle(
              color: t.headerFg,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '›',
              style: TextStyle(color: t.headerFg.withValues(alpha: 0.5)),
            ),
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.headerFg,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
          if (_inFocus()) ...[
            Icon(Icons.do_not_disturb_on_outlined, color: t.bannerFg, size: 16),
            const SizedBox(width: 4),
            Text(
              'focus',
              style: TextStyle(
                color: t.bannerFg,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            tooltip: 'Cycle theme (Ctrl+T)',
            onPressed: _cycleTheme,
            icon: Icon(Icons.palette_outlined, color: t.headerFg, size: 20),
          ),
          IconButton(
            tooltip: 'Help (Ctrl+H)',
            onPressed: () => setState(() => _showHelp = !_showHelp),
            icon: Icon(Icons.help_outline, color: t.headerFg, size: 20),
          ),
          IconButton(
            tooltip: 'Users',
            onPressed: () => setState(() => _showUsersPanel = !_showUsersPanel),
            icon: Icon(Icons.people_outline, color: t.headerFg, size: 20),
          ),
          if (widget.e2e != null) ...[
            const SizedBox(width: 8),
            Text(
              _connected ? 'E2E on' : 'E2E',
              style: TextStyle(
                color: _connected
                    ? (Color.lerp(t.headerFg, t.accentFg, 0.55) ?? t.accentFg)
                    : t.headerFg.withValues(alpha: 0.42),
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.0,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _connected ? const Color(0xFF44EE44) : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _connected ? 'Connected' : 'Disconnected',
            style: TextStyle(
              color: t.headerFg.withValues(alpha: 0.65),
              fontFamily: 'monospace',
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerBar() {
    if (_banner.isEmpty) return const SizedBox.shrink();
    final err = _banner.startsWith('[ERROR]');
    final fg = err ? t.bannerFg : t.accentFg;
    return Material(
      color: fg.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            Icon(
              err ? Icons.error_outline : Icons.info_outline,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _banner,
                style: TextStyle(
                  color: fg,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            InkWell(
              onTap: () => setState(() => _banner = ''),
              child: Icon(
                Icons.close,
                size: 14,
                color: fg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelPanel() {
    return Container(
      width: 168,
      color: t.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelSection('CHANNEL'),
          ListTile(
            dense: true,
            title: Text(
              '#$_activeChannel',
              style: TextStyle(
                color: t.accentFg,
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              'Use :join :leave :channels',
              style: TextStyle(color: t.timeFg, fontSize: 10),
            ),
          ),
          const Divider(height: 1),
          _panelSection('DM'),
          ListTile(
            dense: true,
            title: Text(
              _dmRecipient ?? '(off)',
              style: TextStyle(
                color: t.msgFg,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
            subtitle: Text(
              ':dm user | :dm',
              style: TextStyle(color: t.timeFg, fontSize: 10),
            ),
          ),
          const Spacer(),
          if (widget.isAdmin)
            ListTile(
              dense: true,
              leading: Icon(Icons.storage, color: t.accentFg, size: 18),
              title: Text(
                ':cleardb / :backup / :stats',
                style: TextStyle(
                  color: t.accentFg,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
              subtitle: Text(
                'Also :list :store …',
                style: TextStyle(color: t.timeFg, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelSection(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
    child: Text(
      label,
      style: TextStyle(
        color: t.timeFg,
        fontSize: 9,
        fontFamily: 'monospace',
        letterSpacing: 1.1,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _userPanel() {
    return Container(
      width: 160,
      color: t.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Text(
              'USERS ${_users.length}',
              style: TextStyle(
                color: t.timeFg,
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                final isMe = u == widget.config.username;
                final sel = widget.isAdmin && _selectedUserIndex == i;
                return Material(
                  color: sel
                      ? t.borderColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                  child: ListTile(
                    dense: true,
                    title: Text(
                      isMe ? '$u (me)' : u,
                      style: TextStyle(
                        color: isMe ? t.meFg : t.otherFg,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: widget.isAdmin && !isMe
                        ? () => setState(() {
                            if (_selectedUserIndex == i) {
                              _selectedUserIndex = -1;
                              _selectedUser = '';
                            } else {
                              _selectedUserIndex = i;
                              _selectedUser = u;
                            }
                          })
                        : null,
                  ),
                );
              },
            ),
          ),
          if (widget.isAdmin && _selectedUser.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _miniAct('Kick', () => _adminUserCmd('kick')),
                  _miniAct('Ban', () => _adminUserCmd('ban')),
                  _miniAct('FD', () => _adminUserCmd('forcedisconnect')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniAct(String label, VoidCallback onTap) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      foregroundColor: t.accentFg,
      side: BorderSide(color: t.borderColor.withValues(alpha: 0.5)),
      visualDensity: VisualDensity.compact,
    ),
    onPressed: onTap,
    child: Text(
      label,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
    ),
  );

  Future<void> _adminUserCmd(String verb) async {
    if (_selectedUser.isEmpty) return;
    if (_selectedUser == widget.config.username) {
      _toast('[ERROR] Cannot target self');
      return;
    }
    await _sendWire(
      ChatWireMessage(
        sender: widget.config.username,
        content: ':$verb $_selectedUser',
        createdAt: DateTime.now(),
        type: WireTypes.adminCommand,
      ),
    );
    if (verb == 'kick' || verb == 'ban' || verb == 'forcedisconnect') {
      setState(() {
        _selectedUserIndex = -1;
        _selectedUser = '';
      });
    }
    _toast('[OK] Sent :$verb');
  }

  Widget _messageLine(ChatWireMessage m) {
    final me = m.sender == widget.config.username;
    final ts = _timeCellText(m);
    if (m.type == WireTypes.file && m.file != null) {
      final saveArg = m.messageId != 0 ? 'id:${m.messageId}' : m.file!.filename;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _timeColumnWidth,
              child: Text(
                ts,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.timeFg,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(
                m.sender,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: me ? t.meFg : t.userFg,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '[file] ${m.file!.filename} (${m.file!.size} bytes); :savefile $saveArg',
                    style: TextStyle(
                      color: t.msgFg,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  ..._reactionTrail(m.messageId),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _timeColumnWidth,
            child: Text(
              ts,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.timeFg,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Text(
              m.sender,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: me ? t.meFg : t.userFg,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (m.type == WireTypes.delete)
                  Text(
                    '[deleted]',
                    style: TextStyle(
                      color: t.timeFg,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else if (m.edited)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '(edited) ',
                        style: TextStyle(
                          color: t.timeFg,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      Expanded(child: _richMessage(m.content)),
                    ],
                  )
                else
                  _richMessage(m.content),
                ..._reactionTrail(m.messageId),
              ],
            ),
          ),
          if (_showMsgMeta && m.messageId != 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '#${m.messageId}${m.encrypted ? ", enc" : ""}',
                style: TextStyle(
                  color: t.timeFg,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _reactionTrail(int messageId) {
    if (messageId == 0) return const [];
    final line = formatReactionSummary(_reactionsByTarget, messageId);
    if (line == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          line,
          style: TextStyle(
            color: t.timeFg,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    ];
  }

  Widget _richMessage(String content) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'(@\w+)').allMatches(content)) {
      if (m.start > last) {
        spans.add(TextSpan(text: content.substring(last, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: TextStyle(color: t.mentionFg, fontWeight: FontWeight.bold),
        ),
      );
      last = m.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(color: t.msgFg, fontFamily: 'monospace', fontSize: 13),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
            setState(() => _showHelp = !_showHelp),
        const SingleActivator(LogicalKeyboardKey.keyT, control: true):
            _cycleTheme,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: t.bg,
          body: Stack(
            children: [
              Column(
                children: [
                  _header(),
                  _bannerBar(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    color: t.sidebarBg,
                    child: Text(
                      _statusLine,
                      style: TextStyle(
                        color: t.otherFg,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_showChannelsPanel) _channelPanel(),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: t.borderColor.withValues(alpha: 0.2),
                                ),
                                right: BorderSide(
                                  color: t.borderColor.withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                            child: _messages.isEmpty
                                ? Center(
                                    child: Text(
                                      'No messages yet.',
                                      style: TextStyle(
                                        color: t.timeFg,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _scroll,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    itemCount: _messages.length,
                                    itemBuilder: (_, i) =>
                                        _messageLine(_messages[i]),
                                  ),
                          ),
                        ),
                        if (_showUsersPanel) _userPanel(),
                      ],
                    ),
                  ),
                  _inputBar(),
                ],
              ),
              if (_showHelp) _helpOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    final hint = _dmRecipient != null
        ? 'DM to $_dmRecipient; :dm to exit. Enter send, Shift+Enter newline.'
        : 'Message or command. Enter send, Shift+Enter newline. Ctrl+H help.';
    return Material(
      color: t.sidebarBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: t.borderColor.withValues(alpha: 0.2),
              child: Text(
                _dmRecipient != null ? '@$_dmRecipient' : '#$_activeChannel',
                style: TextStyle(
                  color: t.accentFg,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _inputFocus,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  color: t.inputFg,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                cursorColor: t.accentFg,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: t.inputBg,
                  hintText: hint,
                  hintStyle: TextStyle(
                    color: t.timeFg,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: t.borderColor.withValues(alpha: 0.35),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: t.borderColor.withValues(alpha: 0.65),
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _submitInput(),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _sending ? null : () => _submitInput(),
              style: FilledButton.styleFrom(
                backgroundColor: t.headerBg,
                foregroundColor: t.headerFg,
              ),
              child: Text(_sending ? '…' : 'Send'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showHelp = false),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 520,
                  maxHeight: 520,
                ),
                child: Material(
                  color: t.bg,
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        color: t.headerBg,
                        child: Row(
                          children: [
                            Text(
                              'marchat help',
                              style: TextStyle(
                                color: t.headerFg,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _showHelp = false),
                              icon: Icon(
                                Icons.close,
                                color: t.headerFg,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _helpBodyText,
                            style: TextStyle(
                              color: t.msgFg,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
