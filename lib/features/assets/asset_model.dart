import 'package:flutter/material.dart';

import '../../core/util.dart';

class Asset {
  final int id;
  final String? name;
  final String? description;
  final String? type;
  final String? make;
  final String? model;
  final String? serial;
  final String? os;
  final String? uri;
  final String? uri2;
  final String? status;
  final int? clientId;
  final int? locationId;
  final int? vendorId;
  final int? contactId;
  final String? mac;
  final String? ip;
  final DateTime? purchaseDate;
  final DateTime? warrantyExpire;
  final DateTime? installDate;
  final String? notes;
  final Map<String, dynamic> raw;

  Asset({
    required this.id,
    this.name,
    this.description,
    this.type,
    this.make,
    this.model,
    this.serial,
    this.os,
    this.uri,
    this.uri2,
    this.status,
    this.clientId,
    this.locationId,
    this.vendorId,
    this.contactId,
    this.mac,
    this.ip,
    this.purchaseDate,
    this.warrantyExpire,
    this.installDate,
    this.notes,
    this.raw = const {},
  });

  factory Asset.fromRow(Map<String, dynamic> r) => Asset(
        id: toInt(r['asset_id']) ?? 0,
        name: str(r['asset_name']),
        description: str(r['asset_description']),
        type: str(r['asset_type']),
        make: str(r['asset_make']),
        model: str(r['asset_model']),
        serial: str(r['asset_serial']),
        os: str(r['asset_os']),
        uri: str(r['asset_uri']),
        uri2: str(r['asset_uri_2']),
        status: str(r['asset_status']),
        clientId: toInt(r['asset_client_id']),
        locationId: toInt(r['asset_location_id']),
        vendorId: toInt(r['asset_vendor_id']),
        contactId: toInt(r['asset_contact_id']),
        mac: str(r['interface_mac']),
        ip: str(r['interface_ip']),
        purchaseDate: toDate(r['asset_purchase_date']),
        warrantyExpire: toDate(r['asset_warranty_expire']),
        installDate: toDate(r['asset_install_date']),
        notes: str(r['asset_notes']),
        raw: r,
      );

  static const types = [
    'Desktop',
    'Laptop',
    'Server',
    'Phone',
    'Tablet',
    'Printer',
    'Switch',
    'Router',
    'Firewall',
    'Access Point',
    'Camera',
    'Other',
  ];

  static const statuses = [
    'Ready To Deploy',
    'Deployed',
    'Archived',
    'Lost/Stolen',
    'Broken',
  ];

  IconData get icon {
    switch (type?.toLowerCase()) {
      case 'desktop':
      case 'laptop':
        return Icons.laptop_mac;
      case 'server':
        return Icons.dns_outlined;
      case 'phone':
        return Icons.smartphone;
      case 'tablet':
        return Icons.tablet_mac;
      case 'printer':
        return Icons.print_outlined;
      case 'switch':
      case 'router':
      case 'firewall':
      case 'access point':
        return Icons.router_outlined;
      case 'camera':
        return Icons.videocam_outlined;
      default:
        return Icons.devices_other;
    }
  }
}
