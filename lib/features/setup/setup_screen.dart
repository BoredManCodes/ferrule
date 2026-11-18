import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api/api_response.dart';
import '../../core/api/itflow_client.dart';
import '../../core/api/itflow_web_client.dart';
import '../../core/api/providers.dart';
import '../../core/auth/api_key_provisioning.dart';
import '../../core/storage/secure_store.dart';

/// How this device gets its API key.
enum _Mode { admin, code, key }

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _decryptPwController = TextEditingController();
  _Mode? _mode;
  SetupCode? _code;
  bool _busy = false;
  String? _busyStatus;
  bool _showPassword = false;
  bool _showApiKey = false;
  bool _showDecryptPw = false;
  String? _error;
  bool _notAdmin = false;

  @override
  void dispose() {
    _urlController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _apiKeyController.dispose();
    _decryptPwController.dispose();
    super.dispose();
  }

  void _pick(_Mode m) => setState(() {
        _mode = m;
        _error = null;
        _notAdmin = false;
      });

  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _SetupCodeScanner()),
    );
    _useCode(raw);
  }

  /// A picture of the QR code someone sent you (screenshot or saved image).
  Future<void> _pickPicture() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
    try {
      final capture = await scanner.analyzeImage(picked.path);
      final raw = capture?.barcodes
          .map((b) => b.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (raw == null) {
        setState(() => _error =
            'No QR code found in that picture. Try a clearer screenshot, or paste the code text instead.');
        return;
      }
      _useCode(raw);
    } catch (e) {
      setState(() => _error = 'Could not read that picture: $e');
    } finally {
      scanner.dispose();
    }
  }

  /// The setup code as text, e.g. from a message. The whole message can be
  /// pasted; the code is picked out of it.
  Future<void> _paste() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PasteDialog(
          initial: SetupCode.tryParse(clip) != null ? clip : ''),
    );
    _useCode(text);
  }

  void _useCode(String? raw) {
    if (raw == null || raw.trim().isEmpty || !mounted) return;
    final code = SetupCode.tryParse(raw);
    setState(() {
      _code = code;
      _error = code == null
          ? 'That isn\'t a Ferrule setup code. Ask your admin to make one in Ferrule under Settings > Set up a technician.'
          : null;
    });
  }

  Future<void> _connect() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notAdmin = false;
    });
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    try {
      Credentials creds;
      switch (_mode!) {
        case _Mode.admin:
          setState(() => _busyStatus = 'Signing in…');
          creds = await provisionCredentials(
            instanceUrl: _normalizeUrl(_urlController.text.trim()),
            email: email,
            password: password,
          );
        case _Mode.code:
          creds = _code!.toCredentials(webEmail: email, webPassword: password);
          if (creds.hasWebCreds) {
            setState(() => _busyStatus = 'Checking your login…');
            await ItflowWebClient(
                    baseUrl: creds.instanceUrl,
                    email: email,
                    password: password)
                .login();
          }
        case _Mode.key:
          final pw = _decryptPwController.text.trim();
          creds = Credentials(
            instanceUrl: _normalizeUrl(_urlController.text.trim()),
            apiKey: _apiKeyController.text.trim(),
            decryptPassword: pw.isEmpty ? null : pw,
            webEmail: email.isEmpty ? null : email,
            webPassword: password.isEmpty ? null : password,
          );
      }
      setState(() => _busyStatus = 'Verifying…');
      final client = ItflowClient(
        baseUrl: creds.instanceUrl,
        apiKey: creds.apiKey,
        decryptPassword: creds.decryptPassword,
      );
      final resp = await client.get('clients', 'read', query: {'limit': 1});
      if (!resp.success &&
          resp.message != null &&
          !resp.message!.contains('No resource')) {
        setState(() => _error = resp.message);
        return;
      }
      await ref.read(credentialsProvider.notifier).save(creds);
    } catch (e) {
      final msg = e is ApiException ? e.message : e.toString();
      setState(() {
        _error = msg;
        _notAdmin = _mode == _Mode.admin && msg.contains('isn\'t an admin');
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyStatus = null;
        });
      }
    }
  }

  String _normalizeUrl(String raw) {
    var u = raw;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      // Default to http for IP/port addresses (e.g. Tailscale, LAN), https otherwise.
      final isIpOrPort =
          RegExp(r'^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/|$)').hasMatch(u) ||
              u.contains(':');
      u = '${isIpOrPort ? 'http' : 'https'}://$u';
    }
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _mode == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _mode = null);
      },
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.shield_outlined,
                                size: 36, color: scheme.onPrimaryContainer),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Connect to ITFlow',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 20),
                        ...switch (_mode) {
                          null => _chooser(context),
                          _Mode.admin => _adminForm(context),
                          _Mode.code => _codeForm(context),
                          _Mode.key => _keyForm(context),
                        },
                        if (_mode != null) ..._footer(context),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => context.push('/privacy'),
                            icon: const Icon(Icons.policy_outlined, size: 16),
                            label: const Text('Privacy policy'),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
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
      ),
    );
  }

  // --- Step 1: which kind of account -------------------------------------

  List<Widget> _chooser(BuildContext context) {
    final muted = TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4);
    return [
      Text(
        'Ferrule talks to ITFlow with an API key. Only ITFlow admins can make '
        'API keys, so how you sign in depends on your account.',
        textAlign: TextAlign.center,
        style: muted,
      ),
      const SizedBox(height: 20),
      _ChoiceCard(
        icon: Icons.admin_panel_settings_outlined,
        title: 'I\'m an ITFlow admin',
        body: 'Sign in with your ITFlow email and password. Ferrule makes its '
            'own API key that acts as you and renews it before it expires.',
        onTap: () => _pick(_Mode.admin),
      ),
      const SizedBox(height: 12),
      _ChoiceCard(
        icon: Icons.qr_code_scanner,
        title: 'I have a setup code',
        body: 'Technicians: an admin makes you one in Ferrule under Settings > '
            'Set up a technician. Scan it, pick the picture, or paste the '
            'message they sent.',
        onTap: () => _pick(_Mode.code),
      ),
      const SizedBox(height: 12),
      _ChoiceCard(
        icon: Icons.key_outlined,
        title: 'I have an API key',
        body: 'Paste a key an admin made for you under Admin > API Keys, with '
            'its vault password.',
        onTap: () => _pick(_Mode.key),
      ),
    ];
  }

  // --- Step 2 forms --------------------------------------------------------

  Widget _back() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : () => setState(() => _mode = null),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Other ways to sign in'),
        ),
      );

  Widget _urlField() => TextFormField(
        controller: _urlController,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'ITFlow address',
          hintText: 'itflow.example.com',
          prefixIcon: Icon(Icons.link),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      );

  Widget _emailField({required bool required}) => TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: required ? 'Email' : 'Your ITFlow email',
          prefixIcon: const Icon(Icons.mail_outline),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      );

  Widget _passwordField({required bool required}) => TextFormField(
        controller: _passwordController,
        obscureText: !_showPassword,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) {
          if (!_busy) _connect();
        },
        decoration: InputDecoration(
          labelText: required ? 'Password' : 'Your ITFlow password',
          prefixIcon: const Icon(Icons.password),
          suffixIcon: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        validator: required
            ? (v) => (v == null || v.isEmpty) ? 'Required' : null
            : null,
      );

  Widget _note(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(height: 1.35)),
          ),
        ],
      ),
    );
  }

  List<Widget> _adminForm(BuildContext context) => [
        _back(),
        const SizedBox(height: 8),
        _urlField(),
        const SizedBox(height: 12),
        _emailField(required: true),
        const SizedBox(height: 12),
        _passwordField(required: true),
        const SizedBox(height: 8),
        _note('Your login stays on this phone in secure storage. Ferrule uses '
            'it to make and renew its API key, and for things ITFlow\'s API '
            'can\'t do yet: logging time, trips, expenses and payments. Two-'
            'factor sign-in on this account isn\'t supported.'),
      ];

  List<Widget> _codeForm(BuildContext context) {
    final code = _code;
    if (code == null) {
      return [
        _back(),
        const SizedBox(height: 8),
        Text(
          'Your admin makes the code in Ferrule under Settings > Set up a '
          'technician. Scan it off their screen, or if they sent it to you, '
          'pick the picture or paste the message.',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan with camera'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _pickPicture,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Pick picture'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _paste,
          icon: const Icon(Icons.content_paste),
          label: const Text('Paste code'),
        ),
      ];
    }
    return [
      _back(),
      const SizedBox(height: 8),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.verified_outlined),
        title: Text('Signing in as ${code.agentName}'),
        subtitle: Text(
            '${code.instanceUrl}\nKey works until ${DateFormat.yMMMd().format(code.expiresAt)}'),
        trailing: IconButton(
          tooltip: 'Use a different code',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() => _code = null),
        ),
      ),
      const SizedBox(height: 8),
      _emailField(required: false),
      const SizedBox(height: 12),
      _passwordField(required: false),
      const SizedBox(height: 8),
      _note('Optional, but needed for logging time, public notes, trips, '
          'expenses and payments, which ITFlow\'s API can\'t do yet. Ferrule '
          'can\'t renew this key itself; it reminds you a month before it '
          'runs out so you can get a new code.'),
    ];
  }

  List<Widget> _keyForm(BuildContext context) => [
        _back(),
        const SizedBox(height: 8),
        _urlField(),
        const SizedBox(height: 12),
        TextFormField(
          controller: _apiKeyController,
          obscureText: !_showApiKey,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'API key',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showApiKey = !_showApiKey),
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _decryptPwController,
          obscureText: !_showDecryptPw,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Vault password',
            helperText: 'Shown with the key when it was made · opens the Vault',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(
                  _showDecryptPw ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _showDecryptPw = !_showDecryptPw),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _emailField(required: false),
        const SizedBox(height: 12),
        _passwordField(required: false),
        const SizedBox(height: 8),
        _note('Email and password are optional; they unlock logging time, '
            'trips, expenses and payments. Ferrule can\'t renew a pasted key, '
            'so replace it before it expires.'),
      ];

  List<Widget> _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canConnect = _mode != _Mode.code || _code != null;
    return [
      if (_error != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
        ),
        if (_notAdmin) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _pick(_Mode.code),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Use a setup code from your admin'),
          ),
        ] else if (_mode == _Mode.key) ...[
          const SizedBox(height: 8),
          _note('Check the address (https://itflow.example.com, nothing after '
              'it), that the key was pasted with no spaces, and that this '
              'phone can open the address in a browser.'),
        ],
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _busy || !canConnect ? null : _connect,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.arrow_forward),
        label: Text(_busy ? (_busyStatus ?? 'Connecting…') : 'Connect'),
      ),
    ];
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(body,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant, height: 1.35)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen QR scanner that returns the first code it reads.
class _SetupCodeScanner extends StatefulWidget {
  const _SetupCodeScanner();
  @override
  State<_SetupCodeScanner> createState() => _SetupCodeScannerState();
}

class _SetupCodeScannerState extends State<_SetupCodeScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan setup code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              final raw = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .firstOrNull;
              if (raw == null) return;
              _done = true;
              Navigator.of(context).pop(raw);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Point the camera at the QR code on your admin\'s phone '
                '(Ferrule > Settings > Set up a technician).',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasteDialog extends StatefulWidget {
  final String initial;
  const _PasteDialog({required this.initial});
  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Paste setup code'),
        content: TextField(
          controller: _c,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Paste the whole message; Ferrule finds the code in it',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _c.text),
              child: const Text('Use code')),
        ],
      );
}
