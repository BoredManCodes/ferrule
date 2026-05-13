import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';

// ===========================================================================
// Providers
// ===========================================================================

final _listProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, module) async {
  await ref.watch(credentialsProvider.future);
  final client = requireClient(ref);
  const pageSize = 500;
  const maxItems = 50000;
  final all = <Map<String, dynamic>>[];
  var offset = 0;
  while (offset < maxItems) {
    final resp = await client
        .get(module, 'read', query: {'limit': pageSize, 'offset': offset});
    if (!resp.success) break;
    final rows = resp.rows;
    if (rows.isEmpty) break;
    all.addAll(rows);
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
  return all;
});

class _RowKey {
  final String module;
  final String idField;
  final int id;
  const _RowKey(this.module, this.idField, this.id);
  @override
  bool operator ==(Object other) =>
      other is _RowKey &&
      other.module == module &&
      other.idField == idField &&
      other.id == id;
  @override
  int get hashCode => Object.hash(module, idField, id);
}

final _rowProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, _RowKey>((ref, k) async {
  await ref.watch(credentialsProvider.future);
  final client = requireClient(ref);
  final resp =
      await client.get(k.module, 'read', query: {k.idField: k.id});
  if (!resp.success) return null;
  return resp.row;
});

// ===========================================================================
// Shared helpers
// ===========================================================================

final _df = DateFormat.yMMMd();

Widget? _kv(
  String label,
  dynamic value,
  IconData icon, {
  VoidCallback? onTap,
  Widget? trailing,
}) {
  final v = str(value);
  if (v == null) return null;
  return KeyValueTile(
    label: label,
    value: v,
    icon: icon,
    onTap: onTap,
    trailing: trailing,
  );
}

Widget? _kvDate(String label, dynamic value, IconData icon) {
  final d = toDate(value);
  if (d == null) return null;
  return KeyValueTile(label: label, value: _df.format(d), icon: icon);
}

Widget _section(String title, List<Widget?> tiles) {
  final nonNull = tiles.whereType<Widget>().toList();
  if (nonNull.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(title),
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: nonNull),
      ),
    ],
  );
}

Widget _expireChip(DateTime? expires) {
  if (expires == null) return const SizedBox.shrink();
  final now = DateTime.now();
  final days = expires.difference(now).inDays;
  Color color;
  String label;
  if (days < 0) {
    color = Colors.red;
    label = 'Expired';
  } else if (days < 30) {
    color = Colors.orange;
    label = 'Expires in ${days}d';
  } else if (days < 90) {
    color = Colors.amber.shade700;
    label = 'Expires in ${days}d';
  } else {
    color = Colors.green;
    label = 'Expires ${_df.format(expires)}';
  }
  return Chip(
    label: Text(label, style: TextStyle(fontSize: 11, color: color)),
    side: BorderSide(color: color),
    backgroundColor: color.withValues(alpha: 0.08),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
  );
}

Color _statusColor(String? status) {
  switch (status?.toLowerCase()) {
    case 'paid':
    case 'closed':
    case 'accepted':
      return Colors.green;
    case 'overdue':
    case 'expired':
      return Colors.red;
    case 'partial':
    case 'sent':
    case 'pending':
      return Colors.orange;
    case 'draft':
      return Colors.grey;
    case 'declined':
    case 'cancelled':
      return Colors.red.shade300;
    default:
      return Colors.blue;
  }
}

Widget _statusChip(String? status) {
  if (status == null || status.isEmpty) return const SizedBox.shrink();
  final c = _statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: c.withValues(alpha: 0.6)),
    ),
    child: Text(status,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
  );
}

Future<void> _open(String s) async {
  if (s.isEmpty) return;
  var u = s.trim();
  if (!u.contains('://')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri != null) await launchUrl(uri);
}

String _money(dynamic amount, [dynamic code]) {
  final v = toDouble(amount);
  if (v == null) return '';
  final cc = str(code);
  if (cc != null) {
    final f = NumberFormat.currency(name: cc, symbol: '');
    return '${f.format(v)} $cc';
  }
  return NumberFormat.simpleCurrency().format(v);
}

String _composePhone(dynamic countryCode, dynamic number, [dynamic ext]) {
  final cc = str(countryCode);
  final n = str(number);
  if (n == null) return '';
  var out = cc != null ? '+$cc $n' : n;
  final e = str(ext);
  if (e != null) out = '$out ext. $e';
  return out;
}

String? _composeAddress(Map<String, dynamic> r) {
  final parts = <String>[
    if (str(r['location_address']) != null) str(r['location_address'])!,
    [
      str(r['location_city']),
      str(r['location_state']),
      str(r['location_zip']),
    ].whereType<String>().join(', '),
    if (str(r['location_country']) != null) str(r['location_country'])!,
  ].where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  return parts.join('\n');
}

class _CopyButton extends StatelessWidget {
  final String value;
  const _CopyButton({required this.value});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy',
      icon: const Icon(Icons.copy, size: 18),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Copied'), duration: Duration(seconds: 1)));
      },
    );
  }
}

class _LongTextSection extends StatefulWidget {
  final String title;
  final String value;
  final bool monospace;
  final int collapsedLines;
  const _LongTextSection({
    required this.title,
    required this.value,
    this.monospace = false,
    this.collapsedLines = 6,
  });

  @override
  State<_LongTextSection> createState() => _LongTextSectionState();
}

class _LongTextSectionState extends State<_LongTextSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(widget.value).length + 1;
    final collapsible = lineCount > widget.collapsedLines;
    final style = TextStyle(
      fontFamily: widget.monospace ? 'monospace' : null,
      fontSize: 13,
      height: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          widget.title,
          trailing: _CopyButton(value: widget.value),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.value,
                  style: style,
                  maxLines:
                      collapsible && !_expanded ? widget.collapsedLines : null,
                  overflow: collapsible && !_expanded
                      ? TextOverflow.ellipsis
                      : TextOverflow.clip,
                ),
                if (collapsible)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? 'Show less' : 'Show more'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Generic list scaffold
// ===========================================================================

class _SearchList extends ConsumerStatefulWidget {
  final String module;
  final String title;
  final IconData icon;
  final String searchHint;
  final String Function(Map<String, dynamic>) searchHaystack;
  final String? archivedField;
  final Comparator<Map<String, dynamic>>? sort;
  final Widget Function(BuildContext, Map<String, dynamic>) buildItem;

  const _SearchList({
    required this.module,
    required this.title,
    required this.icon,
    required this.searchHint,
    required this.searchHaystack,
    required this.buildItem,
    this.archivedField,
    this.sort,
  });

  @override
  ConsumerState<_SearchList> createState() => _SearchListState();
}

class _SearchListState extends ConsumerState<_SearchList> {
  String _q = '';
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_listProvider(widget.module));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_listProvider(widget.module)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.searchHint,
              ),
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
            ),
          ),
          if (widget.archivedField != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                FilterChip(
                  label: const Text('Show archived'),
                  selected: _showArchived,
                  onSelected: (v) => setState(() => _showArchived = v),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(_listProvider(widget.module)),
              ),
              data: (rows) {
                var filtered = rows.where((r) {
                  if (widget.archivedField != null && !_showArchived) {
                    if (toDate(r[widget.archivedField!]) != null) return false;
                  }
                  if (_q.isEmpty) return true;
                  return widget.searchHaystack(r).toLowerCase().contains(_q);
                }).toList();
                if (widget.sort != null) filtered.sort(widget.sort!);
                if (filtered.isEmpty) {
                  return EmptyView(
                      icon: widget.icon, title: 'No ${widget.title}');
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(_listProvider(widget.module)),
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) => widget.buildItem(c, filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Generic detail scaffold
// ===========================================================================

typedef _SectionsBuilder = List<Widget> Function(
    BuildContext, WidgetRef, Map<String, dynamic>);

class _Detail extends ConsumerWidget {
  final String module;
  final String idField;
  final int id;
  final IconData icon;
  final String fallbackTitle;
  final String? Function(Map<String, dynamic>) titleFor;
  final String? Function(Map<String, dynamic>)? subtitleFor;
  final Widget? Function(BuildContext, Map<String, dynamic>)? headerTrailing;
  final List<Widget> Function(BuildContext, Map<String, dynamic>)?
      appBarActions;
  final _SectionsBuilder sectionsBuilder;

  const _Detail({
    required this.module,
    required this.idField,
    required this.id,
    required this.icon,
    required this.fallbackTitle,
    required this.titleFor,
    required this.sectionsBuilder,
    this.subtitleFor,
    this.headerTrailing,
    this.appBarActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = _RowKey(module, idField, id);
    final async = ref.watch(_rowProvider(k));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.value != null
            ? (titleFor(async.value!) ?? fallbackTitle)
            : fallbackTitle),
        actions: [
          ...?(async.value != null ? appBarActions?.call(context, async.value!) : null),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_rowProvider(k)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(_rowProvider(k))),
        data: (row) {
          if (row == null) {
            return const EmptyView(icon: Icons.search_off, title: 'Not found');
          }
          final subtitle = subtitleFor?.call(row);
          final trailing = headerTrailing?.call(context, row);
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(icon,
                          size: 28,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titleFor(row) ?? fallbackTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(subtitle,
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...sectionsBuilder(context, ref, row),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Documents
// ===========================================================================

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'documents',
        title: 'Documents',
        icon: Icons.description_outlined,
        searchHint: 'Search documents…',
        archivedField: 'document_archived_at',
        sort: (a, b) {
          final av = toDate(a['document_updated_at']) ?? DateTime(0);
          final bv = toDate(b['document_updated_at']) ?? DateTime(0);
          return bv.compareTo(av);
        },
        searchHaystack: (r) =>
            '${str(r['document_name']) ?? ''} ${str(r['document_description']) ?? ''}',
        buildItem: (c, r) {
          final fav = toBool(r['document_favorite']);
          final visible = toBool(r['document_client_visible']);
          return ListTile(
            onTap: () =>
                c.push('/documents/${toInt(r['document_id']) ?? 0}'),
            leading: const CircleAvatar(
                child: Icon(Icons.description_outlined)),
            title: Text(str(r['document_name']) ?? '(unnamed)'),
            subtitle: Text(str(r['document_description']) ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (visible)
                  const Icon(Icons.visibility_outlined, size: 16),
                if (fav)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.star, size: 16, color: Colors.amber),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
          );
        },
      );
}

class DocumentDetailScreen extends StatelessWidget {
  final int id;
  const DocumentDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'documents',
        idField: 'document_id',
        id: id,
        icon: Icons.description_outlined,
        fallbackTitle: 'Document',
        titleFor: (r) => str(r['document_name']),
        subtitleFor: (r) => str(r['document_description']),
        headerTrailing: (_, r) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (toBool(r['document_favorite']))
                const Icon(Icons.star, color: Colors.amber, size: 20),
              if (toBool(r['document_client_visible']))
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.visibility_outlined, size: 20),
                ),
            ],
          );
        },
        sectionsBuilder: (c, ref, r) {
          final content = str(r['document_content_raw']) ??
              str(r['document_content']);
          return [
            _section('Details', [
              _kv('Visible to client',
                  toBool(r['document_client_visible']) ? 'Yes' : 'No',
                  Icons.visibility_outlined),
              _kv('Folder ID', r['document_folder_id'], Icons.folder_outlined),
              _kv('Client ID', r['document_client_id'], Icons.business_outlined),
            ]),
            if (content != null) ...[
              _LongTextSection(title: 'Content', value: content),
            ],
            _section('Dates', [
              _kvDate('Created', r['document_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['document_updated_at'], Icons.update_outlined),
              _kvDate('Last viewed', r['document_accessed_at'],
                  Icons.visibility_outlined),
              _kvDate('Archived', r['document_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Domains
// ===========================================================================

class DomainsScreen extends StatelessWidget {
  const DomainsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'domains',
        title: 'Domains',
        icon: Icons.dns_outlined,
        searchHint: 'Search domains…',
        archivedField: 'domain_archived_at',
        sort: (a, b) => (str(a['domain_name']) ?? '')
            .toLowerCase()
            .compareTo((str(b['domain_name']) ?? '').toLowerCase()),
        searchHaystack: (r) =>
            '${str(r['domain_name']) ?? ''} ${str(r['domain_registrar']) ?? ''} ${str(r['domain_description']) ?? ''}',
        buildItem: (c, r) {
          final expires = toDate(r['domain_expire']);
          final name = str(r['domain_name']);
          return ListTile(
            onTap: () => c.push('/domains/${toInt(r['domain_id']) ?? 0}'),
            leading: const CircleAvatar(child: Icon(Icons.public)),
            title: Text(name ?? '(unnamed)'),
            subtitle: Text([
              str(r['domain_registrar']),
              if (expires != null) 'Expires ${_df.format(expires)}',
            ].whereType<String>().join(' • ')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _expireChip(expires),
                IconButton(
                  tooltip: 'Open',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: name == null ? null : () => _open(name),
                ),
              ],
            ),
          );
        },
      );
}

class DomainDetailScreen extends StatelessWidget {
  final int id;
  const DomainDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'domains',
        idField: 'domain_id',
        id: id,
        icon: Icons.public,
        fallbackTitle: 'Domain',
        titleFor: (r) => str(r['domain_name']),
        subtitleFor: (r) => str(r['domain_description']),
        headerTrailing: (_, r) => _expireChip(toDate(r['domain_expire'])),
        appBarActions: (c, r) => [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: () {
              final n = str(r['domain_name']);
              if (n != null) _open(n);
            },
          ),
        ],
        sectionsBuilder: (c, ref, r) {
          return [
            _section('Registration', [
              _kv('Registrar', r['domain_registrar'], Icons.business_outlined),
              _kvDate('Expires', r['domain_expire'], Icons.event_outlined),
              _kv('IP', r['domain_ip'], Icons.lan_outlined,
                  trailing: str(r['domain_ip']) == null
                      ? null
                      : _CopyButton(value: str(r['domain_ip'])!)),
            ]),
            _section('Hosting', [
              _kv('Web host', r['domain_webhost'], Icons.storage_outlined),
              _kv('DNS host', r['domain_dnshost'], Icons.dns_outlined),
              _kv('Mail host', r['domain_mailhost'], Icons.alternate_email),
            ]),
            if (str(r['domain_name_servers']) != null)
              _LongTextSection(
                title: 'Name servers',
                value: str(r['domain_name_servers'])!,
                monospace: true,
                collapsedLines: 4,
              ),
            if (str(r['domain_mail_servers']) != null)
              _LongTextSection(
                title: 'Mail servers',
                value: str(r['domain_mail_servers'])!,
                monospace: true,
                collapsedLines: 4,
              ),
            if (str(r['domain_txt']) != null)
              _LongTextSection(
                title: 'TXT records',
                value: str(r['domain_txt'])!,
                monospace: true,
                collapsedLines: 4,
              ),
            if (str(r['domain_notes']) != null)
              _LongTextSection(
                title: 'Notes',
                value: str(r['domain_notes'])!,
              ),
            if (str(r['domain_raw_whois']) != null)
              _LongTextSection(
                title: 'WHOIS',
                value: str(r['domain_raw_whois'])!,
                monospace: true,
                collapsedLines: 4,
              ),
            _section('Dates', [
              _kvDate(
                  'Created', r['domain_created_at'], Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['domain_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['domain_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Locations
// ===========================================================================

class LocationsScreen extends StatelessWidget {
  const LocationsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'locations',
        title: 'Locations',
        icon: Icons.location_on_outlined,
        searchHint: 'Search locations…',
        archivedField: 'location_archived_at',
        searchHaystack: (r) => [
          str(r['location_name']),
          str(r['location_address']),
          str(r['location_city']),
          str(r['location_country']),
        ].whereType<String>().join(' '),
        buildItem: (c, r) {
          final primary = toBool(r['location_primary']);
          return ListTile(
            onTap: () =>
                c.push('/locations/${toInt(r['location_id']) ?? 0}'),
            leading: CircleAvatar(
              backgroundColor: primary
                  ? Theme.of(c).colorScheme.primaryContainer
                  : null,
              child: Icon(
                primary ? Icons.star : Icons.location_on_outlined,
                color: primary
                    ? Theme.of(c).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
            title: Text(str(r['location_name']) ?? '(unnamed)'),
            subtitle: Text([
              str(r['location_address']),
              str(r['location_city']),
              str(r['location_country']),
            ].whereType<String>().join(', ')),
            trailing: const Icon(Icons.chevron_right),
          );
        },
      );
}

class LocationDetailScreen extends StatelessWidget {
  final int id;
  const LocationDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'locations',
        idField: 'location_id',
        id: id,
        icon: Icons.location_on_outlined,
        fallbackTitle: 'Location',
        titleFor: (r) => str(r['location_name']),
        subtitleFor: (r) => str(r['location_description']),
        headerTrailing: (_, r) => toBool(r['location_primary'])
            ? Chip(
                avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                label: const Text('Primary', style: TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            : null,
        sectionsBuilder: (c, ref, r) {
          final address = _composeAddress(r);
          final phone = _composePhone(
              r['location_phone_country_code'],
              r['location_phone'],
              r['location_phone_extension']);
          final fax = _composePhone(
              r['location_fax_country_code'], r['location_fax']);
          return [
            _section('Address', [
              if (address != null)
                KeyValueTile(
                  label: 'Address',
                  value: address,
                  icon: Icons.place_outlined,
                  onTap: () => _open(
                      'https://maps.google.com/?q=${Uri.encodeQueryComponent(address.replaceAll('\n', ', '))}'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                ),
            ]),
            _section('Contact', [
              if (phone.isNotEmpty)
                KeyValueTile(
                  label: 'Phone',
                  value: phone,
                  icon: Icons.phone_outlined,
                  onTap: () =>
                      launchUrl(Uri.parse('tel:${str(r['location_phone'])}')),
                ),
              if (fax.isNotEmpty)
                KeyValueTile(
                  label: 'Fax',
                  value: fax,
                  icon: Icons.print_outlined,
                ),
              _kv('Hours', r['location_hours'], Icons.access_time),
              _kv('Contact ID', r['location_contact_id'],
                  Icons.contacts_outlined),
              _kv('Client ID', r['location_client_id'],
                  Icons.business_outlined),
            ]),
            if (str(r['location_notes']) != null)
              _LongTextSection(
                  title: 'Notes', value: str(r['location_notes'])!),
            _section('Dates', [
              _kvDate('Created', r['location_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['location_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['location_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Networks
// ===========================================================================

class NetworksScreen extends StatelessWidget {
  const NetworksScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'networks',
        title: 'Networks',
        icon: Icons.lan_outlined,
        searchHint: 'Search networks…',
        archivedField: 'network_archived_at',
        searchHaystack: (r) =>
            '${str(r['network_name']) ?? ''} ${str(r['network']) ?? ''} ${str(r['network_description']) ?? ''}',
        buildItem: (c, r) {
          final vlan = str(r['network_vlan']);
          return ListTile(
            onTap: () => c.push('/networks/${toInt(r['network_id']) ?? 0}'),
            leading: const CircleAvatar(child: Icon(Icons.lan_outlined)),
            title: Text(str(r['network_name']) ?? '(unnamed)'),
            subtitle: Text([
              str(r['network']),
              if (vlan != null) 'VLAN $vlan',
            ].whereType<String>().join(' • ')),
            trailing: const Icon(Icons.chevron_right),
          );
        },
      );
}

class NetworkDetailScreen extends StatelessWidget {
  final int id;
  const NetworkDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'networks',
        idField: 'network_id',
        id: id,
        icon: Icons.lan_outlined,
        fallbackTitle: 'Network',
        titleFor: (r) => str(r['network_name']),
        subtitleFor: (r) => str(r['network_description']),
        sectionsBuilder: (c, ref, r) {
          final subnet = str(r['network']) ?? str(r['network_subnet']);
          return [
            _section('Addressing', [
              if (subnet != null)
                KeyValueTile(
                  label: 'Subnet',
                  value: subnet,
                  icon: Icons.share_outlined,
                  trailing: _CopyButton(value: subnet),
                ),
              _kv('VLAN', r['network_vlan'], Icons.layers_outlined),
              _kv('Gateway', r['network_gateway'], Icons.router_outlined),
            ]),
            _section('DNS / DHCP', [
              _kv('Primary DNS', r['network_primary_dns'], Icons.dns_outlined),
              _kv('Secondary DNS', r['network_secondary_dns'],
                  Icons.dns_outlined),
              _kv('DHCP range', r['network_dhcp_range'],
                  Icons.swap_horiz_outlined),
            ]),
            _section('Associations', [
              _kv('Location ID', r['network_location_id'],
                  Icons.location_on_outlined),
              _kv('Client ID', r['network_client_id'],
                  Icons.business_outlined),
            ]),
            if (str(r['network_notes']) != null)
              _LongTextSection(
                  title: 'Notes', value: str(r['network_notes'])!),
            _section('Dates', [
              _kvDate('Created', r['network_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['network_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['network_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Software
// ===========================================================================

class SoftwareScreen extends StatelessWidget {
  const SoftwareScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'software',
        title: 'Software',
        icon: Icons.apps_outlined,
        searchHint: 'Search software…',
        archivedField: 'software_archived_at',
        searchHaystack: (r) =>
            '${str(r['software_name']) ?? ''} ${str(r['software_version']) ?? ''} ${str(r['software_type']) ?? ''}',
        buildItem: (c, r) {
          final expires = toDate(r['software_expire']);
          return ListTile(
            onTap: () =>
                c.push('/software/${toInt(r['software_id']) ?? 0}'),
            leading: const CircleAvatar(child: Icon(Icons.apps_outlined)),
            title: Text(str(r['software_name']) ?? '(unnamed)'),
            subtitle: Text([
              str(r['software_version']),
              str(r['software_type']),
            ].whereType<String>().join(' • ')),
            trailing: expires != null
                ? _expireChip(expires)
                : const Icon(Icons.chevron_right),
          );
        },
      );
}

class SoftwareDetailScreen extends StatelessWidget {
  final int id;
  const SoftwareDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'software',
        idField: 'software_id',
        id: id,
        icon: Icons.apps_outlined,
        fallbackTitle: 'Software',
        titleFor: (r) {
          final n = str(r['software_name']);
          final v = str(r['software_version']);
          if (n == null) return null;
          return v == null ? n : '$n $v';
        },
        subtitleFor: (r) => str(r['software_description']),
        headerTrailing: (_, r) => _expireChip(toDate(r['software_expire'])),
        sectionsBuilder: (c, ref, r) {
          final key = str(r['software_key']);
          return [
            _section('Details', [
              _kv('Type', r['software_type'], Icons.category_outlined),
              _kv('Version', r['software_version'], Icons.tag),
              _kv('License type', r['software_license_type'],
                  Icons.assignment_outlined),
              _kv('Seats', r['software_seats'], Icons.people_outline),
            ]),
            _section('License', [
              if (key != null)
                KeyValueTile(
                  label: 'Key',
                  value: key,
                  icon: Icons.vpn_key_outlined,
                  trailing: _CopyButton(value: key),
                ),
              _kv('Purchase reference', r['software_purchase_reference'],
                  Icons.receipt_outlined),
              _kvDate('Purchased', r['software_purchase'],
                  Icons.shopping_cart_outlined),
              _kvDate(
                  'Expires', r['software_expire'], Icons.event_outlined),
            ]),
            _section('Associations', [
              _kv('Vendor ID', r['software_vendor_id'], Icons.store_outlined),
              _kv('Client ID', r['software_client_id'],
                  Icons.business_outlined),
            ]),
            if (str(r['software_notes']) != null)
              _LongTextSection(
                  title: 'Notes', value: str(r['software_notes'])!),
            _section('Dates', [
              _kvDate('Created', r['software_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['software_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['software_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Vendors
// ===========================================================================

class VendorsScreen extends StatelessWidget {
  const VendorsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'vendors',
        title: 'Vendors',
        icon: Icons.store_outlined,
        searchHint: 'Search vendors…',
        archivedField: 'vendor_archived_at',
        searchHaystack: (r) =>
            '${str(r['vendor_name']) ?? ''} ${str(r['vendor_description']) ?? ''} ${str(r['vendor_email']) ?? ''} ${str(r['vendor_contact_name']) ?? ''}',
        buildItem: (c, r) {
          return ListTile(
            onTap: () => c.push('/vendors/${toInt(r['vendor_id']) ?? 0}'),
            leading: const CircleAvatar(child: Icon(Icons.store_outlined)),
            title: Text(str(r['vendor_name']) ?? '(unnamed)'),
            subtitle: Text([
              str(r['vendor_contact_name']),
              str(r['vendor_email']),
            ].whereType<String>().join(' • ')),
            trailing: const Icon(Icons.chevron_right),
          );
        },
      );
}

class VendorDetailScreen extends StatelessWidget {
  final int id;
  const VendorDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'vendors',
        idField: 'vendor_id',
        id: id,
        icon: Icons.store_outlined,
        fallbackTitle: 'Vendor',
        titleFor: (r) => str(r['vendor_name']),
        subtitleFor: (r) => str(r['vendor_description']),
        sectionsBuilder: (c, ref, r) {
          final phone = _composePhone(r['vendor_phone_country_code'],
              r['vendor_phone'], r['vendor_extension']);
          final email = str(r['vendor_email']);
          final website = str(r['vendor_website']);
          return [
            _section('Contact', [
              _kv('Contact name', r['vendor_contact_name'],
                  Icons.person_outline),
              if (phone.isNotEmpty)
                KeyValueTile(
                  label: 'Phone',
                  value: phone,
                  icon: Icons.phone_outlined,
                  onTap: () =>
                      launchUrl(Uri.parse('tel:${str(r['vendor_phone'])}')),
                ),
              if (email != null)
                KeyValueTile(
                  label: 'Email',
                  value: email,
                  icon: Icons.mail_outline,
                  onTap: () => launchUrl(Uri.parse('mailto:$email')),
                ),
              if (website != null)
                KeyValueTile(
                  label: 'Website',
                  value: website,
                  icon: Icons.public,
                  onTap: () => _open(website),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                ),
              _kv('Hours', r['vendor_hours'], Icons.access_time),
            ]),
            _section('Account', [
              _kv('Vendor code', r['vendor_code'], Icons.qr_code_2),
              _kv('Account number', r['vendor_account_number'],
                  Icons.badge_outlined),
              _kv('SLA', r['vendor_sla'], Icons.support_agent),
              _kv('Client ID', r['vendor_client_id'],
                  Icons.business_outlined),
            ]),
            if (str(r['vendor_notes']) != null)
              _LongTextSection(
                  title: 'Notes', value: str(r['vendor_notes'])!),
            _section('Dates', [
              _kvDate('Created', r['vendor_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['vendor_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['vendor_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Products
// ===========================================================================

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'products',
        title: 'Products',
        icon: Icons.shopping_bag_outlined,
        searchHint: 'Search products…',
        archivedField: 'product_archived_at',
        searchHaystack: (r) =>
            '${str(r['product_name']) ?? ''} ${str(r['product_code']) ?? ''} ${str(r['product_description']) ?? ''}',
        buildItem: (c, r) {
          final amount = _money(r['product_price'], r['product_currency_code']);
          return ListTile(
            onTap: () =>
                c.push('/products/${toInt(r['product_id']) ?? 0}'),
            leading: const CircleAvatar(
                child: Icon(Icons.shopping_bag_outlined)),
            title: Text(str(r['product_name']) ?? '(unnamed)'),
            subtitle: Text([
              str(r['product_code']),
              str(r['product_type']),
              str(r['product_description']),
            ].whereType<String>().join(' • ')),
            trailing: amount.isEmpty
                ? const Icon(Icons.chevron_right)
                : Text(amount,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
      );
}

class ProductDetailScreen extends StatelessWidget {
  final int id;
  const ProductDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'products',
        idField: 'product_id',
        id: id,
        icon: Icons.shopping_bag_outlined,
        fallbackTitle: 'Product',
        titleFor: (r) => str(r['product_name']),
        subtitleFor: (r) => str(r['product_type']),
        headerTrailing: (c, r) {
          final amount = _money(r['product_price'], r['product_currency_code']);
          if (amount.isEmpty) return null;
          return Text(amount,
              style: Theme.of(c).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ));
        },
        sectionsBuilder: (c, ref, r) {
          return [
            _section('Details', [
              _kv('Code', r['product_code'], Icons.qr_code_2),
              _kv('Type', r['product_type'], Icons.category_outlined),
              _kv('Location', r['product_location'],
                  Icons.location_on_outlined),
              _kv('Currency', r['product_currency_code'],
                  Icons.attach_money_outlined),
              _kv('Tax ID', r['product_tax_id'], Icons.percent_outlined),
              _kv('Category ID', r['product_category_id'],
                  Icons.label_outline),
            ]),
            if (str(r['product_description']) != null)
              _LongTextSection(
                title: 'Description',
                value: str(r['product_description'])!,
              ),
            _section('Dates', [
              _kvDate('Created', r['product_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['product_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['product_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Invoices
// ===========================================================================

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'invoices',
        title: 'Invoices',
        icon: Icons.receipt_long_outlined,
        searchHint: 'Search invoices…',
        archivedField: 'invoice_archived_at',
        sort: (a, b) {
          final av = toDate(a['invoice_date']) ?? DateTime(0);
          final bv = toDate(b['invoice_date']) ?? DateTime(0);
          return bv.compareTo(av);
        },
        searchHaystack: (r) => [
          str(r['invoice_prefix']),
          str(r['invoice_number']),
          str(r['invoice_scope']),
          str(r['invoice_status']),
        ].whereType<String>().join(' '),
        buildItem: (c, r) {
          final amount =
              _money(r['invoice_amount'], r['invoice_currency_code']);
          final date = toDate(r['invoice_date']);
          final due = toDate(r['invoice_due']);
          final overdue = due != null &&
              due.isBefore(DateTime.now()) &&
              (str(r['invoice_status']) ?? '').toLowerCase() != 'paid';
          return ListTile(
            onTap: () =>
                c.push('/invoices/${toInt(r['invoice_id']) ?? 0}'),
            leading: const CircleAvatar(
                child: Icon(Icons.receipt_long_outlined)),
            title: Text(
                '${str(r['invoice_prefix']) ?? ''}${str(r['invoice_number']) ?? ''}'),
            subtitle: Row(
              children: [
                if (date != null)
                  Text(_df.format(date),
                      style: Theme.of(c).textTheme.bodySmall),
                if (date != null) const SizedBox(width: 8),
                _statusChip(overdue
                    ? 'Overdue'
                    : str(r['invoice_status'])),
              ],
            ),
            trailing: amount.isEmpty
                ? const Icon(Icons.chevron_right)
                : Text(amount,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
      );
}

class InvoiceDetailScreen extends StatelessWidget {
  final int id;
  const InvoiceDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'invoices',
        idField: 'invoice_id',
        id: id,
        icon: Icons.receipt_long_outlined,
        fallbackTitle: 'Invoice',
        titleFor: (r) {
          final p = str(r['invoice_prefix']) ?? '';
          final n = str(r['invoice_number']) ?? '';
          final t = '$p$n';
          return t.isEmpty ? null : t;
        },
        subtitleFor: (r) => str(r['invoice_scope']),
        headerTrailing: (_, r) => _statusChip(str(r['invoice_status'])),
        sectionsBuilder: (c, ref, r) {
          final cur = str(r['invoice_currency_code']);
          return [
            _section('Amounts', [
              _kv('Total', _money(r['invoice_amount'], cur),
                  Icons.attach_money_outlined),
              _kv('Discount', _money(r['invoice_discount_amount'], cur),
                  Icons.percent_outlined),
              _kv('Credit applied', _money(r['invoice_credit_amount'], cur),
                  Icons.account_balance_wallet_outlined),
              _kv('Currency', cur, Icons.money_outlined),
            ]),
            _section('Dates', [
              _kvDate(
                  'Issued', r['invoice_date'], Icons.calendar_month_outlined),
              _kvDate('Due', r['invoice_due'], Icons.event_outlined),
              _kvDate('Created', r['invoice_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['invoice_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['invoice_archived_at'],
                  Icons.archive_outlined),
            ]),
            _section('Associations', [
              _kv('Client ID', r['invoice_client_id'],
                  Icons.business_outlined),
              _kv('Category ID', r['invoice_category_id'],
                  Icons.label_outline),
              _kv('Recurring invoice ID', r['invoice_recurring_invoice_id'],
                  Icons.repeat),
              if (str(r['invoice_url_key']) != null)
                KeyValueTile(
                  label: 'Public URL key',
                  value: str(r['invoice_url_key'])!,
                  icon: Icons.link,
                  trailing: _CopyButton(value: str(r['invoice_url_key'])!),
                ),
            ]),
            if (str(r['invoice_note']) != null)
              _LongTextSection(
                  title: 'Note', value: str(r['invoice_note'])!),
          ];
        },
      );
}

// ===========================================================================
// Quotes
// ===========================================================================

class QuotesScreen extends StatelessWidget {
  const QuotesScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'quotes',
        title: 'Quotes',
        icon: Icons.request_quote_outlined,
        searchHint: 'Search quotes…',
        archivedField: 'quote_archived_at',
        sort: (a, b) {
          final av = toDate(a['quote_date']) ?? DateTime(0);
          final bv = toDate(b['quote_date']) ?? DateTime(0);
          return bv.compareTo(av);
        },
        searchHaystack: (r) => [
          str(r['quote_prefix']),
          str(r['quote_number']),
          str(r['quote_scope']),
          str(r['quote_status']),
        ].whereType<String>().join(' '),
        buildItem: (c, r) {
          final amount = _money(r['quote_amount'], r['quote_currency_code']);
          final date = toDate(r['quote_date']);
          return ListTile(
            onTap: () => c.push('/quotes/${toInt(r['quote_id']) ?? 0}'),
            leading: const CircleAvatar(
                child: Icon(Icons.request_quote_outlined)),
            title: Text(
                '${str(r['quote_prefix']) ?? ''}${str(r['quote_number']) ?? ''}'),
            subtitle: Row(
              children: [
                if (date != null)
                  Text(_df.format(date),
                      style: Theme.of(c).textTheme.bodySmall),
                if (date != null) const SizedBox(width: 8),
                _statusChip(str(r['quote_status'])),
              ],
            ),
            trailing: amount.isEmpty
                ? const Icon(Icons.chevron_right)
                : Text(amount,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
      );
}

class QuoteDetailScreen extends StatelessWidget {
  final int id;
  const QuoteDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'quotes',
        idField: 'quote_id',
        id: id,
        icon: Icons.request_quote_outlined,
        fallbackTitle: 'Quote',
        titleFor: (r) {
          final t =
              '${str(r['quote_prefix']) ?? ''}${str(r['quote_number']) ?? ''}';
          return t.isEmpty ? null : t;
        },
        subtitleFor: (r) => str(r['quote_scope']),
        headerTrailing: (_, r) => _statusChip(str(r['quote_status'])),
        sectionsBuilder: (c, ref, r) {
          final cur = str(r['quote_currency_code']);
          return [
            _section('Amounts', [
              _kv('Total', _money(r['quote_amount'], cur),
                  Icons.attach_money_outlined),
              _kv('Discount', _money(r['quote_discount_amount'], cur),
                  Icons.percent_outlined),
              _kv('Currency', cur, Icons.money_outlined),
            ]),
            _section('Dates', [
              _kvDate(
                  'Issued', r['quote_date'], Icons.calendar_month_outlined),
              _kvDate('Expires', r['quote_expire'], Icons.event_outlined),
              _kvDate('Created', r['quote_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['quote_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['quote_archived_at'],
                  Icons.archive_outlined),
            ]),
            _section('Associations', [
              _kv('Client ID', r['quote_client_id'], Icons.business_outlined),
              _kv('Category ID', r['quote_category_id'], Icons.label_outline),
              if (str(r['quote_url_key']) != null)
                KeyValueTile(
                  label: 'Public URL key',
                  value: str(r['quote_url_key'])!,
                  icon: Icons.link,
                  trailing: _CopyButton(value: str(r['quote_url_key'])!),
                ),
            ]),
            if (str(r['quote_note']) != null)
              _LongTextSection(title: 'Note', value: str(r['quote_note'])!),
          ];
        },
      );
}

// ===========================================================================
// Expenses
// ===========================================================================

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'expenses',
        title: 'Expenses',
        icon: Icons.payments_outlined,
        searchHint: 'Search expenses…',
        archivedField: 'expense_archived_at',
        sort: (a, b) {
          final av = toDate(a['expense_date']) ?? DateTime(0);
          final bv = toDate(b['expense_date']) ?? DateTime(0);
          return bv.compareTo(av);
        },
        searchHaystack: (r) =>
            '${str(r['expense_description']) ?? ''} ${str(r['expense_reference']) ?? ''} ${str(r['expense_payment_method']) ?? ''}',
        buildItem: (c, r) {
          final amount =
              _money(r['expense_amount'], r['expense_currency_code']);
          final date = toDate(r['expense_date']);
          return ListTile(
            onTap: () =>
                c.push('/expenses/${toInt(r['expense_id']) ?? 0}'),
            leading:
                const CircleAvatar(child: Icon(Icons.payments_outlined)),
            title:
                Text(str(r['expense_description']) ?? '(no description)'),
            subtitle: Text([
              if (date != null) _df.format(date),
              str(r['expense_payment_method']),
              str(r['expense_reference']),
            ].whereType<String>().join(' • ')),
            trailing: amount.isEmpty
                ? const Icon(Icons.chevron_right)
                : Text(amount,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        },
      );
}

class ExpenseDetailScreen extends StatelessWidget {
  final int id;
  const ExpenseDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'expenses',
        idField: 'expense_id',
        id: id,
        icon: Icons.payments_outlined,
        fallbackTitle: 'Expense',
        titleFor: (r) => str(r['expense_description']),
        subtitleFor: (r) {
          final d = toDate(r['expense_date']);
          return d != null ? _df.format(d) : null;
        },
        headerTrailing: (c, r) {
          final amount =
              _money(r['expense_amount'], r['expense_currency_code']);
          if (amount.isEmpty) return null;
          return Text(amount,
              style: Theme.of(c).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ));
        },
        sectionsBuilder: (c, ref, r) {
          final receipt = str(r['expense_receipt']);
          return [
            _section('Details', [
              _kv('Amount',
                  _money(r['expense_amount'], r['expense_currency_code']),
                  Icons.attach_money_outlined),
              _kvDate(
                  'Date', r['expense_date'], Icons.calendar_month_outlined),
              _kv('Reference', r['expense_reference'], Icons.tag),
              _kv('Payment method', r['expense_payment_method'],
                  Icons.credit_card_outlined),
              if (receipt != null)
                KeyValueTile(
                  label: 'Receipt',
                  value: receipt,
                  icon: Icons.receipt_outlined,
                  onTap: () => _open(receipt),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                ),
            ]),
            _section('Associations', [
              _kv('Vendor ID', r['expense_vendor_id'], Icons.store_outlined),
              _kv('Client ID', r['expense_client_id'],
                  Icons.business_outlined),
              _kv('Category ID', r['expense_category_id'],
                  Icons.label_outline),
              _kv('Account ID', r['expense_account_id'],
                  Icons.account_balance_outlined),
            ]),
            _section('Dates', [
              _kvDate('Created', r['expense_created_at'],
                  Icons.add_circle_outline),
              _kvDate(
                  'Updated', r['expense_updated_at'], Icons.update_outlined),
              _kvDate('Archived', r['expense_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}

// ===========================================================================
// Certificates
// ===========================================================================

class CertificatesScreen extends StatelessWidget {
  const CertificatesScreen({super.key});
  @override
  Widget build(BuildContext context) => _SearchList(
        module: 'certificates',
        title: 'Certificates',
        icon: Icons.workspace_premium_outlined,
        searchHint: 'Search certificates…',
        archivedField: 'certificate_archived_at',
        sort: (a, b) {
          final av = toDate(a['certificate_expire']) ?? DateTime(2100);
          final bv = toDate(b['certificate_expire']) ?? DateTime(2100);
          return av.compareTo(bv);
        },
        searchHaystack: (r) =>
            '${str(r['certificate_name']) ?? ''} ${str(r['certificate_domain']) ?? ''} ${str(r['certificate_issued_by']) ?? ''}',
        buildItem: (c, r) {
          final expires = toDate(r['certificate_expire']);
          return ListTile(
            onTap: () =>
                c.push('/certificates/${toInt(r['certificate_id']) ?? 0}'),
            leading: const CircleAvatar(
                child: Icon(Icons.workspace_premium_outlined)),
            title: Text(str(r['certificate_name']) ?? '(unnamed)'),
            subtitle: Text([
              str(r['certificate_domain']),
              str(r['certificate_issued_by']),
            ].whereType<String>().join(' • ')),
            trailing: _expireChip(expires),
          );
        },
      );
}

class CertificateDetailScreen extends StatelessWidget {
  final int id;
  const CertificateDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Detail(
        module: 'certificates',
        idField: 'certificate_id',
        id: id,
        icon: Icons.workspace_premium_outlined,
        fallbackTitle: 'Certificate',
        titleFor: (r) => str(r['certificate_name']),
        subtitleFor: (r) => str(r['certificate_description']),
        headerTrailing: (_, r) =>
            _expireChip(toDate(r['certificate_expire'])),
        sectionsBuilder: (c, ref, r) {
          return [
            _section('Details', [
              _kv('Common name / domain', r['certificate_domain'],
                  Icons.public),
              _kv('Issued by', r['certificate_issued_by'],
                  Icons.verified_user_outlined),
              _kvDate('Expires', r['certificate_expire'],
                  Icons.event_outlined),
              _kv('Domain ID', r['certificate_domain_id'], Icons.dns_outlined),
              _kv('Client ID', r['certificate_client_id'],
                  Icons.business_outlined),
            ]),
            if (str(r['certificate_public_key']) != null)
              _LongTextSection(
                title: 'Public key',
                value: str(r['certificate_public_key'])!,
                monospace: true,
                collapsedLines: 6,
              ),
            if (str(r['certificate_notes']) != null)
              _LongTextSection(
                  title: 'Notes', value: str(r['certificate_notes'])!),
            _section('Dates', [
              _kvDate('Created', r['certificate_created_at'],
                  Icons.add_circle_outline),
              _kvDate('Updated', r['certificate_updated_at'],
                  Icons.update_outlined),
              _kvDate('Archived', r['certificate_archived_at'],
                  Icons.archive_outlined),
            ]),
          ];
        },
      );
}
