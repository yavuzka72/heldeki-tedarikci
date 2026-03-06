import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:haldeki_tedarikci_web/config.dart';
import 'package:haldeki_tedarikci_web/models/category.dart' as m;
import 'package:haldeki_tedarikci_web/models/product.dart';
import 'package:haldeki_tedarikci_web/models/variant.dart';
import 'package:haldeki_tedarikci_web/services/api_client.dart';
import 'package:haldeki_tedarikci_web/widgets/add_product_sheet.dart';

class MarketController extends ChangeNotifier {
  final ApiClient api;
  MarketController(this.api);

  // UI
  final TextEditingController search = TextEditingController();

  bool loadingCats = true;
  bool loadingProds = true;
  bool loadingMore = false;

  List<m.Category> cats = const [];
  int? selectedCat;

  List<Product> products = const [];
  int _page = 1;
  bool more = true;

  Product? selectedProduct;

  // Variants cache: productId -> variants (user prices)
  final Map<int, List<ProductVariant>> _variantsCache = {};
  final Set<int> _loadingVariantFor = <int>{};
  final Map<int, CancelToken> _variantTokens = {};

  // price editing
  final Map<int, TextEditingController> _priceCtrls = {};
  final Map<int, double> dirtyPrices = {};

  // image upload (detail panel)
  Uint8List? detailImageBytes;
  String? detailImageName;
  bool uploadingDetailImage = false;

  String get _email => api.session?.email.toString() ?? '';
  int? get _userId {
    final sid = api.session?.userId;
    if (sid != null && sid > 0) return sid;
    final pid = api.userId;
    if (pid != null && pid > 0) return pid;
    return null;
  }

  int? get _dealerId {
    final sid = api.session?.dealerId;
    if (sid != null && sid > 0) return sid;
    final pid = api.dealerId;
    if (pid != null && pid > 0) return pid;
    return null;
  }

  Future<void> init() async {
    await Future.wait([
      loadCategories(),
      fetchProducts(reset: true),
    ]);
  }

  @override
  void dispose() {
    search.dispose();
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    _priceCtrls.clear();

    for (final t in _variantTokens.values) {
      t.cancel('dispose');
    }
    _variantTokens.clear();
    super.dispose();
  }

  // ---------------- Categories ----------------
  Future<void> loadCategories() async {
    loadingCats = true;
    notifyListeners();

    try {
      final res = await api.dio.get('categories');
      final data = res.data;

      List list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['data'] is List) {
        list = data['data'] as List;
      } else if (data is Map && data['results'] is List) {
        list = data['results'] as List;
      } else {
        list = [];
      }

      cats = list
          .whereType<Map>()
          .map((j) => m.Category.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } catch (_) {
      cats = const [];
    } finally {
      loadingCats = false;
      notifyListeners();
    }
  }

  // ---------------- Products ----------------
  Future<void> fetchProducts({required bool reset}) async {
    if (reset) {
      _page = 1;
      more = true;
      products = const [];
      loadingProds = true;
      notifyListeners();
    } else {
      if (!more || loadingMore) return;
      loadingMore = true;
      notifyListeners();
    }

    try {
      final params = <String, dynamic>{
        'page': _page,
        if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
        if (selectedCat != null) ...{
          'category_id': selectedCat,
          'filters[category_id]': selectedCat,
        },

        // ✅ Eğer backend destekliyorsa aç:
        // 'email': _email,
      };

      final res = await api.dio.get('products', queryParameters: params);
      final parsed = _parseProductsPayload(res.data);

      products = [...products, ...parsed];

      int? currentPage, lastPage;
      final root = res.data;
      if (root is Map) {
        if (root['data'] is Map) {
          final d = root['data'] as Map;
          if (d['current_page'] is num) {
            currentPage = (d['current_page'] as num).toInt();
          }
          if (d['last_page'] is num) {
            lastPage = (d['last_page'] as num).toInt();
          }
        }
        if (root['current_page'] is num) {
          currentPage = (root['current_page'] as num).toInt();
        }
        if (root['last_page'] is num) {
          lastPage = (root['last_page'] as num).toInt();
        }
      }

      if (currentPage != null && lastPage != null) {
        more = currentPage < lastPage;
        if (more) _page = currentPage + 1;
      } else {
        more = parsed.isNotEmpty;
        if (more) _page += 1;
      }
    } finally {
      loadingProds = false;
      loadingMore = false;
      notifyListeners();
    }
  }

  List<Product> _parseProductsPayload(dynamic payload) {
    List items;
    if (payload is Map &&
        payload['data'] is Map &&
        (payload['data'] as Map)['data'] is List) {
      items = ((payload['data'] as Map)['data'] as List);
    } else if (payload is Map && payload['data'] is List) {
      items = (payload['data'] as List);
    } else if (payload is List) {
      items = payload;
    } else if (payload is Map && payload['results'] is List) {
      items = payload['results'] as List;
    } else {
      items = const [];
    }

    return items.whereType<Map>().map((raw) {
      final j = Map<String, dynamic>.from(raw);

      final id = _asInt(j['id']);
      final name = (j['name'] ?? j['title'] ?? '').toString();
      final catId = _asInt(j['category_id'] ?? j['categoryId']);

      final imagePath = j['image']?.toString() ?? '';
      final imageUrl = imagePath.isEmpty
          ? ''
          : (imagePath.startsWith('http')
              ? imagePath
              : AppConfig.imageUrl(imagePath));

      // NOTE: products endpoint çoğu zaman variants getirmiyor => boş kalabilir.
      List<ProductVariant> variants = [];
      if (j['variants'] is List) {
        variants = (j['variants'] as List).whereType<Map>().map((vv) {
          final v = Map<String, dynamic>.from(vv);
          return ProductVariant(
            id: _asInt(v['id']),
            name: (v['name'] ?? 'Standart').toString(),
            price: _asDouble(v['user_price'] ?? v['price'] ?? 0),
            unit: (v['unit'] ?? 'ADET').toString(),
            sku: v['sku']?.toString(),
            image: v['image']?.toString(),
          );
        }).toList();
      }

      return Product(
        id: id,
        categoryId: catId,
        name: name,
        image: imageUrl,
        variants: variants,
      );
    }).toList();
  }

  // ---------------- Selection ----------------
  void selectProduct(Product p) {
    selectedProduct = p;

    // reset image state
    detailImageBytes = null;
    detailImageName = null;
    uploadingDetailImage = false;

    dirtyPrices.clear();
    notifyListeners();

    ensureVariantsLoaded(p);
  }

  // ---------------- Variants ----------------
  bool isLoadingVariants(Product p) => _loadingVariantFor.contains(p.id);

  List<ProductVariant> variantsFor(Product p) {
    final cached = _variantsCache[p.id];
    if (cached != null && cached.isNotEmpty) return cached;
    return p.variants;
  }

  /// ✅ Kart fiyatı için: önce cache (variantsuser), yoksa product.variants
  double? cardMinPrice(Product p) {
    final vs = variantsFor(p);
    if (vs.isEmpty) return null;

    double? min;
    for (final v in vs) {
      final price = v.price;
      if (price <= 0) continue;
      min = (min == null) ? price : (price < min ? price : min);
    }
    return min;
  }

  Future<void> ensureVariantsLoaded(Product p) async {
    final cached = _variantsCache[p.id];
    if (cached != null && cached.isNotEmpty) return;
    if (_loadingVariantFor.contains(p.id)) return;

    _loadingVariantFor.add(p.id);
    notifyListeners();

    final vs = await _fetchVariantsUser(p.id);

    _loadingVariantFor.remove(p.id);

    if (vs.isNotEmpty) {
      _variantsCache[p.id] = vs;

      // ✅ product list içindeki ürünü de güncelle (kartlar görsün)
      _mergeProductVariantsIntoList(productId: p.id, variants: vs);

      // ctrl textleri cache’ten güncelle
      for (final v in vs) {
        final ctrl = _priceCtrls[v.id];
        if (ctrl != null && !dirtyPrices.containsKey(v.id)) {
          ctrl.text = v.price.toStringAsFixed(2);
        }
      }
    }

    notifyListeners();
  }

  Future<List<ProductVariant>> _fetchVariantsUser(int productId) async {
    final cached = _variantsCache[productId];
    if (cached != null && cached.isNotEmpty) return cached;

    _variantTokens[productId]?.cancel('newer variants request');
    final token = CancelToken();
    _variantTokens[productId] = token;

    double _pickPriceFromAny(Map<String, dynamic> v) {
      // 1) user_price (backend en doğrusu)
      final up = v['user_price'];
      final p = v['price'];
      if (up != null) return _asDouble(up);
      if (p != null) return _asDouble(p);

      // 2) prices[0].price fallback (senin response burada)
      final prices = v['prices'];
      if (prices is List && prices.isNotEmpty) {
        final first = prices.first;
        if (first is Map) {
          final pp = first['price'];
          if (pp != null) return _asDouble(pp);
        }
      }

      return 0.0;
    }

    String _pickUnit(Map<String, dynamic> v) {
      // unit null gelebiliyor sende
      final unit = v['unit']?.toString();
      if (unit != null && unit.trim().isNotEmpty) return unit;

      // bazen name "KG/DEMET" ise unit gibi kullanıyoruz
      final name = (v['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;

      return 'ADET';
    }

    try {
      final r = await api.dio.get(
        'products/$productId/variantsuser',
        cancelToken: token,
      );

      dynamic data = r.data;
      if (data is Map && data['data'] is List) data = data['data'];
      if (data is Map && data['variants'] is List) data = data['variants'];
      final list = (data is List) ? data : <dynamic>[];

      final vs = list.whereType<Map>().map((vv) {
        final v = Map<String, dynamic>.from(vv);

        final price = _pickPriceFromAny(v);
        final unit = _pickUnit(v);

        return ProductVariant(
          id: _asInt(v['id']),
          name: (v['name'] ?? 'Varyant').toString(),
          price: price,
          unit: unit,
          sku: v['sku']?.toString(),
          image: v['image']?.toString(),
        );
      }).toList();

      if (vs.isNotEmpty) _variantsCache[productId] = vs;
      return vs;
    } on DioException catch (e) {
      debugPrint(
          'variantsuser error: ${e.response?.statusCode} ${e.response?.data}');
      return const [];
    } finally {
      if (_variantTokens[productId] == token) _variantTokens.remove(productId);
    }
  }

  Future<List<ProductVariant>> _fetchVariantsUserMail(int productId) async {
    final cached = _variantsCache[productId];
    if (cached != null && cached.isNotEmpty) return cached;

    _variantTokens[productId]?.cancel('newer variants request');
    final token = CancelToken();
    _variantTokens[productId] = token;

    try {
      final r = await api.dio.get(
        'products/$productId/variantsuser',
        queryParameters: {'email': _email},
        cancelToken: token,
      );

      dynamic data = r.data;
      if (data is Map && data['data'] is List) data = data['data'];
      if (data is Map && data['variants'] is List) data = data['variants'];
      final list = (data is List) ? data : <dynamic>[];

      final vs = list.whereType<Map>().map((vv) {
        final v = Map<String, dynamic>.from(vv);
        final price = _asDouble(v['user_price'] ?? v['price'] ?? 0);

        return ProductVariant(
          id: _asInt(v['id']),
          name: (v['name'] ?? 'Varyant').toString(),
          price: price,
          unit: (v['unit'] ?? 'ADET').toString(),
          sku: v['sku']?.toString(),
          image: v['image']?.toString(),
        );
      }).toList();

      if (vs.isNotEmpty) _variantsCache[productId] = vs;
      return vs;
    } catch (_) {
      return const [];
    } finally {
      if (_variantTokens[productId] == token) _variantTokens.remove(productId);
    }
  }

  void _mergeProductVariantsIntoList({
    required int productId,
    required List<ProductVariant> variants,
  }) {
    final idx = products.indexWhere((x) => x.id == productId);
    if (idx < 0) return;

    final old = products[idx];
    final updated = Product(
      id: old.id,
      categoryId: old.categoryId,
      name: old.name,
      image: old.image,
      variants: List<ProductVariant>.from(variants),
    );

    final list = List<Product>.from(products);
    list[idx] = updated;
    products = list;

    if (selectedProduct?.id == productId) {
      selectedProduct = updated;
    }
  }

  // ---------------- Price helpers ----------------
  TextEditingController pc(int variantId, double initial) {
    return _priceCtrls.putIfAbsent(
      variantId,
      () => TextEditingController(text: initial.toStringAsFixed(2)),
    );
  }

// Kartta göstermek için: en düşük fiyatlı varyant (price>0) + doğru birim
  ({double price, String unit})? cardMinPriceWithUnit(Product p) {
    final vs = variantsFor(p);
    if (vs.isEmpty) return null;

    ProductVariant? best;
    for (final v in vs) {
      if (v.price <= 0) continue;
      if (best == null || v.price < best.price) best = v;
    }
    if (best == null) return null;

    final unit = _displayUnit(best);
    return (price: best.price, unit: unit);
  }

  String _displayUnit(ProductVariant v) {
    final name = (v.name).trim().toUpperCase(); // çoğu zaman "KG", "DEMET" vs.
    final unit = (v.unit).trim().toUpperCase(); // sende genelde "ADET" geliyor

    // 1) unit ADET değilse onu göster
    if (unit.isNotEmpty && unit != 'ADET' && unit != 'AD') return unit;

    // 2) unit ADET ise ama name birim gibi duruyorsa name'i göster
    const unitLike = {
      'KG',
      'KILO',
      'G',
      'GRAM',
      'LT',
      'L',
      'ML',
      'DEMET',
      'KASA',
      'BAĞ',
      'PAKET',
      'KOLI',
      'KOLİ',
    };
    if (unitLike.contains(name)) return name;

    // 3) fallback
    return unit.isNotEmpty ? unit : 'ADET';
  }

  double? tryParsePrice(String s) {
    if (s.trim().isEmpty) return null;

    final cleaned = s
        .toUpperCase()
        .replaceAll('₺', '')
        .replaceAll('TL', '')
        .replaceAll('/', '')
        .replaceAll('ADET', '')
        .replaceAll('KG', '')
        .replaceAll(' ', '')
        .replaceAll(',', '.');

    final v = double.tryParse(cleaned);
    if (v == null || v.isNaN || v.isInfinite) return null;

    return v;
  }

  // ---------------- SAVE (UPsert) ----------------
  Future<void> saveAllDirty({required ScaffoldMessengerState messenger}) async {
    final email = _email;
    final userId = _userId;
    final dealerId = _dealerId;
    if (email.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Email bulunamadı (session boş).')),
      );
      return;
    }

    final p = selectedProduct;
    if (p == null || dirtyPrices.isEmpty) return;

    try {
      final currentVariants = List<ProductVariant>.from(variantsFor(p));

      for (final entry in dirtyPrices.entries) {
        final variantId = entry.key;
        final price = entry.value;

        await api.dio.post('user-product-prices/upsert', data: {
          'email': email,
          if (userId != null) 'user_id': userId,
          if (dealerId != null) 'dealer_id': dealerId,
          'product_variant_id': variantId,
          'price': price,
          'active': true,
        });

        // local update (cache + list)
        final idx = currentVariants.indexWhere((x) => x.id == variantId);
        if (idx >= 0) {
          final old = currentVariants[idx];
          currentVariants[idx] = ProductVariant(
            id: old.id,
            name: old.name,
            unit: old.unit,
            sku: old.sku,
            image: old.image,
            price: price,
          );
        }
      }

      _variantsCache[p.id] = List<ProductVariant>.from(currentVariants);
      _mergeProductVariantsIntoList(productId: p.id, variants: currentVariants);

      dirtyPrices.clear();
      messenger.showSnackBar(
        const SnackBar(content: Text('Fiyatlar kaydedildi ✓')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      notifyListeners();
    }
  }

  // ---------------- Image upload ----------------
  Future<String?> _uploadImageBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final fd = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: filename),
      });

      final up = await api.dio.post('upload', data: fd);

      final data = up.data;
      if (data is Map && data['path'] is String) return data['path'] as String;
      if (data is Map &&
          data['data'] is Map &&
          (data['data'] as Map)['path'] is String) {
        return (data['data'] as Map)['path'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> pickAndUploadDetailImage({
    required ScaffoldMessengerState messenger,
  }) async {
    try {
      final p = selectedProduct;
      if (p == null) return;

      Uint8List? bytes;
      String? filename;
      await pickImageBytes(
        onPicked: (pickedBytes, pickedName) {
          bytes = pickedBytes;
          filename = pickedName;
        },
      );
      if (bytes == null || filename == null) return;

      detailImageBytes = bytes;
      detailImageName = filename;
      uploadingDetailImage = true;
      notifyListeners();

      final path = await _uploadImageBytes(
        bytes: bytes!,
        filename: filename!,
      );
      if (path == null) {
        uploadingDetailImage = false;
        notifyListeners();
        messenger.showSnackBar(
          const SnackBar(content: Text('Resim yükleme başarısız')),
        );
        return;
      }

      await api.updateProduct(p.id, ProductUpdate(image: path));
      _applyProductImage(productId: p.id, imagePath: AppConfig.imageUrl(path));

      uploadingDetailImage = false;
      notifyListeners();

      messenger.showSnackBar(
        const SnackBar(content: Text('Resim güncellendi ✓')),
      );
    } catch (e) {
      uploadingDetailImage = false;
      notifyListeners();
      messenger.showSnackBar(
        SnackBar(content: Text('Resim seçme/yükleme hatası: $e')),
      );
    }
  }

  void clearDetailImage() {
    detailImageBytes = null;
    detailImageName = null;
    uploadingDetailImage = false;
    notifyListeners();
  }

  void _applyProductImage({
    required int productId,
    required String imagePath,
  }) {
    final idx = products.indexWhere((x) => x.id == productId);
    if (idx >= 0) {
      final updated = products[idx].copyWith(image: imagePath);
      final next = List<Product>.from(products);
      next[idx] = updated;
      products = next;
      if (selectedProduct?.id == productId) {
        selectedProduct = updated;
      }
      return;
    }

    if (selectedProduct?.id == productId) {
      selectedProduct = selectedProduct?.copyWith(image: imagePath);
    }
  }

  // utils
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is num) return v.toInt();
    return 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    return 0.0;
  }
}
