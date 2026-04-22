import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'app_config.dart';
import 'marchat_keystore.dart';
import 'mc_crypto.dart';
import 'screens/chat_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MarchatApp());
}

class MarchatApp extends StatelessWidget {
  const MarchatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'marchat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: false),
      home: const ConfigScreen(),
    );
  }
}

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _server = TextEditingController(text: 'ws://localhost:8080/ws');
  final _adminKey = TextEditingController();
  final _globalKeyField = TextEditingController();
  final _passphrase = TextEditingController();

  bool _isAdmin = false;
  bool _enableE2E = false;
  bool _busy = false;
  String? _keystorePath;

  @override
  void dispose() {
    _username.dispose();
    _server.dispose();
    _adminKey.dispose();
    _globalKeyField.dispose();
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _pickKeystore() async {
    final r = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select keystore.dat',
      type: FileType.any,
      allowMultiple: false,
    );
    if (r == null || r.files.isEmpty) return;
    final path = r.files.single.path;
    if (path == null) return;
    setState(() => _keystorePath = path);
  }

  Future<void> _go() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);

    MarchatGlobalE2E? e2e;
    try {
      if (_enableE2E) {
        if (_globalKeyField.text.trim().isNotEmpty) {
          await const FlutterSecureStorage().write(
            key: 'global_e2e_key',
            value: _globalKeyField.text.trim(),
          );
        }

        // Same precedence as Go `initializeGlobalKey`: env wins over file-derived key.
        Uint8List? raw32;
        final env = Platform.environment['MARCHAT_GLOBAL_E2E_KEY'];
        if (env != null && env.trim().isNotEmpty) {
          raw32 = MarchatGlobalE2E.tryDecodeGlobalKeyBase64(env.trim());
          if (raw32 == null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('MARCHAT_GLOBAL_E2E_KEY is set but is not valid base64 32-byte key.'),
              ),
            );
            setState(() => _busy = false);
            return;
          }
        }

        if (raw32 == null && _globalKeyField.text.trim().isNotEmpty) {
          raw32 = MarchatGlobalE2E.tryDecodeGlobalKeyBase64(
            _globalKeyField.text.trim(),
          );
          if (raw32 == null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Global E2E key field must be base64 encoding of exactly 32 raw bytes.',
                ),
              ),
            );
            setState(() => _busy = false);
            return;
          }
        }

        if (raw32 == null) {
          final stored =
              await const FlutterSecureStorage().read(key: 'global_e2e_key');
          if (stored != null && stored.trim().isNotEmpty) {
            raw32 = MarchatGlobalE2E.tryDecodeGlobalKeyBase64(stored.trim());
          }
        }

        if (raw32 == null) {
          final ksPath = _keystorePath;
          if (ksPath == null || ksPath.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'E2E: set MARCHAT_GLOBAL_E2E_KEY, paste a base64 global key, '
                  'or choose keystore.dat and enter your passphrase (same as TUI).',
                ),
              ),
            );
            setState(() => _busy = false);
            return;
          }
          if (_passphrase.text.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Enter the keystore passphrase to unlock keystore.dat.'),
              ),
            );
            setState(() => _busy = false);
            return;
          }
          final file = File(ksPath);
          if (!file.existsSync()) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Keystore not found: $ksPath')),
            );
            setState(() => _busy = false);
            return;
          }
          try {
            final legacyPath = p.normalize(file.absolute.path);
            raw32 = await MarchatKeystore.unlockToGlobalKey32(
              fileBytes: await file.readAsBytes(),
              passphrase: _passphrase.text,
              keystorePathForLegacy: legacyPath,
            );
          } on MarchatKeystoreException catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$e')),
            );
            setState(() => _busy = false);
            return;
          }
        }

        e2e = MarchatGlobalE2E.fromRawKey32(raw32);
      }

      final cfg = MarchatClientConfig(
        username: _username.text.trim(),
        serverURL: _server.text.trim(),
        twentyFourHour: true,
        chatThemeId: 'modern',
      );

      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            config: cfg,
            e2e: e2e,
            isAdmin: _isAdmin,
            adminKey: _adminKey.text,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('marchat — connect'),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _server,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'ws://host:8080/ws',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Connect as admin'),
                  value: _isAdmin,
                  onChanged: (v) => setState(() => _isAdmin = v ?? false),
                ),
                if (_isAdmin)
                  TextFormField(
                    controller: _adminKey,
                    decoration: const InputDecoration(
                      labelText: 'Admin key',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text(
                    'Enable global E2E (ChaCha20-Poly1305, marchat wire format)',
                  ),
                  subtitle: const Text(
                    'Use the same key as other clients: MARCHAT_GLOBAL_E2E_KEY, '
                    'paste base64 key, or unlock the same keystore.dat + passphrase as the TUI.',
                  ),
                  value: _enableE2E,
                  onChanged: (v) => setState(() => _enableE2E = v ?? false),
                ),
                if (_enableE2E) ...[
                  TextFormField(
                    controller: _globalKeyField,
                    decoration: const InputDecoration(
                      labelText:
                          'Global E2E key (base64, 32 bytes) — optional if env / keystore',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pickKeystore,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: Text(
                            _keystorePath == null
                                ? 'Choose keystore.dat'
                                : p.basename(_keystorePath!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (_keystorePath != null)
                        IconButton(
                          tooltip: 'Clear keystore',
                          onPressed: _busy
                              ? null
                              : () => setState(() => _keystorePath = null),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  TextFormField(
                    controller: _passphrase,
                    decoration: const InputDecoration(
                      labelText: 'Keystore passphrase',
                      hintText: 'Same passphrase you use with the TUI keystore',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'If the TUI created your key, it lives in keystore.dat under the '
                    'client config directory (or cwd). Copy that file here and use the '
                    'same passphrase. MARCHAT_GLOBAL_E2E_KEY still overrides when set.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => SystemNavigator.pop(),
                      child: const Text('Exit'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _busy ? null : _go,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Connect'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'After connecting, use :theme / :themes and Ctrl+T for the same '
                  'built-in theme order as the marchat TUI (system → patriot → retro → modern).',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
