import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/providers.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../clients/client_model.dart';
import '../clients/client_repository.dart';
import '../contacts/contact_model.dart';
import '../contacts/contact_repository.dart';
import '../expenses/expense_repository.dart';
import '../tickets/ticket_model.dart';
import '../tickets/ticket_repository.dart';

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

/// Invalidates the cached list for the given read-only module (e.g. 'expenses'),
/// forcing the next watch to refetch. Used by sibling features (like the
/// expense create form) so newly-added rows show up immediately.
void invalidateModuleList(WidgetRef ref, String module) {
  ref.invalidate(_listProvider(module));
}

/// Line items belonging to a single invoice, in display order.
final _invoiceItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, invoiceId) =>
        _fetchItems(ref, module: 'invoice_items', idField: 'invoice_id', id: invoiceId));

/// Line items belonging to a single quote, in display order.
final _quoteItemsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, int>((ref, quoteId) =>
        _fetchItems(ref, module: 'quote_items', idField: 'quote_id', id: quoteId));

Future<List<Map<String, dynamic>>> _fetchItems(
  Ref ref, {
  required String module,
  required String idField,
  required int id,
}) async {
  await ref.watch(credentialsProvider.future);
  final client = requireClient(ref);
  const pageSize = 200;
  final out = <Map<String, dynamic>>[];
  var offset = 0;
  while (true) {
    final resp = await client.get(module, 'read', query: {
      idField: id,
      'limit': pageSize,
      'offset': offset,
    });
    if (!resp.success) break;
    final rows = resp.rows;
    if (rows.isEmpty) break;
    out.addAll(rows);
    if (rows.length < pageSize) break;
    offset += pageSize;
  }
  return out;
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
// Name resolution — turns linked IDs (client_id, vendor_id, ...) into names
// by piggy-backing on the cached _listProvider for the target module. The
// list provider is autoDispose but stays alive while any detail screen is
// watching it, so navigating between detail rows only fetches each module
// once.
// ===========================================================================

class _NamesKey {
  final String module;
  final String idField;
  final String nameField;
  const _NamesKey(this.module, this.idField, this.nameField);
  @override
  bool operator ==(Object other) =>
      other is _NamesKey &&
      other.module == module &&
      other.idField == idField &&
      other.nameField == nameField;
  @override
  int get hashCode => Object.hash(module, idField, nameField);
}

final _namesProvider = FutureProvider.autoDispose
    .family<Map<int, String>, _NamesKey>((ref, k) async {
  final rows = await ref.watch(_listProvider(k.module).future);
  final out = <int, String>{};
  for (final r in rows) {
    final id = toInt(r[k.idField]);
    if (id == null || id == 0) continue;
    final name = str(r[k.nameField]);
    if (name != null) out[id] = name;
  }
  return out;
});

const _clientNames =
    _NamesKey('clients', 'client_id', 'client_name');
const _vendorNames =
    _NamesKey('vendors', 'vendor_id', 'vendor_name');
const _contactNames =
    _NamesKey('contacts', 'contact_id', 'contact_name');
const _locationNames =
    _NamesKey('locations', 'location_id', 'location_name');
const _domainNames =
    _NamesKey('domains', 'domain_id', 'domain_name');

/// Scraped from the web admin's "New Expense" modal — gives us name lookups
/// for expense categories + accounts (which the v1 REST API doesn't expose).
/// Returns empty maps when web credentials are missing or the scrape fails,
/// so callers can degrade gracefully to "#<id>".
final _expenseAdminLookupsProvider = FutureProvider.autoDispose<
    ({Map<int, String> categories, Map<int, String> accounts})>((ref) async {
  try {
    final form = await ref.watch(expenseAddFormProvider.future);
    return (
      categories: {for (final o in form.categories) o.id: o.name},
      accounts: {for (final o in form.accounts) o.id: o.name},
    );
  } catch (_) {
    return (
      categories: const <int, String>{},
      accounts: const <int, String>{},
    );
  }
});

/// Builds a KeyValueTile for foreign-key ids using a pre-fetched lookup map.
/// Used for category/account fields where the lookup source isn't a generic
/// REST module list ([[_kvLookup]]) but a scraped admin-form options list.
Widget? _kvFromMap(
  String label,
  dynamic id,
  IconData icon,
  Map<int, String> map,
) {
  final i = toInt(id);
  if (i == null || i == 0) return null;
  final resolved = map[i];
  return KeyValueTile(
    label: label,
    value: resolved ?? '#$i',
    icon: icon,
  );
}

/// Renders a KeyValueTile that resolves a foreign-key id to the target
/// entity's name, optionally making the row tappable to navigate to its
/// detail screen. Falls back to `#<id>` while loading or if the row is
/// missing/archived/unreadable.
Widget? _kvLookup(
  BuildContext context,
  WidgetRef ref,
  String label,
  dynamic id,
  IconData icon, {
  required _NamesKey names,
  String? route,
}) {
  final i = toInt(id);
  if (i == null || i == 0) return null;
  final async = ref.watch(_namesProvider(names));
  final resolved = async.value?[i];
  final display = resolved ?? '#$i';
  return KeyValueTile(
    label: label,
    value: display,
    icon: icon,
    onTap: route == null ? null : () => context.push('$route/$i'),
    trailing: route == null
        ? null
        : const Icon(Icons.chevron_right, size: 18),
  );
}

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

/// Returns the configured ITFlow instance URL with any trailing slash stripped,
/// or null if no credentials are stored. Used to compose URLs that the API
/// returns as bare filenames or relative paths (e.g. expense receipt files).
String? _instanceRoot(WidgetRef ref) {
  final url = ref.read(credentialsProvider).value?.instanceUrl;
  if (url == null || url.isEmpty) return null;
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
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
  final Widget? floatingActionButton;

  const _SearchList({
    required this.module,
    required this.title,
    required this.icon,
    required this.searchHint,
    required this.searchHaystack,
    required this.buildItem,
    this.archivedField,
    this.sort,
    this.floatingActionButton,
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
      floatingActionButton: widget.floatingActionButton,
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
              _kvLookup(c, ref, 'Client', r['document_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
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
              _kvLookup(c, ref, 'Contact', r['location_contact_id'],
                  Icons.contacts_outlined,
                  names: _contactNames, route: '/contacts'),
              _kvLookup(c, ref, 'Client', r['location_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
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
              _kvLookup(c, ref, 'Location', r['network_location_id'],
                  Icons.location_on_outlined,
                  names: _locationNames, route: '/locations'),
              _kvLookup(c, ref, 'Client', r['network_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
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
              _kvLookup(c, ref, 'Vendor', r['software_vendor_id'],
                  Icons.store_outlined,
                  names: _vendorNames, route: '/vendors'),
              _kvLookup(c, ref, 'Client', r['software_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
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
            _section('Details', [
              _kv('Account Number', r['vendor_account_number'],
                  Icons.fingerprint),
              _kv('Account Manager', r['vendor_contact_name'],
                  Icons.person_outline),
              _kvLookup(c, ref, 'Client', r['vendor_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
            ]),
            _section('Support', [
              if (phone.isNotEmpty)
                KeyValueTile(
                  label: 'Support Phone',
                  value: phone,
                  icon: Icons.phone_outlined,
                  onTap: () =>
                      launchUrl(Uri.parse('tel:${str(r['vendor_phone'])}')),
                ),
              _kv('Support Hours', r['vendor_hours'], Icons.event_outlined),
              if (email != null)
                KeyValueTile(
                  label: 'Support Email',
                  value: email,
                  icon: Icons.mail_outline,
                  onTap: () => launchUrl(Uri.parse('mailto:$email')),
                ),
              if (website != null)
                KeyValueTile(
                  label: 'Support Website',
                  value: website,
                  icon: Icons.public,
                  onTap: () => _open(website),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                ),
              _kv('SLA', r['vendor_sla'], Icons.handshake_outlined),
              _kv('Pin / Code', r['vendor_code'], Icons.vpn_key_outlined),
            ]),
            if (str(r['vendor_notes']) != null)
              _LongTextSection(
                  title: 'Notes', value: str(r['vendor_notes'])!),
            _VendorRelations(vendorId: toInt(r['vendor_id']) ?? 0),
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

/// Renders related-entity sections for a vendor. ITFlow's schema technically
/// has `asset_vendor_id` and `credential_vendor_id`, but the web UI doesn't
/// surface those as primary vendor attributes (they're marked WIP), so this
/// only shows the relations the web UI actually treats as first-class:
/// contacts and software (licenses).
class _VendorRelations extends ConsumerWidget {
  final int vendorId;
  const _VendorRelations({required this.vendorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);
    final softwareAsync = ref.watch(_listProvider('software'));

    final contacts = contactsAsync.value
            ?.where((c) => c.vendorId == vendorId)
            .toList() ??
        const <Contact>[];
    final software = softwareAsync.value
            ?.where((r) => toInt(r['software_vendor_id']) == vendorId)
            .toList() ??
        const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _relatedContacts(context, contacts, contactsAsync.isLoading),
        _relatedSoftware(context, software, softwareAsync.isLoading),
      ],
    );
  }

  Widget _relatedContacts(
      BuildContext context, List<Contact> items, bool loading) {
    if (!loading && items.isEmpty) return const SizedBox.shrink();
    return _relatedCard(
      title: 'Contacts',
      count: items.length,
      loading: loading && items.isEmpty,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(items[i].name ?? '(unnamed)'),
              subtitle: Text([
                items[i].title,
                items[i].email,
              ]
                  .map((s) => s?.toString().trim() ?? '')
                  .where((s) => s.isNotEmpty)
                  .join(' • ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/contacts/${items[i].id}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _relatedSoftware(BuildContext context,
      List<Map<String, dynamic>> items, bool loading) {
    if (!loading && items.isEmpty) return const SizedBox.shrink();
    return _relatedCard(
      title: 'Software',
      count: items.length,
      loading: loading && items.isEmpty,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.apps_outlined),
              title: Text(str(items[i]['software_name']) ?? '(unnamed)'),
              subtitle: Text([
                str(items[i]['software_version']),
                str(items[i]['software_type']),
              ].whereType<String>().join(' • ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  context.push('/software/${toInt(items[i]['software_id']) ?? 0}'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _relatedCard({
    required String title,
    required int count,
    required bool loading,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('$title${count > 0 ? ' ($count)' : ''}'),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
      ],
    );
  }
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
        appBarActions: (c, r) {
          final invoiceId = toInt(r['invoice_id']) ?? 0;
          final status = (str(r['invoice_status']) ?? '').toLowerCase();
          final canPay = status != 'paid' && status != 'cancelled' &&
              status != 'draft';
          return [
            if (canPay)
              IconButton(
                tooltip: 'Make Payment',
                icon: const Icon(Icons.payments_outlined),
                onPressed: () => c.push('/invoices/$invoiceId/pay'),
              ),
            _InvoicePdfButton(invoiceId: invoiceId),
          ];
        },
        sectionsBuilder: (c, ref, r) {
          final cur = str(r['invoice_currency_code']);
          final clientId = toInt(r['invoice_client_id']) ?? 0;
          return [
            _InvoiceBillToSection(clientId: clientId),
            _InvoiceItemsSection(
                invoiceId: toInt(r['invoice_id']) ?? 0, currency: cur),
            _section('Amounts', [
              _kv('Total', _money(r['invoice_amount'], cur),
                  Icons.attach_money_outlined),
              _kv('Discount', _money(r['invoice_discount_amount'], cur),
                  Icons.percent_outlined),
              _kv('Credit applied', _money(r['invoice_credit_amount'], cur),
                  Icons.account_balance_wallet_outlined),
              _kv('Currency', cur, Icons.money_outlined),
            ]),
            if (str(r['invoice_note']) != null)
              _LongTextSection(
                  title: 'Note', value: str(r['invoice_note'])!),
            _InvoiceTicketsSection(invoiceId: toInt(r['invoice_id']) ?? 0),
            if (str(r['invoice_url_key']) != null)
              _GuestInvoiceCard(
                invoiceId: toInt(r['invoice_id']) ?? 0,
                urlKey: str(r['invoice_url_key'])!,
              ),
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
          ];
        },
      );
}

class _InvoiceBillToSection extends ConsumerWidget {
  final int clientId;
  const _InvoiceBillToSection({required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (clientId == 0) return const SizedBox.shrink();
    final clientAsync = ref.watch(clientProvider(clientId));
    final locationsAsync = ref.watch(clientLocationsProvider(clientId));
    final contactsAsync = ref.watch(contactsProvider);

    final Client? client = clientAsync.value;
    final primaryLocation = locationsAsync.value
        ?.firstWhere((r) => toBool(r['location_primary']),
            orElse: () => <String, dynamic>{});
    final primaryContact = contactsAsync.value?.firstWhere(
      (c) => c.clientId == clientId && c.primary,
      orElse: () => Contact(id: 0),
    );

    if (client == null && primaryLocation == null && primaryContact == null) {
      return const SizedBox.shrink();
    }

    final addressLines = primaryLocation == null
        ? <String>[]
        : <String>[
            if (str(primaryLocation['location_address']) != null)
              str(primaryLocation['location_address'])!,
            [
              str(primaryLocation['location_city']),
              str(primaryLocation['location_state']),
              str(primaryLocation['location_zip']),
            ].whereType<String>().join(', '),
            if (str(primaryLocation['location_country']) != null)
              str(primaryLocation['location_country'])!,
          ].where((s) => s.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Bill To'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (client?.name != null)
                  InkWell(
                    onTap: () => context.push('/clients/$clientId'),
                    child: Text(
                      client!.name!,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (addressLines.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(addressLines.join('\n'),
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (primaryContact != null &&
                    primaryContact.email != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => launchUrl(
                        Uri.parse('mailto:${primaryContact.email}')),
                    child: Text(
                      primaryContact.email!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceItemsSection extends ConsumerWidget {
  final int invoiceId;
  final String? currency;
  const _InvoiceItemsSection(
      {required this.invoiceId, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ItemsSection(async: ref.watch(_invoiceItemsProvider(invoiceId)), currency: currency);
}

class _QuoteItemsSection extends ConsumerWidget {
  final int quoteId;
  final String? currency;
  const _QuoteItemsSection(
      {required this.quoteId, required this.currency});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _ItemsSection(async: ref.watch(_quoteItemsProvider(quoteId)), currency: currency);
}

class _ItemsSection extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> async;
  final String? currency;
  const _ItemsSection({required this.async, required this.currency});

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          SectionHeader('Items'),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          ),
        ],
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader('Items (${items.length})'),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _InvoiceItemTile(item: items[i], currency: currency),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InvoiceItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String? currency;
  const _InvoiceItemTile({required this.item, required this.currency});

  @override
  Widget build(BuildContext context) {
    final name = str(item['item_name']) ?? '(item)';
    final desc = str(item['item_description']);
    final qty = toDouble(item['item_quantity']);
    final price = toDouble(item['item_price']);
    final total = toDouble(item['item_total']);
    final tax = toDouble(item['item_tax']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (total != null)
                Text(
                  _money(total, currency),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
            ],
          ),
          if (desc != null && desc.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
            child: Wrap(
              spacing: 12,
              runSpacing: 2,
              children: [
                if (qty != null)
                  Text('Qty ${_fmtQty(qty)}'),
                if (price != null)
                  Text('Unit ${_money(price, currency)}'),
                if (tax != null && tax > 0)
                  Text('Tax ${_money(tax, currency)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2);
}

class _InvoiceTicketsSection extends ConsumerWidget {
  final int invoiceId;
  const _InvoiceTicketsSection({required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketsProvider);
    if (async.isLoading && async.value == null) return const SizedBox.shrink();
    final tickets = async.value
            ?.where(
                (t) => toInt(t.raw['ticket_invoice_id']) == invoiceId)
            .toList() ??
        const <Ticket>[];
    if (tickets.isEmpty) return const SizedBox.shrink();
    tickets.sort((a, b) {
      final av = a.createdAt ?? DateTime(0);
      final bv = b.createdAt ?? DateTime(0);
      return bv.compareTo(av);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Tickets (${tickets.length})'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < tickets.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent),
                  title: Text(tickets[i].subject ?? '(no subject)'),
                  subtitle: Text([
                    tickets[i].displayNumber,
                    tickets[i].isResolved ? 'Closed' : 'Open',
                    tickets[i].createdAt == null
                        ? null
                        : _df.format(tickets[i].createdAt!),
                  ]
                      .whereType<String>()
                      .where((s) => s.isNotEmpty)
                      .join(' • ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tickets/${tickets[i].id}'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GuestInvoiceCard extends ConsumerWidget {
  final int invoiceId;
  final String urlKey;
  const _GuestInvoiceCard({required this.invoiceId, required this.urlKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = _instanceRoot(ref);
    if (root == null) return const SizedBox.shrink();
    final url =
        '$root/guest/guest_view_invoice.php?invoice_id=$invoiceId&url_key=$urlKey';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Guest View'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shareable link the client can open without logging in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Guest link copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy link'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoicePdfButton extends ConsumerStatefulWidget {
  final int invoiceId;
  const _InvoicePdfButton({required this.invoiceId});

  @override
  ConsumerState<_InvoicePdfButton> createState() => _InvoicePdfButtonState();
}

class _InvoicePdfButtonState extends ConsumerState<_InvoicePdfButton> {
  bool _busy = false;

  Future<void> _download() async {
    final web = ref.read(itflowWebClientProvider);
    if (web == null) {
      _toast('Agent email + password not set. Add them in Settings.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await web.downloadInvoicePdf(widget.invoiceId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invoice-${widget.invoiceId}.pdf');
      await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Invoice #${widget.invoiceId}',
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Download failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Download PDF',
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
      onPressed: _busy ? null : _download,
    );
  }
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
        appBarActions: (c, r) => [
          _QuotePdfButton(quoteId: toInt(r['quote_id']) ?? 0),
        ],
        sectionsBuilder: (c, ref, r) {
          final cur = str(r['quote_currency_code']);
          final clientId = toInt(r['quote_client_id']) ?? 0;
          final quoteId = toInt(r['quote_id']) ?? 0;
          return [
            _InvoiceBillToSection(clientId: clientId),
            _QuoteItemsSection(quoteId: quoteId, currency: cur),
            _section('Amounts', [
              _kv('Total', _money(r['quote_amount'], cur),
                  Icons.attach_money_outlined),
              _kv('Discount', _money(r['quote_discount_amount'], cur),
                  Icons.percent_outlined),
              _kv('Currency', cur, Icons.money_outlined),
            ]),
            if (str(r['quote_note']) != null)
              _LongTextSection(title: 'Note', value: str(r['quote_note'])!),
            if (str(r['quote_url_key']) != null)
              _GuestQuoteCard(
                quoteId: quoteId,
                urlKey: str(r['quote_url_key'])!,
              ),
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
              _kvLookup(c, ref, 'Client', r['quote_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
              _kv('Category ID', r['quote_category_id'], Icons.label_outline),
            ]),
          ];
        },
      );
}

class _GuestQuoteCard extends ConsumerWidget {
  final int quoteId;
  final String urlKey;
  const _GuestQuoteCard({required this.quoteId, required this.urlKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final root = _instanceRoot(ref);
    if (root == null) return const SizedBox.shrink();
    final url =
        '$root/guest/guest_view_quote.php?quote_id=$quoteId&url_key=$urlKey';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Guest View'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shareable link the client can open without logging in.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Guest link copied'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy link'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _QuotePdfButton extends ConsumerStatefulWidget {
  final int quoteId;
  const _QuotePdfButton({required this.quoteId});

  @override
  ConsumerState<_QuotePdfButton> createState() => _QuotePdfButtonState();
}

class _QuotePdfButtonState extends ConsumerState<_QuotePdfButton> {
  bool _busy = false;

  Future<void> _download() async {
    final web = ref.read(itflowWebClientProvider);
    if (web == null) {
      _toast('Agent email + password not set. Add them in Settings.');
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await web.downloadQuotePdf(widget.quoteId);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/quote-${widget.quoteId}.pdf');
      await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Quote #${widget.quoteId}',
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Download failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Download PDF',
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.picture_as_pdf_outlined),
      onPressed: _busy ? null : _download,
    );
  }
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/expenses/new'),
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
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
          final root = _instanceRoot(ref);
          final receiptUrl = (receipt != null && root != null)
              ? '$root/uploads/expenses/${Uri.encodeComponent(receipt)}'
              : null;
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
                  onTap: receiptUrl == null ? null : () => _open(receiptUrl),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                ),
            ]),
            _section('Associations', [
              _kvLookup(c, ref, 'Vendor', r['expense_vendor_id'],
                  Icons.store_outlined,
                  names: _vendorNames, route: '/vendors'),
              _kvLookup(c, ref, 'Client', r['expense_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
              _kvFromMap(
                  'Category',
                  r['expense_category_id'],
                  Icons.label_outline,
                  ref.watch(_expenseAdminLookupsProvider).value?.categories ??
                      const <int, String>{}),
              _kvFromMap(
                  'Account',
                  r['expense_account_id'],
                  Icons.account_balance_outlined,
                  ref.watch(_expenseAdminLookupsProvider).value?.accounts ??
                      const <int, String>{}),
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
              _kvLookup(c, ref, 'Domain', r['certificate_domain_id'],
                  Icons.dns_outlined,
                  names: _domainNames, route: '/domains'),
              _kvLookup(c, ref, 'Client', r['certificate_client_id'],
                  Icons.business_outlined,
                  names: _clientNames, route: '/clients'),
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
