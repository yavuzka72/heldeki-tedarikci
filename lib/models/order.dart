import 'package:haldeki_tedarikci_web/utils/json_parse.dart';

class Order {
  final int id;
  final String orderNumber; // boş bile olsa '' veriyoruz
  final String status; // '' olabilir, UI’da _s() ile güvenle kullan
  final String paymentStatus;
  final String supplier_status;
  final double totalAmount;
  final String? shippingAddress; // nullable bırakılabilir
  final String? phone;
  final bool isGuestOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdByName; // JSON'da yoksa '' olur
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentStatus,
    required this.supplier_status,
    required this.totalAmount,
    required this.shippingAddress,
    required this.phone,
    required this.isGuestOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.createdByName,
    required this.items,
  });

  factory Order.fromJson(Map<String, dynamic> j) {
    // created_by / user alanı hem Map hem String olabilir, yok da olabilir
    String pickCreatedBy(Map<String, dynamic> m) {
      final u = m['user'] ?? m['created_by'] ?? m['customer'];
      if (u == null) return '';
      if (u is Map) {
        return asString(u['name'],
            fallback: asString(u['email'], fallback: ''));
      }
      return asString(u); // zaten string ise
    }

    final itemsRaw = (j['items'] ??
        j['order_items'] ??
        j['lines'] ??
        j['cart_items'] ??
        []) as List?;
    final items = (itemsRaw ?? [])
        .whereType<Map>()
        .map((m) => OrderItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();

    return Order(
      id: asInt(j['id']),
      orderNumber: asString(j['order_number'] ?? j['number'] ?? j['code']),
      status: asString(j['status'])
          .toLowerCase(), // 'pending','delivered','away' vb.
      supplier_status: asString(j['supplier_status'])
          .toLowerCase(), // 'pending','delivered','away' vb.
      paymentStatus: asString(j['payment_status']),
      totalAmount: asDouble(
          j['total_amount'] ?? j['total'] ?? j['grand_total'] ?? j['amount']),
      shippingAddress: (j['shipping_address'] ?? j['address'])?.toString(),
      phone: j['phone']?.toString(),
      isGuestOrder: asBool(j['is_guest_order']),
      createdAt: parseDate(j['created_at'] ?? j['date']),
      updatedAt: parseDate(j['updated_at']),
      createdByName: pickCreatedBy(j),
      items: items,
    );
  }
}

class OrderItem {
  final int id;
  final int orderId;
  final int productVariantId;
  final int? sellerId;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // UI için yardımcı alanlar
  final String? productName;
  final ProductVariant? productVariant;
  final Seller? seller;

  // Ürün adını mümkün olduğunca doğru üret.
  String get productTitle {
    final p = (productName ?? '').trim();
    final v = (productVariant?.name ?? '').trim();
    if (p.isNotEmpty && v.isNotEmpty) return '$p - $v';
    if (p.isNotEmpty) return p;
    if (v.isNotEmpty) return v;
    return 'Ürün';
  }

  double get qtyCases => quantity.toDouble();

  OrderItem({
    required this.id,
    required this.orderId,
    required this.productName,
    required this.productVariantId,
    required this.sellerId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.productVariant,
    required this.seller,
  });

  factory OrderItem.fromJson(Map<String, dynamic> j) {
    final pvJson = j['product_variant'] ??
        j['productVariant'] ??
        j['variant'] ??
        j['product_variant_data'] ??
        {};
    final sellerJson = j['seller'];
    final pvMap = pvJson is Map ? Map<String, dynamic>.from(pvJson) : null;
    final productMap = pvMap?['product'] is Map
        ? Map<String, dynamic>.from(pvMap!['product'])
        : null;

    String? pickProductName() {
      final direct = j['product_name'] ??
          j['productName'] ??
          j['product_title'] ??
          j['productTitle'] ??
          j['title'] ??
          j['name'];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString().trim();
      }
      final productDirect = j['product'];
      if (productDirect is Map) {
        final pm = Map<String, dynamic>.from(productDirect);
        final fromProductDirect = pm['name'] ??
            pm['title'] ??
            pm['product_name'] ??
            pm['productTitle'];
        if (fromProductDirect != null &&
            fromProductDirect.toString().trim().isNotEmpty) {
          return fromProductDirect.toString().trim();
        }
      }
      final fromProduct = productMap?['name'] ??
          productMap?['title'] ??
          productMap?['product_name'] ??
          productMap?['productTitle'];
      if (fromProduct != null && fromProduct.toString().trim().isNotEmpty) {
        return fromProduct.toString().trim();
      }
      final nestedDirect = pvMap?['product_name'] ??
          pvMap?['productName'] ??
          pvMap?['product_title'] ??
          pvMap?['productTitle'];
      if (nestedDirect != null && nestedDirect.toString().trim().isNotEmpty) {
        return nestedDirect.toString().trim();
      }
      return null;
    }

    return OrderItem(
      id: asInt(j['id']),
      orderId: asInt(j['order_id']),
      productName: pickProductName(),
      productVariantId: asInt(
        j['product_variant_id'] ?? j['variant_id'] ?? j['variantId'],
      ),
      sellerId: j['seller_id'] != null ? asInt(j['seller_id']) : null,
      quantity: asInt(j['quantity'] ?? j['qty']),
      unitPrice: asDouble(j['unit_price'] ?? j['price']),
      lineTotal: asDouble(j['total_price'] ?? j['line_total'] ?? j['total']),
      status: asString(j['status']).toLowerCase(),
      createdAt: parseDate(j['created_at']),
      updatedAt: parseDate(j['updated_at']),
      productVariant: pvJson is Map
          ? ProductVariant.fromJson(Map<String, dynamic>.from(pvJson))
          : null,
      seller: (sellerJson is Map)
          ? Seller.fromJson(Map<String, dynamic>.from(sellerJson))
          : null,
    );
  }
}

class ProductVariant {
  final int id;
  final int? productId;
  final String name;
  final bool active;
  final double averagePrice;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.active,
    required this.averagePrice,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> j) {
    return ProductVariant(
      id: asInt(j['id']),
      productId: j['product_id'] != null ? asInt(j['product_id']) : null,
      name: asString(j['name'] ?? j['variant_name'] ?? j['variantName']),
      active: asBool(j['active']),
      averagePrice: asDouble(j['average_price'] ?? j['price']),
      createdAt: parseDate(j['created_at']),
      updatedAt: parseDate(j['updated_at']),
    );
  }
}

class Seller {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? address;

  Seller({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.address,
  });

  factory Seller.fromJson(Map<String, dynamic> j) {
    return Seller(
      id: asInt(j['id']),
      name: asString(j['name']),
      email: asString(j['email']),
      phone: j['phone']?.toString(),
      address: j['address']?.toString(),
    );
  }

  // ---- JSON yardımcıları (STRING → NUMBER normalizasyonu) ----
  double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final s = v.replaceAll('₺', '').replaceAll(' ', '').replaceAll(',', '.');
      return double.tryParse(s) ?? 0.0;
    }
    return 0.0;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
