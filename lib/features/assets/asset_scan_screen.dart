import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AssetScanScreen extends ConsumerStatefulWidget {
  const AssetScanScreen({super.key});

  @override
  ConsumerState<AssetScanScreen> createState() => _AssetScanScreenState();
}

class _AssetScanScreenState extends ConsumerState<AssetScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Parses formats like `000037_bordertechsolutions_0126` and returns the asset id.
  static int? parseAssetId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // Plain integer
    final plain = int.tryParse(trimmed);
    if (plain != null) return plain;

    // Split on underscore; first segment is the id (may be zero-padded).
    final parts = trimmed.split('_');
    if (parts.isEmpty) return null;
    final first = parts.first.replaceAll(RegExp(r'\D'), '');
    if (first.isEmpty) return null;
    return int.tryParse(first);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;

    final id = parseAssetId(raw);
    if (id == null) {
      _handling = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unrecognized QR: "$raw"'),
          duration: const Duration(seconds: 2),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      _handling = false;
      return;
    }

    _handling = true;
    await _controller.stop();
    if (!mounted) return;
    context.pushReplacement('/assets/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Asset QR'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 48,
                        color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Camera unavailable',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error.errorDetails?.message ?? error.errorCode.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _Reticle(),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.qr_code, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Aim at an asset QR code.\nFormat: assetid_customer_installdate',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reticle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
