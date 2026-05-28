# marchat_flutter

![marchat_flutter connect screen](marchat_flutter_screenshot.png)

Flutter desktop and multi-platform client for [marchat](https://github.com/Cod-e-Codes/marchat), a real-time chat server using WebSocket JSON and the same wire types as the official Go TUI client.

**Status:** Primary GUI focus for the marchat ecosystem. **v1.2.x** tracks the [marchat](https://github.com/Cod-e-Codes/marchat) **v1.2.0** server line (server release expected soon; this client aligns with that protocol on `main`).

## Relationship to marchat

This is an optional graphical client for the main [marchat](https://github.com/Cod-e-Codes/marchat) project.

- The terminal client in `marchat` remains the reference client and protocol source.
- `marchat_flutter` is the recommended GUI path for users who want desktop or mobile UI.
- Wire message compatibility follows [PROTOCOL.md](https://github.com/Cod-e-Codes/marchat/blob/main/PROTOCOL.md).
- Plugin registry defaults and catalog come from [marchat-plugins](https://github.com/Cod-e-Codes/marchat-plugins).

**Also see:** [marchat-gui](https://github.com/Cod-e-Codes/marchat-gui) (Go/Fyne companion client).

## Features

- Real-time messaging over WebSocket (string message types, admin commands, channels, DMs, structured commands aligned with the TUI)
- Channel messages persist channel metadata on the wire and the transcript shows only the active channel when not in a DM thread
- Direct messages use `:dm <user> <message>` and the left sidebar lists DM threads with unread counts
- Reactions (`type: reaction` with `reaction.target_id` / `emoji` / `is_removal`) update the transcript in place and render under the target message like the Go TUI
- Optional global E2E: ChaCha20-Poly1305 on the wire, compatible with `shared.EncryptTextMessage` / `MARCHAT_GLOBAL_E2E_KEY`. Applies to channel chat, direct messages, edits, and file payloads when a key is loaded. In chat, plain text **`E2E on`** (theme-tinted) appears in the header next to the socket dot when a key is loaded and the socket is up; the left status strip still shows **`Connected (E2E)`**. Rows that were **`encrypted` on the wire** keep that flag after decrypt and show a **`*`** after the time (`:msginfo` adds `#id, enc`), matching the Go client's metadata idea.
- On reconnect, the transcript is cleared before server history replay so messages are not duplicated (same as the Go TUI).
- Read receipts are sent (debounced) when the message list is scrolled to the bottom.
- Chat composer: **Enter** sends, **Shift+Enter** starts a new line; **12-hour** times stay on one line in a wider time column; the header shows **Connected** / **Disconnected** next to the socket indicator.
- Unlock existing `keystore.dat` with the same passphrase and format as `client/crypto/keystore.go` (v3 portable header or legacy path-salt)
- File send and save
- Message list times use the device local timezone (same idea as the TUI when the server sends UTC in the JSON created_at field)
- Built-in chat themes matching TUI order: `system`, `patriot`, `retro`, `modern` (`:theme`, `:themes`, Ctrl+T)
- Admin commands (kick, ban, unban, allow, forcedisconnect, cleardb, backup, stats, plugin-style `:` commands to the server)

## Requirements

- Flutter stable in the 3.44.x line (tested with 3.44.0) and Dart 3.12.x as bundled with that SDK
- Dart SDK constraint for this package: see `pubspec.yaml` (`>=3.8.0 <4.0.0`)
- Git for Windows (or Git on your PATH) if you clone with Git
- **Windows desktop builds:** plugin builds need symlink support. Turn on **Developer Mode** in Windows Settings (Privacy and security, For developers), or run the build from an elevated shell. See Flutter Windows setup docs if `flutter build windows` fails with a symlink message.

## Branding

The same logo files as the [marchat](https://github.com/Cod-e-Codes/marchat) repo live under `assets/branding/` (`marchat-transparent.png` and `.svg`). The **in-app** UI is text only (no repeated logos). The PNG is used to generate **taskbar, window, and PWA/ favicon** icons. After changing the artwork, refresh those:

```bash
dart run flutter_launcher_icons
```

That overwrites platform launcher and `web/icons` from `assets/branding/marchat-transparent.png` (and updates web favicon when the tool does so).

## Setup

```
flutter pub get
```

## Run

Windows:

```
flutter run -d windows
```

Android emulator:

```
flutter run -d emulator-5554
```

## Test

```
flutter test
```

## Releases

Prebuilt binaries are published on **[GitHub Releases](https://github.com/Cod-e-Codes/marchat_flutter/releases)** when a `v*` tag is pushed.

| Asset | File name |
|-------|-----------|
| Android | `marchat-flutter-<version>-android.apk` |
| Windows x64 | `marchat-flutter-<version>-windows-x64.zip` |

Use a **marchat server** build from the same line (for example **v1.2.0**) for full protocol parity. See [CHANGELOG.md](CHANGELOG.md) (auto-updated from git history).

### Cutting a release (maintainers)

1. Merge to `main`. The **Update changelog** workflow keeps [CHANGELOG.md](CHANGELOG.md) current (or run it manually under Actions).
2. Tag and push: `git tag v1.2.0 && git push origin v1.2.0`
3. The **Release** workflow builds the APK and Windows zip, generates release notes with [git-cliff](https://git-cliff.org), and publishes the GitHub Release.

To rebuild an existing tag without changing it, run **Release** via **workflow_dispatch** and pass an existing `v*` tag (for example `v1.2.0`). Only collaborators with permission to run workflows can do this; the workflow verifies the tag exists before building.

Protect `main` and `v*` tags in GitHub branch/tag protection so only trusted maintainers can push code or tags that trigger these workflows.

## Build from source

Windows:

```
flutter build windows --release
```

Linux (on Linux or WSL with a desktop toolchain):

```
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter config --enable-linux-desktop
flutter build linux --release
```

Artifacts:

- Windows: `build/windows/x64/runner/Release/marchat_flutter.exe`
- Linux: `build/linux/x64/release/bundle/`

Linux desktop builds are local only (not attached to GitHub Releases yet).

## CI

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| [CI](.github/workflows/ci.yml) | Push or PR to `main` | `flutter analyze` and `flutter test` (read-only token) |
| [Update changelog](.github/workflows/changelog.yml) | Push to `main`, manual | Regenerate `CHANGELOG.md` from commits |
| [Release](.github/workflows/release.yml) | Push tag `v*`, manual | Build APK + Windows zip, publish GitHub Release |

Dependabot opens weekly PRs to update pinned GitHub Actions (see [.github/dependabot.yml](.github/dependabot.yml)).

## Configuration

- Default server URL on the connect screen: `ws://localhost:8080/ws` (adjust for `wss://` behind a proxy as needed).
- Entry point: `lib/main.dart`. Main chat UI: `lib/screens/chat_screen.dart`.
- The connect screen can set **24-hour clock** and **built-in chat theme**; those values persist in SharedPreferences (`marchat_chat_twenty_four_hour`, `marchat_chat_theme_id`) and stay in sync when you use `:time`, `:theme`, or Ctrl+T in chat.

### Android emulator and localhost

When using the Android emulator, `localhost` inside the app is the emulator itself, not your PC host process.
If your server is running on your PC at port 8080, map emulator port 8080 to host port 8080:

```
adb reverse tcp:8080 tcp:8080
```

After that, `ws://localhost:8080/ws` or `wss://localhost:8080/ws` in the app will target your host server through the reverse tunnel.

### TLS note for Android builds

| Build | `wss://` behavior |
|-------|-------------------|
| **Debug** (`flutter run`) | Dart accepts any certificate when `kDebugMode` is on. The debug network security config also trusts **user-installed CAs** (`<certificates src="user"/>`), so `wss://` can work with a CA you install on the device (homelab, proxy tools). |
| **Release** (GitHub APK, `flutter build apk --release`) | System CAs only. Use a publicly trusted certificate chain (for example Let's Encrypt behind your reverse proxy). Self-signed or user-CA `wss://` will fail. |

Cleartext `ws://` to `localhost`, `127.0.0.1`, and `10.0.2.2` is allowed in all builds for local dev and the emulator.

### E2E and keystore

1. **`MARCHAT_GLOBAL_E2E_KEY`** (base64, 32 raw bytes): if set in the environment, it takes precedence over a file-derived key (same as the Go client).
2. **Pasted global key** on the connect screen: optional; may be stored in secure storage when you save it from the field.
3. **`keystore.dat` + passphrase**: choose the same file the TUI uses and enter the same passphrase. Legacy v2 files use PBKDF2 with salt equal to the UTF-8 bytes of the **absolute path** of that file, so pick the real file path the Go client resolves (see `marchat-client -doctor` for config paths).

If E2E is enabled and none of the above apply, connect will fail until you provide a key or a valid keystore. The TUI generates a random global key on first use and writes it into `keystore.dat`; Flutter does not yet create a brand-new keystore from only a passphrase (use the TUI once, or set `MARCHAT_GLOBAL_E2E_KEY`).

## Admin commands

When connected as admin, you can send the same `:` commands as the server expects, for example:

```
:cleardb
:backup
:stats
:kick <user>
:ban <user>
:unban <user>
:allow <user>
:forcedisconnect <user>
```

Use in-app help (Ctrl+H) and the marchat TUI help for the full command set.

## DM behavior

- Send a direct message with `:dm <user> <message>`.
- There is no DM send toggle mode in the composer.
- The left sidebar shows users who have sent DMs to you or received DMs from you.
- DM messages are not shown in the default channel timeline.
- When a DM thread is selected, composer sends go to that user as DMs (encrypted on the wire when E2E is enabled, including code snippets from `:code`).
- When no DM thread is selected, composer sends go to the normal channel chat.
- Click a DM user in the sidebar to view that DM thread and clear its unread count.
- Typing indicators are scoped by active view: DM typing appears only in that DM thread, and channel typing appears only in the active channel view.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
