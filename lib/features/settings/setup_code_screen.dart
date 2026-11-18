import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_response.dart';
import '../../core/api/itflow_web_client.dart';
import '../../core/api/providers.dart';
import '../../core/auth/api_key_provisioning.dart';
import '../expenses/expense_form_data.dart' show NamedOption;

/// Admins: make a setup code so a technician's app can connect without an
/// admin account. Creates an API key acting as that technician (Admin >
/// API Keys shows it) and shows it as a QR code to scan on their phone.
class SetupCodeScreen extends ConsumerStatefulWidget {
  const SetupCodeScreen({super.key});

  @override
  ConsumerState<SetupCodeScreen> createState() => _SetupCodeScreenState();
}

class _SetupCodeScreenState extends ConsumerState<SetupCodeScreen> {
  List<NamedOption>? _agents;
  NamedOption? _picked;
  SetupCode? _code;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    final creds = ref.read(credentialsProvider).value;
    if (creds == null || !creds.hasWebCreds) {
      setState(() => _error =
          'Sign in with your ITFlow email and password first (Settings > Web Session).');
      return;
    }
    try {
      final web = ItflowWebClient(
          baseUrl: creds.instanceUrl,
          email: creds.webEmail!,
          password: creds.webPassword!);
      final agents = await web.fetchApiKeyAgents();
      if (mounted) setState(() => _agents = agents);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : '$e');
      }
    }
  }

  Future<void> _make() async {
    final creds = ref.read(credentialsProvider).value!;
    final agent = _picked!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await createSetupCode(creds,
          agentId: agent.id, agentName: agent.name);
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('Set up a technician')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (code == null) ...[
            Text(
              'Only ITFlow admins can make API keys, so a technician can\'t '
              'sign in to Ferrule on their own. Make them a setup code here: '
              'it creates a key that acts as them, with their role and client '
              'access, and they scan it on the Ferrule sign-in screen.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_agents == null && _error == null)
              const Center(child: CircularProgressIndicator()),
            if (_agents != null)
              DropdownButtonFormField<int>(
                initialValue: _picked?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Technician',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                items: [
                  for (final a in _agents!)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() =>
                    _picked = _agents!.firstWhere((a) => a.id == v)),
              ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy || _picked == null ? null : _make,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.qr_code_2),
              label: const Text('Make setup code'),
            ),
          ] else ...[
            Center(
              child: Text(code.agentName,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(
                  data: code.encode(),
                  size: 280,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'On their phone: open Ferrule, pick "I have a setup code", and '
              'scan this. Then they add their own ITFlow email and password '
              'for logging time, trips and expenses.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Anyone who scans this code gets in as ${code.agentName} until '
                '${DateFormat.yMMMd().format(code.expiresAt)}. Show it only to '
                'them. To cut it off, revoke the key named "Ferrule setup code - '
                '${code.agentName}" under Admin > API Keys.',
                style: TextStyle(color: scheme.onErrorContainer, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            Text('Not in the same room?',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Send it by text or chat instead. They can paste the message, '
              'or save the picture and pick it from their gallery. The code '
              'stays in that conversation, so ask them to delete it once '
              'they are signed in.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _shareText(context, code),
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send as text'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _sharePicture(context, code),
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Send picture'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ],
      ),
    );
  }
}

Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null ? null : box.localToGlobal(Offset.zero) & box.size;
}

Future<void> _shareText(BuildContext context, SetupCode code) async {
  await Share.share(
    code.shareText(),
    subject: 'Ferrule setup code',
    sharePositionOrigin: _shareOrigin(context),
  );
}

/// The QR code as a PNG on white with a quiet zone, so gallery scanners
/// read it (a transparent background reads as black on black).
Future<void> _sharePicture(BuildContext context, SetupCode code) async {
  const size = 900.0, pad = 60.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, size + pad * 2, size + pad * 2),
      Paint()..color = Colors.white);
  canvas.translate(pad, pad);
  QrPainter(
    data: code.encode(),
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
    dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square, color: Colors.black),
  ).paint(canvas, const Size(size, size));
  final image = await recorder
      .endRecording()
      .toImage((size + pad * 2).toInt(), (size + pad * 2).toInt());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) return;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/ferrule-setup-code.png');
  await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
  if (!context.mounted) return;
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'image/png')],
    text: 'Ferrule setup code for ${code.agentName}. In Ferrule choose '
        '"I have a setup code", then "Pick picture". Delete this once you are '
        'signed in.',
    sharePositionOrigin: _shareOrigin(context),
  );
}
