import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets.dart';

/// Privacy policy view. Tries to fetch the latest PRIVACY.md from GitHub so
/// users see the current policy even on an older app build; falls back to
/// the asset bundled at compile time if the network call fails (offline,
/// GitHub down, blocked, etc.).
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  static const _rawUrl =
      'https://raw.githubusercontent.com/BoredManCodes/ferrule/main/PRIVACY.md';

  late Future<_PolicyLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PolicyLoad> _load() async {
    final bundled = await rootBundle.loadString('PRIVACY.md');
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        responseType: ResponseType.plain,
      ));
      final resp = await dio.get<String>(_rawUrl);
      final remote = resp.data?.trim();
      if (remote != null && remote.isNotEmpty) {
        return _PolicyLoad(text: remote, source: _Source.remote);
      }
    } catch (_) {
      // Fall through to bundled.
    }
    return _PolicyLoad(text: bundled, source: _Source.bundled);
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy policy'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _retry,
          ),
        ],
      ),
      body: FutureBuilder<_PolicyLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return ErrorView(
              error: snapshot.error ?? 'Could not load policy',
              onRetry: _retry,
            );
          }
          final load = snapshot.data!;
          return Column(
            children: [
              if (load.source == _Source.bundled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Showing the version bundled with this app — couldn\'t reach GitHub for the latest.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Markdown(
                  data: load.text,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  selectable: true,
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      launchUrl(Uri.parse(href),
                          mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _Source { remote, bundled }

class _PolicyLoad {
  final String text;
  final _Source source;
  const _PolicyLoad({required this.text, required this.source});
}
