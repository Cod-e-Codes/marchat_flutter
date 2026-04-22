import 'dart:convert';
import 'dart:typed_data';

/// Mirrors `shared.Message` / `shared.MessageType` wire JSON from marchat.
abstract final class WireTypes {
  static const text = 'text';
  static const file = 'file';

  /// Matches Go `shared.AdminCommandType` (`"admin_command"`).
  static const adminCommand = 'admin_command';
  static const edit = 'edit';
  static const delete = 'delete';
  static const dm = 'dm';
  static const search = 'search';
  static const reaction = 'reaction';
  static const pin = 'pin';
  static const typing = 'typing';
  static const readReceipt = 'read_receipt';
  static const joinChannel = 'join_channel';
  static const leaveChannel = 'leave_channel';
  static const listChannels = 'list_channels';
}

class WireFileMeta {
  final String filename;
  final int size;
  final Uint8List data;

  WireFileMeta({
    required this.filename,
    required this.size,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'size': size,
    'data': base64Encode(data),
  };

  factory WireFileMeta.fromJson(Map<String, dynamic> j) {
    final raw = j['data'];
    Uint8List bytes;
    if (raw is String) {
      bytes = Uint8List.fromList(base64Decode(raw));
    } else if (raw is List) {
      bytes = Uint8List.fromList(raw.cast<int>());
    } else {
      bytes = Uint8List(0);
    }
    return WireFileMeta(
      filename: j['filename'] as String? ?? '',
      size: (j['size'] as num?)?.toInt() ?? bytes.length,
      data: bytes,
    );
  }
}

class ChatWireMessage {
  final String sender;
  String content;
  final DateTime createdAt;
  final String type;
  final bool encrypted;
  final int messageId;
  final String recipient;
  final String channel;
  final bool edited;
  final WireFileMeta? file;
  final Map<String, dynamic>? reaction;

  ChatWireMessage({
    required this.sender,
    required this.content,
    required this.createdAt,
    this.type = WireTypes.text,
    this.encrypted = false,
    this.messageId = 0,
    this.recipient = '',
    this.channel = '',
    this.edited = false,
    this.file,
    this.reaction,
  });

  static DateTime _parseTime(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.now();
    }
    return DateTime.now();
  }

  factory ChatWireMessage.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String?)?.trim();
    WireFileMeta? fm;
    if (j['file'] is Map<String, dynamic>) {
      fm = WireFileMeta.fromJson(j['file'] as Map<String, dynamic>);
    }
    final mid = j['message_id'];
    int messageId = 0;
    if (mid is int) {
      messageId = mid;
    } else if (mid is num) {
      messageId = mid.toInt();
    }
    return ChatWireMessage(
      sender: j['sender'] as String? ?? '',
      content: j['content'] as String? ?? '',
      createdAt: _parseTime(j['created_at']),
      type: (type == null || type.isEmpty) ? WireTypes.text : type,
      encrypted: j['encrypted'] as bool? ?? false,
      messageId: messageId,
      recipient: j['recipient'] as String? ?? '',
      channel: j['channel'] as String? ?? '',
      edited: j['edited'] as bool? ?? false,
      file: fm,
      reaction: j['reaction'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(j['reaction'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'sender': sender,
      'content': content,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
    // Omit `type` for plain text so JSON matches Go `omitempty` on default `text`.
    if (type.isNotEmpty && type != WireTypes.text) {
      m['type'] = type;
    }
    if (encrypted) m['encrypted'] = true;
    if (messageId != 0) m['message_id'] = messageId;
    if (recipient.isNotEmpty) m['recipient'] = recipient;
    if (channel.isNotEmpty) m['channel'] = channel;
    if (edited) m['edited'] = true;
    if (file != null) m['file'] = file!.toJson();
    if (reaction != null) m['reaction'] = reaction;
    return m;
  }

  ChatWireMessage copyWith({
    String? sender,
    String? content,
    DateTime? createdAt,
    String? type,
    bool? encrypted,
    int? messageId,
    String? recipient,
    String? channel,
    bool? edited,
    WireFileMeta? file,
    Map<String, dynamic>? reaction,
    bool clearFile = false,
    bool clearReaction = false,
  }) {
    return ChatWireMessage(
      sender: sender ?? this.sender,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      encrypted: encrypted ?? this.encrypted,
      messageId: messageId ?? this.messageId,
      recipient: recipient ?? this.recipient,
      channel: channel ?? this.channel,
      edited: edited ?? this.edited,
      file: clearFile ? null : (file ?? this.file),
      reaction: clearReaction ? null : (reaction ?? this.reaction),
    );
  }

  /// Plain global-channel text (matches Go `shared.Message` defaults).
  factory ChatWireMessage.plainText(String sender, String content) {
    return ChatWireMessage(
      sender: sender,
      content: content,
      createdAt: DateTime.now(),
      type: WireTypes.text,
    );
  }
}
