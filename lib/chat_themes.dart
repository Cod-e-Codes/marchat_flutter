import 'package:flutter/material.dart';

/// Terminal-style chat chrome colors (aligned with TUI built-ins: system, patriot,
/// retro, modern — same names and `:themes` / Ctrl+T order as marchat TUI).
Color mcHex(String h) =>
    Color(int.parse('FF${h.replaceFirst('#', '')}', radix: 16));

class McChatTheme {
  final String id;
  final String name;
  final String description;
  final Color bg;
  final Color sidebarBg;
  final Color headerBg;
  final Color headerFg;
  final Color borderColor;
  final Color inputBg;
  final Color inputFg;
  final Color msgFg;
  final Color userFg;
  final Color timeFg;
  final Color mentionFg;
  final Color bannerFg;
  final Color meFg;
  final Color otherFg;
  final Color accentFg;

  const McChatTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.bg,
    required this.sidebarBg,
    required this.headerBg,
    required this.headerFg,
    required this.borderColor,
    required this.inputBg,
    required this.inputFg,
    required this.msgFg,
    required this.userFg,
    required this.timeFg,
    required this.mentionFg,
    required this.bannerFg,
    required this.meFg,
    required this.otherFg,
    required this.accentFg,
  });
}

/// Same sequence as `ListAllThemes()` in marchat `client/theme_loader.go`.
final List<McChatTheme> kMcBuiltinChatThemes = [
  const McChatTheme(
    id: 'system',
    name: 'System',
    description: "Uses terminal's default colors",
    bg: Color(0xFF121212),
    sidebarBg: Color(0xFF0A0A0A),
    headerBg: Color(0xFF1E1E1E),
    headerFg: Color(0xFFCCCCCC),
    borderColor: Color(0xFF444444),
    inputBg: Color(0xFF1A1A1A),
    inputFg: Color(0xFFDDDDDD),
    msgFg: Color(0xFFCCCCCC),
    userFg: Color(0xFF00CC00),
    timeFg: Color(0xFF555555),
    mentionFg: Color(0xFFFFFF00),
    bannerFg: Color(0xFFFF4444),
    meFg: Color(0xFF00CC00),
    otherFg: Color(0xFF888888),
    accentFg: Color(0xFF00AAFF),
  ),
  McChatTheme(
    id: 'patriot',
    name: 'Patriot',
    description: 'American patriotic theme (red, white, blue)',
    bg: mcHex('#00203F'),
    sidebarBg: mcHex('#001830'),
    headerBg: mcHex('#BF0A30'),
    headerFg: mcHex('#FFFFFF'),
    borderColor: mcHex('#002868'),
    inputBg: mcHex('#002868'),
    inputFg: mcHex('#FFFFFF'),
    msgFg: mcHex('#FFFFFF'),
    userFg: mcHex('#002868'),
    timeFg: mcHex('#BF0A30'),
    mentionFg: mcHex('#FFD700'),
    bannerFg: mcHex('#FF5555'),
    meFg: mcHex('#BF0A30'),
    otherFg: mcHex('#87CEEB'),
    accentFg: mcHex('#FFD700'),
  ),
  McChatTheme(
    id: 'retro',
    name: 'Retro',
    description: 'Retro terminal theme (orange, green)',
    bg: mcHex('#181818'),
    sidebarBg: mcHex('#101010'),
    headerBg: mcHex('#FF8800'),
    headerFg: mcHex('#181818'),
    borderColor: mcHex('#FF8800'),
    inputBg: mcHex('#222200'),
    inputFg: mcHex('#FFFFAA'),
    msgFg: mcHex('#FFFFAA'),
    userFg: mcHex('#FF8800'),
    timeFg: mcHex('#00FF00'),
    mentionFg: mcHex('#00FFFF'),
    bannerFg: mcHex('#FF6600'),
    meFg: mcHex('#FF8800'),
    otherFg: mcHex('#00FFFF'),
    accentFg: mcHex('#FFFFAA'),
  ),
  McChatTheme(
    id: 'modern',
    name: 'Modern',
    description: 'Modern dark blue-gray theme',
    bg: mcHex('#181C24'),
    sidebarBg: mcHex('#13161e'),
    headerBg: mcHex('#4F8EF7'),
    headerFg: mcHex('#FFFFFF'),
    borderColor: mcHex('#4F8EF7'),
    inputBg: mcHex('#23272E'),
    inputFg: mcHex('#E0E0E0'),
    msgFg: mcHex('#E0E0E0'),
    userFg: mcHex('#4F8EF7'),
    timeFg: mcHex('#A0A0A0'),
    mentionFg: mcHex('#FF5F5F'),
    bannerFg: mcHex('#FF5F5F'),
    meFg: mcHex('#4F8EF7'),
    otherFg: mcHex('#AAAAAA'),
    accentFg: mcHex('#4A9EFF'),
  ),
];

McChatTheme? mcThemeById(String id) {
  final k = id.toLowerCase().trim();
  for (final t in kMcBuiltinChatThemes) {
    if (t.id == k) return t;
  }
  return null;
}

String mcBuiltinThemeIdsJoined() =>
    kMcBuiltinChatThemes.map((e) => e.id).join(', ');
