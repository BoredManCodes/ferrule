import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/itflow_client.dart';
import '../../core/api/providers.dart';
import '../../core/storage/secure_store.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _decryptPwController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _showApiKey = false;
  bool _showDecryptPw = false;
  bool _showPassword = false;
  bool _vaultExpanded = false;
  bool _agentExpanded = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _decryptPwController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final url = _normalizeUrl(_urlController.text.trim());
    final key = _apiKeyController.text.trim();
    final pw = _decryptPwController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final client = ItflowClient(
      baseUrl: url,
      apiKey: key,
      decryptPassword: pw.isEmpty ? null : pw,
    );
    try {
      final resp = await client.get('clients', 'read', query: {'limit': 1});
      if (!resp.success && resp.message != null) {
        setState(() => _error = resp.message);
        return;
      }
      await ref.read(credentialsProvider.notifier).save(
            Credentials(
              instanceUrl: url,
              apiKey: key,
              decryptPassword: pw.isEmpty ? null : pw,
              webEmail: email.isEmpty ? null : email,
              webPassword: password.isEmpty ? null : password,
            ),
          );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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
    return Scaffold(
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
                      const SizedBox(height: 8),
                      Text(
                        'Just the instance URL and API key are required. The other fields unlock the vault and labour timer — you can fill them later in Settings.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 24),
                      _SectionLabel('Required', scheme: scheme),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Instance URL',
                          hintText: 'itflow.example.com',
                          prefixIcon: Icon(Icons.link),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _apiKeyController,
                        obscureText: !_showApiKey,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          helperText:
                              'Admin Settings → API Keys in ITFlow web UI',
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(_showApiKey
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () =>
                                setState(() => _showApiKey = !_showApiKey),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),
                      _ExpandableSection(
                        title: 'Vault decrypt password',
                        subtitle:
                            'Optional · unlocks saved login credentials in the Vault tab',
                        icon: Icons.lock_outline,
                        expanded: _vaultExpanded,
                        onToggle: () =>
                            setState(() => _vaultExpanded = !_vaultExpanded),
                        children: [
                          Text(
                            'When you created your API key in ITFlow, you set an additional '
                            '"decrypt password" — that\'s the password that encrypts the '
                            'credential entries (logins, MFA secrets) on the server. The app '
                            'needs it to read and write those entries; without it, the Vault '
                            'tab stays locked but everything else still works.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _decryptPwController,
                            obscureText: !_showDecryptPw,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Decrypt Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_showDecryptPw
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () => setState(
                                    () => _showDecryptPw = !_showDecryptPw),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ExpandableSection(
                        title: 'Agent login (email + password)',
                        subtitle:
                            'Optional · required to log time to tickets from the Labour Timer',
                        icon: Icons.account_circle_outlined,
                        expanded: _agentExpanded,
                        onToggle: () =>
                            setState(() => _agentExpanded = !_agentExpanded),
                        children: [
                          Text(
                            'The ITFlow v1 API doesn\'t expose endpoints for logging time on a ticket — that '
                            'feature only exists in the web UI. To make the timer submit hours back to '
                            'ITFlow, the app signs in as you in the background (using these credentials), '
                            'grabs a CSRF token, and posts the reply exactly like the website would.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber,
                                    size: 16, color: scheme.tertiary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '2FA on this account isn\'t supported by the automation. '
                                    'Stored in OS-level secure storage; never sent anywhere except your instance.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(height: 1.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Agent Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Agent Password',
                              prefixIcon: const Icon(Icons.password),
                              suffixIcon: IconButton(
                                icon: Icon(_showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: scheme.onErrorContainer, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: scheme.onErrorContainer),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy ? null : _connect,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward),
                        label: Text(_busy ? 'Connecting…' : 'Connect'),
                      ),
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
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final ColorScheme scheme;
  const _SectionLabel(this.text, {required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class _ExpandableSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _ExpandableSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    )),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
