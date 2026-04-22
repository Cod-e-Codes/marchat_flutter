/// Persisted / passed client configuration (username, server URL, time format).
class MarchatClientConfig {
  String username;
  String serverURL;
  bool twentyFourHour;

  /// Last selected built-in chat theme id (`system`, `patriot`, `retro`, `modern`).
  String chatThemeId;

  MarchatClientConfig({
    required this.username,
    required this.serverURL,
    this.twentyFourHour = true,
    this.chatThemeId = 'modern',
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'serverURL': serverURL,
    'twentyFourHour': twentyFourHour,
    'chatThemeId': chatThemeId,
  };

  factory MarchatClientConfig.fromJson(Map<String, dynamic> json) =>
      MarchatClientConfig(
        username: json['username'] as String? ?? '',
        serverURL: json['serverURL'] as String? ?? '',
        twentyFourHour: json['twentyFourHour'] as bool? ?? true,
        chatThemeId: json['chatThemeId'] as String? ?? 'modern',
      );
}
