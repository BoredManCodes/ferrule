import '../../core/util.dart';

class Credential {
  final int id;
  final String? name;
  final String? description;
  final String? uri;
  final String? uri2;
  final String? username;
  final String? password;
  final String? otpSecret;
  final String? note;
  final bool favorite;
  final int? contactId;
  final int? assetId;
  final int? clientId;
  final DateTime? passwordChangedAt;
  final Map<String, dynamic> raw;

  Credential({
    required this.id,
    this.name,
    this.description,
    this.uri,
    this.uri2,
    this.username,
    this.password,
    this.otpSecret,
    this.note,
    this.favorite = false,
    this.contactId,
    this.assetId,
    this.clientId,
    this.passwordChangedAt,
    this.raw = const {},
  });

  factory Credential.fromRow(Map<String, dynamic> r) => Credential(
        id: toInt(r['credential_id']) ?? 0,
        name: str(r['credential_name']),
        description: str(r['credential_description']),
        uri: str(r['credential_uri']),
        uri2: str(r['credential_uri_2']),
        username: str(r['credential_username']),
        password: str(r['credential_password']),
        otpSecret: str(r['credential_otp_secret']),
        note: str(r['credential_note']),
        favorite: toBool(r['credential_favorite']),
        contactId: toInt(r['credential_contact_id']),
        assetId: toInt(r['credential_asset_id']),
        clientId: toInt(r['credential_client_id']),
        passwordChangedAt: toDate(r['credential_password_changed_at']),
        raw: r,
      );
}
