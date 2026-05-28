# Changelog

Narrative notes by release. Prebuilt APK and Windows zip: [GitHub Releases](https://github.com/Cod-e-Codes/marchat_flutter/releases).

Release numbers track the supported [marchat](https://github.com/Cod-e-Codes/marchat) server line (wire protocol). See [PROTOCOL.md](https://github.com/Cod-e-Codes/marchat/blob/main/PROTOCOL.md).

## Unreleased

On **main** only; not yet published. Compare to the latest tag on [GitHub Releases](https://github.com/Cod-e-Codes/marchat_flutter/releases).

**Targets marchat v1.2.0** server line (marchat v1.2.0 is scheduled for release on the server repo; this client branch aligns with that protocol work).


### Changes
- Initial commit: marchat Flutter client ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Create LICENSE ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Fix Android connectivity: add INTERNET permission, network security config, and update NDK version ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add demo screenshot ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Delete Screenshot_20250915_221327.jpg ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add demo screenshot ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add marchat_flutter screenshot to README ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Remove marchat_flutter.jpg and update README with new screenshot format and enhanced feature descriptions. Adjust Dart SDK constraints in pubspec.yaml and add new dependencies. Update main.dart for improved app structure and configuration screen. Modify generated plugin files for consistency across platforms. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Enhance configuration options in the app by adding 24-hour clock and built-in chat theme settings. Implement persistence of these preferences using SharedPreferences. Update README to reflect new features and improve code formatting for better readability. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Refactor chat UI text for consistency and clarity. Update app bar title format, improve error and status messages, and adjust chat input hints. Modify comments for better understanding in chat screen logic. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Implement platform-specific exit behavior in main.dart and enhance chat screen state management. Update exit button logic to handle web and native environments differently. Introduce a suppress flag for disconnect UI updates in chat screen to prevent unnecessary state changes during cleanup. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Update README and chat screen to display message timestamps in local timezone. Adjust formatting functions to ensure consistent time representation across the app. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Implement WebSocket error handling and message editing/deletion in chat screen. Add a method to determine disconnect reasons, manage socket subscriptions, and update UI for edited and deleted messages. Enhance connection logic with improved error logging. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Update project description in pubspec.yaml, add flutter_launcher_icons dependency, and configure launcher icons for multiple platforms. Revise README to include branding information and instructions for regenerating icons. Modify web metadata for improved app identification. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Fix reaction wire handling and render under messages ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Refactor app bar in ConfigScreen to a single line for improved readability. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Enhance chat screen functionality by implementing Enter/Shift+Enter key handling for message input, updating connection status display to reflect E2E encryption, and improving timestamp formatting. Revise README to include new chat features and shortcuts for better user guidance. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Update marchat_flutter_screenshot.png to reflect recent UI changes and enhancements in the chat screen. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Update README to clarify the relationship between marchat and marchat_flutter, highlighting its role as an optional GUI client and providing links to related projects and documentation. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Enhance direct messaging functionality in chat screen by implementing DM thread management, unread message tracking, and updating the UI to display active DMs. Revise README to include new DM features and usage instructions. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Enhance README with Android emulator setup instructions and TLS handling for debug builds. Update chat screen to support insecure TLS connections for local development and improve UI responsiveness for compact layouts. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Refine direct messaging functionality in chat screen by filtering out DM messages from the default channel timeline and enhancing the message sending logic for active DM threads. Update README to reflect these changes and clarify DM behavior in the application. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Implement typing indicators in chat screen, ensuring they are scoped by active view for DMs and channels. Update README to describe new typing functionality and its behavior in the application. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Update splash screen assets and configuration for improved branding. Modify launch background colors for Android and adjust iOS LaunchScreen storyboard to match new design. Add adaptive icon settings in pubspec.yaml for better icon support across platforms. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Align Flutter client with marchat E2E DMs and TUI reconnect behavior

Encrypt direct messages (composer, :dm, and :code in a DM thread) using
the same global ChaCha20-Poly1305 wire format as the Go client. Clear the
transcript on reconnect before server history replay, send debounced read
receipts when scrolled to the bottom, and add mc_crypto tests plus README
notes. ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add GitHub Actions workflow to build APK ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Update Flutter version to 3.41.7 in build workflow ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add step to accept Android licenses in workflow ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add release automation, git-cliff changelog, and CI for v1.2.0 line

Introduce Release workflow (APK + Windows zip on v* tags), Update changelog on main pushes, and CI for analyze/test. Configure git-cliff for CHANGELOG.md and GitHub Release notes. Bump app version to 1.2.0, document releases in README, and remove the manual build-apk workflow. ([Cod-e-Codes](https://github.com/Cod-e-Codes))


### Documentation
- Update README ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Add license section ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Link LICENSE in README ([Cod-e-Codes](https://github.com/Cod-e-Codes))


### Miscellaneous
- Ignore metadata and coverage; untrack .metadata ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- Bump Flutter to 3.44.0 in CI and README ([Cod-e-Codes](https://github.com/Cod-e-Codes))
- **android:** Upgrade Gradle, AGP, and Kotlin for Flutter 3.44 ([Cod-e-Codes](https://github.com/Cod-e-Codes))


---
Generated with [git-cliff](https://git-cliff.org). The **Update changelog** workflow refreshes this file on every push to `main`. Release notes on GitHub Releases use the same generator at tag time.
