// Agent banners: ITFlow's notes along the top of agents' pages, for every
// client or for one client. There's no API for them, so this reads what the
// agent pages render (which already applies the server's rules: start/end
// times, who hid which, Urgent first) and drives the same forms the web UI
// uses. Instances older than ITFlow database 3.7.2 have no banners; every
// call here then comes back empty.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/itflow_web_client.dart';
import '../../core/api/providers.dart';

enum BannerTone { info, warning, danger }

BannerTone _tone(String? s) => switch (s) {
      'warning' => BannerTone.warning,
      'danger' => BannerTone.danger,
      _ => BannerTone.info,
    };

String toneLabel(BannerTone t) => switch (t) {
      BannerTone.info => 'Notice',
      BannerTone.warning => 'Heads up',
      BannerTone.danger => 'Urgent',
    };

/// A banner as an agent page shows it.
class AgentBanner {
  final int id;
  final String title;
  final String? clientName; // set when it's for one client
  final String? bodyHtml;
  final BannerTone tone;
  final bool hideable; // Urgent ones can't be hidden

  const AgentBanner({
    required this.id,
    required this.title,
    required this.tone,
    this.clientName,
    this.bodyHtml,
    this.hideable = true,
  });
}

/// A row in a list of banners to manage (client menu or Admin > Agent
/// Banners).
class BannerListItem {
  final int id;
  final String title;
  final BannerTone tone;
  final String? status; // "Showing", "Scheduled", "Ended" ...
  final String? forWho; // "Every client" or the client's name
  final String? when;

  const BannerListItem({
    required this.id,
    required this.title,
    required this.tone,
    this.status,
    this.forWho,
    this.when,
  });
}

/// What a client page says about banners: the ones showing, whether this
/// agent may add/change the client's banners, and the client's own list.
class ClientBannerState {
  final List<AgentBanner> showing;
  final bool canEdit;
  final List<BannerListItem> clientBanners;
  const ClientBannerState(
      {this.showing = const [],
      this.canEdit = false,
      this.clientBanners = const []});
}

List<AgentBanner> parseShowingBanners(String html) {
  final doc = html_parser.parse(html);
  final out = <AgentBanner>[];
  final seen = <int>{};
  for (final el in doc.querySelectorAll('[data-agent-banner]')) {
    final id = int.tryParse(el.attributes['data-agent-banner'] ?? '');
    if (id == null || !seen.add(id)) continue;
    final cls = el.attributes['class'] ?? '';
    final tone = _tone(RegExp(r'\bis-(info|warning|danger)\b')
        .firstMatch(cls)
        ?.group(1));
    final titleEl = el.querySelector('.itflow-agent-banner-title');
    final forEl = titleEl?.querySelector('.itflow-agent-banner-for');
    final clientName = forEl?.text.trim();
    forEl?.remove();
    out.add(AgentBanner(
      id: id,
      title: titleEl?.text.trim() ?? '',
      clientName: (clientName == null || clientName.isEmpty) ? null : clientName,
      bodyHtml: el.querySelector('.itflow-agent-banner-body')?.innerHtml,
      tone: tone,
      hideable: el.querySelector('[data-agent-banner-hide]') != null,
    ));
  }
  return out;
}

ClientBannerState parseClientBannerState(String html) {
  final doc = html_parser.parse(html);
  final canEdit = doc
      .querySelectorAll('[data-modal-url]')
      .any((a) => (a.attributes['data-modal-url'] ?? '')
          .contains('agent_banner/agent_banner_add.php'));
  final list = <BannerListItem>[];
  final seen = <int>{};
  for (final a in doc.querySelectorAll('[data-modal-url*="agent_banner_edit.php"]')) {
    final m = RegExp(r'[?&]id=(\d+)').firstMatch(a.attributes['data-modal-url']!);
    if (m == null) continue;
    final id = int.parse(m.group(1)!);
    if (!seen.add(id)) continue;
    final dot = a.querySelector('.itflow-announcement-dot');
    final tone = _tone(RegExp(r'\bis-(info|warning|danger)\b')
        .firstMatch(dot?.attributes['class'] ?? '')
        ?.group(1));
    final text = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final scheduled = text.endsWith('(scheduled)');
    list.add(BannerListItem(
      id: id,
      title: scheduled ? text.replaceFirst(RegExp(r'\s*\(scheduled\)$'), '') : text,
      tone: tone,
      status: scheduled ? 'Scheduled' : null,
    ));
  }
  return ClientBannerState(
    showing: parseShowingBanners(html),
    canEdit: canEdit,
    clientBanners: list,
  );
}

List<BannerListItem> parseAdminBannerList(String html) {
  final doc = html_parser.parse(html);
  final out = <BannerListItem>[];
  for (final row in doc.querySelectorAll('tr[data-agent-banner-row]')) {
    final id = int.tryParse(row.attributes['data-agent-banner-row'] ?? '');
    if (id == null) continue;
    final link = row.querySelector('a[data-modal-url*="agent_banner_edit.php"]');
    final dot = row.querySelector('.itflow-announcement-dot');
    final cells = row.querySelectorAll('td');
    String cellText(int i) => i < cells.length
        ? cells[i].text.replaceAll(RegExp(r'\s+'), ' ').trim()
        : '';
    final from = cellText(2), until = cellText(3);
    out.add(BannerListItem(
      id: id,
      title: link?.text.trim() ?? 'Banner #$id',
      tone: _tone(RegExp(r'\bis-(info|warning|danger)\b')
          .firstMatch(dot?.attributes['class'] ?? '')
          ?.group(1)),
      status: row.querySelector('.badge.rounded-pill')?.text.trim(),
      forWho: cellText(1).isEmpty ? null : cellText(1),
      when: [from, until].where((s) => s.isNotEmpty).join(' → '),
    ));
  }
  return out;
}

/// The "New Banner" / "Editing banner" form as ITFlow fills it in.
class BannerForm {
  final int? id; // null for a new one
  final String title;
  final String body;
  final String tone; // info | warning | danger
  final List<({String value, String label})> tones;
  final int clientId; // 0 = every client
  final bool clientFixed;
  final List<({int id, String name})> clients; // when it can be picked
  final String startsAt; // yyyy-MM-ddTHH:mm or ''
  final String endsAt;
  final bool archived;

  const BannerForm({
    this.id,
    required this.title,
    required this.body,
    required this.tone,
    required this.tones,
    required this.clientId,
    required this.clientFixed,
    required this.clients,
    required this.startsAt,
    required this.endsAt,
    required this.archived,
  });
}

BannerForm parseBannerForm(String html, {int? id}) {
  final doc = html_parser.parse(html);
  String val(String name) =>
      doc.querySelector('input[name="$name"]')?.attributes['value'] ?? '';
  final toneSel = doc.querySelector('select[name="tone"]');
  final tones = <({String value, String label})>[];
  var tone = 'info';
  for (final o in toneSel?.querySelectorAll('option') ?? <dom.Element>[]) {
    final v = o.attributes['value'] ?? '';
    tones.add((value: v, label: o.text.trim()));
    if (o.attributes.containsKey('selected')) tone = v;
  }
  if (tones.isEmpty) {
    tones.addAll(const [
      (value: 'info', label: 'Notice'),
      (value: 'warning', label: 'Heads up'),
      (value: 'danger', label: 'Urgent'),
    ]);
  }
  final clientSel = doc.querySelector('select[name="client_id"]');
  final clients = <({int id, String name})>[];
  var clientId = 0;
  if (clientSel != null) {
    for (final o in clientSel.querySelectorAll('option')) {
      final cid = int.tryParse(o.attributes['value'] ?? '');
      if (cid == null) continue;
      clients.add((id: cid, name: o.text.trim()));
      if (o.attributes.containsKey('selected')) clientId = cid;
    }
  } else {
    clientId = int.tryParse(val('client_id')) ?? 0;
  }
  return BannerForm(
    id: id,
    title: val('title'),
    body: doc.querySelector('textarea[name="body"]')?.text ?? '',
    tone: tone,
    tones: tones,
    clientId: clientId,
    clientFixed: clientSel == null,
    clients: clients,
    startsAt: val('starts_at'),
    endsAt: val('ends_at'),
    archived: doc.querySelector('a[href*="restore_agent_banner="]') != null,
  );
}

class AgentBannerRepository {
  final ItflowWebClient web;
  AgentBannerRepository(this.web);

  /// Every-client banners, as any agent page shows them.
  Future<List<AgentBanner>> globalBanners() async =>
      parseShowingBanners(await web.fetchAgentHtml('agent/clients.php'));

  /// A client's page: every-client and that client's banners, plus whether
  /// this agent may change the client's banners.
  Future<ClientBannerState> forClient(int clientId) async => parseClientBannerState(
      await web.fetchAgentHtml('agent/client_overview.php',
          query: {'client_id': clientId}));

  /// Admin > Agent Banners. Null when this account isn't an admin.
  Future<List<BannerListItem>?> adminList({bool archived = false}) async {
    final html = await web.fetchAgentHtml('admin/agent_banners.php',
        query: archived ? {'show': 'archived'} : null);
    if (html.contains('does not have admin access') ||
        !html.contains('agent_banner')) {
      return null;
    }
    return parseAdminBannerList(html);
  }

  Future<BannerForm> loadForm({int? id, int? clientId}) async {
    final html = id == null
        ? await web.fetchModalHtml('agent/modals/agent_banner/agent_banner_add.php',
            query: {if (clientId != null) 'client_id': clientId})
        : await web.fetchModalHtml('agent/modals/agent_banner/agent_banner_edit.php',
            query: {'id': id, if (clientId != null) 'client_id': clientId});
    if (html.contains('That banner is gone')) {
      throw StateError('That banner is gone.');
    }
    return parseBannerForm(html, id: id);
  }

  Future<void> save({
    int? id,
    required String title,
    required String body,
    required String tone,
    required int clientId,
    required String startsAt,
    required String endsAt,
  }) =>
      web.postAgentForm({
        if (id == null) 'add_agent_banner': '1' else 'edit_agent_banner': '1',
        if (id != null) 'announcement_id': id,
        'title': title,
        'body': body,
        'tone': tone,
        'client_id': clientId,
        'starts_at': startsAt,
        'ends_at': endsAt,
      });

  Future<void> hide(int id) => web.postAgentQuiet({'hide_agent_banner': id});
  // ITFlow flashes "archived" and "deleted" in red even when they worked.
  Future<void> archive(int id) =>
      web.agentGetAction({'archive_agent_banner': id}, checkFlash: false);
  Future<void> restore(int id) => web.agentGetAction({'restore_agent_banner': id});
  Future<void> delete(int id) =>
      web.agentGetAction({'delete_agent_banner': id}, checkFlash: false);
}

final agentBannerRepositoryProvider = Provider<AgentBannerRepository?>((ref) {
  final web = ref.watch(itflowWebClientProvider);
  return web == null ? null : AgentBannerRepository(web);
});

final globalBannersProvider =
    FutureProvider.autoDispose<List<AgentBanner>>((ref) async {
  await ref.watch(credentialsProvider.future);
  final repo = ref.watch(agentBannerRepositoryProvider);
  if (repo == null) return const [];
  try {
    return await repo.globalBanners();
  } catch (_) {
    return const [];
  }
});

final clientBannersProvider = FutureProvider.autoDispose
    .family<ClientBannerState, int>((ref, clientId) async {
  await ref.watch(credentialsProvider.future);
  final repo = ref.watch(agentBannerRepositoryProvider);
  if (repo == null || clientId <= 0) return const ClientBannerState();
  try {
    return await repo.forClient(clientId);
  } catch (_) {
    return const ClientBannerState();
  }
});

final adminBannersProvider = FutureProvider.autoDispose
    .family<List<BannerListItem>?, bool>((ref, archived) async {
  await ref.watch(credentialsProvider.future);
  final repo = ref.watch(agentBannerRepositoryProvider);
  if (repo == null) return null;
  return repo.adminList(archived: archived);
});

void invalidateBanners(WidgetRef ref) {
  ref.invalidate(globalBannersProvider);
  ref.invalidate(clientBannersProvider);
  ref.invalidate(adminBannersProvider);
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// The banners an agent page would show: every-client ones, plus the
/// client's when [clientId] is given. Renders nothing when there are none.
class AgentBannerStrip extends ConsumerStatefulWidget {
  final int? clientId;
  const AgentBannerStrip({super.key, this.clientId});

  @override
  ConsumerState<AgentBannerStrip> createState() => _AgentBannerStripState();
}

class _AgentBannerStripState extends ConsumerState<AgentBannerStrip> {
  final _hidden = <int>{};

  @override
  Widget build(BuildContext context) {
    final cid = widget.clientId;
    final banners = (cid != null && cid > 0)
        ? ref.watch(clientBannersProvider(cid)).value?.showing
        : ref.watch(globalBannersProvider).value;
    final list = (banners ?? const <AgentBanner>[])
        .where((b) => !_hidden.contains(b.id))
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in list)
          AgentBannerCard(
            banner: b,
            onHide: b.hideable
                ? () async {
                    setState(() => _hidden.add(b.id));
                    try {
                      await ref.read(agentBannerRepositoryProvider)?.hide(b.id);
                    } catch (_) {/* shown again next load */}
                  }
                : null,
          ),
      ],
    );
  }
}

class AgentBannerCard extends StatelessWidget {
  final AgentBanner banner;
  final VoidCallback? onHide;
  const AgentBannerCard({super.key, required this.banner, this.onHide});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (Color bg, Color fg, IconData icon) = switch (banner.tone) {
      BannerTone.danger => (
          const Color(0xFFDC3545),
          Colors.white,
          Icons.error_outline
        ),
      BannerTone.warning => (
          dark ? const Color(0xFF4D3A00) : const Color(0xFFFFF3CD),
          dark ? const Color(0xFFFFE69C) : const Color(0xFF664D03),
          Icons.warning_amber_rounded
        ),
      BannerTone.info => (
          dark ? const Color(0xFF032830) : const Color(0xFFCFF4FC),
          dark ? const Color(0xFF6EDFF6) : const Color(0xFF055160),
          Icons.info_outline
        ),
    };
    final urgent = banner.tone == BannerTone.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.fromLTRB(12, urgent ? 12 : 10, 4, urgent ? 12 : 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, color: fg, size: urgent ? 24 : 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      banner.title,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: urgent ? 16 : 14,
                      ),
                    ),
                    if (banner.clientName != null)
                      Text(banner.clientName!,
                          style: TextStyle(
                              color: fg.withValues(alpha: 0.8), fontSize: 12)),
                  ],
                ),
                if (banner.bodyHtml != null && banner.bodyHtml!.trim().isNotEmpty)
                  Html(
                    data: banner.bodyHtml,
                    style: {
                      'body': Style(
                        margin: Margins.zero,
                        padding: HtmlPaddings.only(top: 4),
                        color: fg,
                        fontSize: FontSize(13),
                      ),
                      'a': Style(
                          color: fg, textDecoration: TextDecoration.underline),
                    },
                    onLinkTap: (url, _, __) {
                      if (url != null) {
                        launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
              ],
            ),
          ),
          if (onHide != null)
            IconButton(
              tooltip: 'Hide - it comes back if it is changed',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, color: fg, size: 18),
              onPressed: onHide,
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }
}
