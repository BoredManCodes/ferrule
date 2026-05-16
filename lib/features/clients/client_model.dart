import '../../core/util.dart';

class Client {
  final int id;
  final String? name;
  final String? type;
  final String? website;
  final String? phone;
  final String? email;
  final String? notes;
  final String? abbreviation;
  final String? referral;
  final double? rate;
  final String? currencyCode;
  final int? netTerms;
  final String? taxIdNumber;
  final bool favorite;
  final bool lead;
  final DateTime? archivedAt;
  final Map<String, dynamic> raw;

  Client({
    required this.id,
    this.name,
    this.type,
    this.website,
    this.phone,
    this.email,
    this.notes,
    this.abbreviation,
    this.referral,
    this.rate,
    this.currencyCode,
    this.netTerms,
    this.taxIdNumber,
    this.favorite = false,
    this.lead = false,
    this.archivedAt,
    this.raw = const {},
  });

  bool get archived => archivedAt != null;

  factory Client.fromRow(Map<String, dynamic> r) => Client(
        id: toInt(r['client_id']) ?? 0,
        name: str(r['client_name']),
        type: str(r['client_type']),
        website: str(r['client_website']),
        phone: str(r['client_phone']),
        email: str(r['client_email']),
        notes: str(r['client_notes']),
        abbreviation: str(r['client_abbreviation']),
        referral: str(r['client_referral']),
        rate: toDouble(r['client_rate']),
        currencyCode: str(r['client_currency_code']),
        netTerms: toInt(r['client_net_terms']),
        taxIdNumber: str(r['client_tax_id_number']),
        favorite: toBool(r['client_favorite']),
        lead: toBool(r['client_lead']),
        archivedAt: toDate(r['client_archived_at']),
        raw: r,
      );
}
