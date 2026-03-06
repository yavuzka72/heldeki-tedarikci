// lib/config.dart
class AppConfig {
  /// flutter run -d chrome --dart-define=API_ORIGIN=http://172.20.10.5:8083/
  static const origin = String.fromEnvironment(
    'API_ORIGIN',
    defaultValue: 'https://api.haldeki.com/',
  );

  static const apiVersion = 'v1/';
  static const imageCdnOrigin = String.fromEnvironment(
    'IMAGE_CDN_ORIGIN',
    defaultValue: 'https://cdn.haldeki.com',
  );

  /// http://172.20.10.5:8083//api/v1
  static String get apiBase => '$origin/api/$apiVersion';

  /// Görsel URL builder (tek doğru nokta)
  static String imageUrl(String? path) {
    final p = (path ?? '').trim();
    if (p.isEmpty) return '';

    final cdn = imageCdnOrigin.trim();
    final imageBase = cdn.isNotEmpty ? cdn : origin;

    String join(String base, String segment) {
      final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final s = segment.startsWith('/') ? segment : '/$segment';
      return '$b$s';
    }

    // Full URL geldiyse CDN'e normalize etmeyi dene
    if (p.startsWith('http://') || p.startsWith('https://')) {
      if (cdn.isNotEmpty) {
        final uri = Uri.tryParse(p);
        final pathOnly = uri?.path ?? '';
        const storageSegment = '/storage/';
        final storageIndex = pathOnly.indexOf(storageSegment);
        if (storageIndex >= 0) {
          final relative =
              pathOnly.substring(storageIndex + storageSegment.length);
          return join(imageBase, '/$relative');
        }
      }
      return p;
    }

    // "/storage/..." geldiyse:
    // CDN varsa "/products/..." olarak yaz, yoksa origin/storage koru
    if (p.startsWith('/storage/')) {
      if (cdn.isNotEmpty) {
        final relative = p.substring('/storage/'.length);
        return join(imageBase, '/$relative');
      }
      return join(imageBase, p);
    }

    // "storage/..." geldiyse:
    // CDN varsa "/products/..." olarak yaz, yoksa origin/storage koru
    if (p.startsWith('storage/')) {
      if (cdn.isNotEmpty) {
        final relative = p.substring('storage/'.length);
        return join(imageBase, '/$relative');
      }
      return join(imageBase, '/$p');
    }

    // "products/..." gibi relative geldiyse:
    // CDN varsa direkt "/products/...", yoksa "/storage/products/..."
    final clean = p.startsWith('/') ? p.substring(1) : p;
    if (cdn.isNotEmpty) return join(imageBase, '/$clean');
    return join(imageBase, '/storage/$clean');
  }

  // ---- Paths ----
  static const String loginPath = 'login';
  static const String previousOrdersPath = 'previous-orders';
  static const String suppliersOrdersPath = 'supplier';
  static const String supplierUpdateStatusPath = 'supplier-order-update-status';
  static const String productsPath = 'products';

  static String approveOrderPath(String id) => 'orders/$id/approve';
  static String cancelOrderPath(String id) => 'orders/$id/cancel';
  static String readyOrderPath(String id) => 'orders/$id/ready';
  static String deliverOrderPath(String id) => 'orders/$id/deliver';

  static String updateProductPath(String id) => 'products/$id';
  static String updateProductImagePath(String id) => 'products/$id/image';
  static const String updatePricePath = 'products/update-price';
  static String productVariantsPath(String id) => 'products/$id/variants';
  static String singleVariantPath(String variantId) => 'variants/$variantId';
  static const String createProductPath = 'products';

  static const String dealerOrdersPath = 'vendor-orders';
  static const dealerOrderDetailPath = 'orderdetail-tedarik';
}
