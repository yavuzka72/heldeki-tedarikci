// lib/screens/price_list_screen.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:data_table_2/data_table_2.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:haldeki_tedarikci_web/screens/haldeki_ui.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/variant.dart';
import '../services/api_client.dart';

import '../widgets/add_product_sheet.dart';

class PriceListScreen extends StatefulWidget {
  const PriceListScreen({super.key});

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _RowVM {
  Product product;
  List<ProductVariant> variants;
  int? selectedVariantId;
  final TextEditingController priceC;
  bool dirty;

  _RowVM({
    required this.product,
    required this.variants,
    required this.selectedVariantId,
    required double price,
  })  : priceC = TextEditingController(text: price.toStringAsFixed(2)),
        dirty = false;

  void dispose() => priceC.dispose();
}

class _PriceListScreenState extends State<PriceListScreen> {
  static const Color _primaryStrong = Color(0xFF0B7A3E);
  String _buildSku(String a, String b) {
    final base = '${a}_$b'
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final suffix =
        DateTime.now().millisecondsSinceEpoch.toString().substring(7);
    return '${base.isEmpty ? 'SKU' : base}_$suffix';
  }

  // --- Controls
  final _search = TextEditingController();
  Timer? _debounce;

  // --- Categories
  bool _loadingCats = true;
  List<Category> _cats = const [];
  int? _selectedCat;

  // --- Data
  final List<_RowVM> _rows = [];
  bool _loadingRows = true;
  bool _fetchingMore = false;
  bool _more = true;
  int _page = 1;

  // PaginatedDataTable (server paging)
  int _rowsPerPage = 20;
  int _firstRowIndex = 0; // table offset
  int _totalRows = 0; // server total if provided
  String? _error;

  // --- Sort
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  // --- API
  Dio get _dio => context.read<ApiClient>().dio;
  // ORAN controller
  final TextEditingController rateCtrl = TextEditingController(text: '10');

  static const List<String> _unitOptions = [
    'ADET',
    'GR',
    'KG',
    'BAĞ',
    'DEMET',
    'KASA'
  ];

  // --- Current user id
  int? _myUserId;

  // --- Perf
  CancelToken? _listToken;
  final Map<int, List<ProductVariant>> _variantsCache =
      {}; // productId -> variants
  final Map<int, CancelToken> _variantTokens = {}; // productId -> cancel token
  final Set<int> _updatingImageIds = <int>{};

  // --- Data source
  late _PriceDataSource _dataSource;

  // --- UI tokens
  static const double _r16 = 16;

  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _borderC = Color(0xFFE6E8EF);

  Color _outline(ColorScheme cs) => _borderC;
  Color _soft(Color c, [double o = .08]) => c.withOpacity(o);

  // Consistent controls
  static const double _ctrlRadius = 12;
  static const EdgeInsets _ctrlPad =
      EdgeInsets.symmetric(horizontal: 12, vertical: 12);

  InputDecoration _proFieldDecoration(
    BuildContext context, {
    String? label,
    String? hint,
    Widget? prefixIcon,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: contentPadding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: const TextStyle(color: Colors.black87),
      hintStyle: const TextStyle(color: Colors.black87),
      prefixStyle: const TextStyle(color: Colors.black87),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderC),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _borderC),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.8),
      ),
      floatingLabelStyle: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    final api = context.read<ApiClient>();
    _myUserId = api.session?.userId;

    _dataSource = _PriceDataSource(
      getRows: () => _rows,
      myUserId: () => _myUserId,
      variantLabel: _variantLabel,
      onSaveRow: (row) async {
        await _saveRow(row);
      },
      onAddVariant: _addVariantForRow,
      onUpdateImage: _updateProductImage,
      onChanged: () => setState(() {}),

      // ✅ server paging
      getFirstRowIndex: () => _firstRowIndex,
      getTotalRows: () => _totalRows > 0 ? _totalRows : _rows.length,

      // ✅ theming (row hover + dirty bar)
      getPrimary: () => Theme.of(context).colorScheme.primary,
    );

    _search.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => _onSearch());
    });

    _loadAll();
  }

  void applyRate({required bool increase}) {
    final rate = double.tryParse(rateCtrl.text);
    if (rate == null || rate <= 0) return;

    final factor = rate / 100;

    setState(() {
      for (final row in _rows) {
        final oldPrice = double.tryParse(row.priceC.text) ?? 0;
        if (oldPrice <= 0) continue;

        final newPrice =
            increase ? oldPrice * (1 + factor) : oldPrice * (1 - factor);

        row.priceC.text = newPrice.toStringAsFixed(2);
        row.dirty = true; // 🔥 Hepsini Kaydet için
      }
    });
  }

  @override
  void dispose() {
    _listToken?.cancel('dispose');
    for (final t in _variantTokens.values) {
      t.cancel('dispose');
    }
    _variantTokens.clear();

    _debounce?.cancel();
    _search.dispose();

    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadCategories(), _fetchRows(reset: true, page: 1)]);
  }

  Future<void> _onSearch() async {
    _firstRowIndex = 0;
    await _fetchRows(reset: true, page: 1);
  }

  // ----------------- CATEGORIES -----------------
  Future<void> _loadCategories() async {
    setState(() => _loadingCats = true);
    try {
      final res = await _dio.get('categories');
      final data = res.data;
      List list;
      if (data is List) {
        list = data;
      } else if (data is Map && data['data'] is List) {
        list = data['data'];
      } else if (data is Map && data['results'] is List) {
        list = data['results'];
      } else {
        list = [];
      }
      _cats = list
          .whereType<Map>()
          .map((j) => Category.fromJson(Map<String, dynamic>.from(j)))
          .toList();
    } finally {
      if (mounted) setState(() => _loadingCats = false);
    }
  }

  // ----------------- PRODUCTS + VARIANTS -----------------
  Future<void> _fetchRows({bool reset = false, required int page}) async {
    if (reset) {
      _listToken?.cancel('reset');
      _listToken = CancelToken();

      for (final t in _variantTokens.values) {
        t.cancel('reset');
      }
      _variantTokens.clear();

      for (final r in _rows) r.dispose();
      _rows.clear();

      _page = page;
      _more = true;
      _error = null;
      _totalRows = 0;

      setState(() {
        _loadingRows = true;
        _fetchingMore = false;
      });

      _dataSource.notifyListeners();
    } else {
      if (!_more || _fetchingMore) return;
      _fetchingMore = true;
      setState(() {});
    }

    try {
      final params = <String, dynamic>{
        'page': _page,
        'per_page': _rowsPerPage,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
        if (_selectedCat != null) ...{
          'category_id': _selectedCat,
          'filters[category_id]': _selectedCat,
        },
      };

      final res = await _dio.get(
        'products',
        queryParameters: params,
        cancelToken: _listToken,
      );

      final products = _parseProductsPayload(res.data);
      _parsePaginationMeta(res.data);

      for (final p in products) {
        final baseVariant = p.variants.isNotEmpty
            ? p.variants.first
            : ProductVariant(
                id: p.id * 1000,
                name: 'Standart',
                price: 0.0,
                unit: 'ADET',
                image: p.image,
              );

        _rows.add(_RowVM(
          product: p,
          variants: [baseVariant],
          selectedVariantId: baseVariant.id,
          price: baseVariant.price ?? 0.0,
        ));
      }

      if (mounted) setState(() {});
      _dataSource.notifyListeners();

      // lazy variants (cache + concurrency)
      const int concurrency = 4;
      for (var i = 0; i < products.length; i += concurrency) {
        final group =
            products.sublist(i, (i + concurrency).clamp(0, products.length));
        await Future.wait(group.map((p) async {
          if (_variantsCache.containsKey(p.id)) {
            final cached = _variantsCache[p.id]!;
            final idx = _rows.indexWhere((r) => r.product.id == p.id);
            if (idx >= 0) {
              final row = _rows[idx];
              row.variants = cached;
              final sel = cached.firstWhere(
                (v) => v.id == row.selectedVariantId,
                orElse: () => cached.first,
              );
              row.selectedVariantId = sel.id;
              row.priceC.text = (sel.price ?? 0.0).toStringAsFixed(2);
            }
            return;
          }

          _variantTokens[p.id]?.cancel('newer variants request');
          final token = CancelToken();
          _variantTokens[p.id] = token;

          final api = context.read<ApiClient>();
          List<ProductVariant> vs = const [];
          try {
            final r = await _dio.get(
              'products/${p.id}/variantsuser',
              queryParameters: {'email': api.session!.email.toString()},
              cancelToken: token,
            );

            dynamic data = r.data;
            if (data is Map && data['data'] is List) data = data['data'];
            if (data is Map && data['variants'] is List)
              data = data['variants'];
            final list = (data is List) ? data : <dynamic>[];

            vs = list.whereType<Map>().map((vv) {
              final v = Map<String, dynamic>.from(vv);
              return ProductVariant(
                id: _asInt(v['id']),
                name: (v['name'] ?? 'Varyant').toString(),
                price: _latestPriceOfMine(v, _myUserId) ??
                    _asDouble(
                        v['user_price'] ?? v['price'] ?? v['average_price']),
                unit: (v['unit'] ?? 'ADET').toString().toUpperCase(),
                sku: v['sku']?.toString(),
                image: v['image']?.toString(),
              );
            }).toList();
          } on DioException catch (e) {
            if (!CancelToken.isCancel(e)) vs = const [];
          } catch (_) {
            vs = const [];
          } finally {
            if (_variantTokens[p.id] == token) {
              _variantTokens.remove(p.id);
            }
          }

          if (vs.isNotEmpty) {
            _variantsCache[p.id] = vs;
            final idx = _rows.indexWhere((r) => r.product.id == p.id);
            if (idx >= 0) {
              final row = _rows[idx];
              row.variants = vs;
              final sel = vs.firstWhere(
                (v) => v.id == row.selectedVariantId,
                orElse: () => vs.first,
              );
              row.selectedVariantId = sel.id;
              row.priceC.text = (sel.price ?? 0.0).toStringAsFixed(2);
            }
          }
        }));

        if (mounted) setState(() {});
        _dataSource.notifyListeners();
      }

      if (_totalRows > 0) {
        _more = (_page * _rowsPerPage) < _totalRows;
      } else {
        _more = products.isNotEmpty;
      }
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      _fetchingMore = false;
      if (mounted) {
        _loadingRows = false;
        setState(() {});
      }
      _dataSource.notifyListeners();
    }
  }

  void _parsePaginationMeta(dynamic root) {
    if (root is Map) {
      if (root['data'] is Map) {
        final d = root['data'];
        if (d is Map) {
          final total = d['total'];
          if (total is num) _totalRows = total.toInt();
          final cur = d['current_page'];
          if (cur is num) _page = cur.toInt();
          final last = d['last_page'];
          if (last is num) _more = _page < last.toInt();
          return;
        }
      }
      final total = root['total'];
      if (total is num) _totalRows = total.toInt();
      final cur = root['current_page'];
      if (cur is num) _page = cur.toInt();
      final last = root['last_page'];
      if (last is num) _more = _page < last.toInt();
    }
  }

  // ----------------- SAVE OPS -----------------
  Future<bool> _saveRow(
    _RowVM row, {
    bool showSuccessSnack = true,
    bool showErrorSnack = true,
  }) async {
    final price = double.tryParse(row.priceC.text.replaceAll(',', '.'));
    final variantId = await _resolveValidVariantId(row);
    if (variantId == null || price == null) {
      if (mounted && showErrorSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Geçersiz varyant veya fiyat')));
      }
      return false;
    }

    final api = context.read<ApiClient>();
    try {
      await _dio.post('user-product-prices/upsert', data: {
        'email': api.session!.email.toString(),
        'product_variant_id': variantId,
        'price': price,
        'active': true,
      });

      row.dirty = false;

      final idx = row.variants.indexWhere((v) => v.id == variantId);
      if (idx >= 0) {
        row.variants[idx] = ProductVariant(
          id: row.variants[idx].id,
          name: row.variants[idx].name,
          unit: row.variants[idx].unit,
          sku: row.variants[idx].sku,
          image: row.variants[idx].image,
          price: price,
        );
        _variantsCache[row.product.id] = row.variants;
      }

      if (mounted && showSuccessSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydedildi: ${row.product.name}')),
        );
      }
      if (mounted) {
        setState(() {});
      }
      return true;
    } catch (e) {
      if (mounted && showErrorSnack) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
      return false;
    } finally {
      _dataSource.notifyListeners();
    }
  }

  Future<int?> _resolveValidVariantId(_RowVM row) async {
    final selected = row.selectedVariantId;
    if (selected == null && row.variants.isNotEmpty) {
      final firstValid = row.variants.firstWhere(
        (v) => v.id > 0,
        orElse: () => row.variants.first,
      );
      row.selectedVariantId = firstValid.id;
    }
    final currentSelected = row.selectedVariantId;
    if (currentSelected == null) return null;

    final isSyntheticOnly = row.variants.length == 1 &&
        row.variants.first.id == row.product.id * 1000;

    if (!isSyntheticOnly &&
        row.variants.any((v) => v.id == currentSelected && v.id > 0)) {
      return currentSelected;
    }

    var fetched = await _fetchVariantsForProduct(row.product.id);
    if (fetched.isEmpty) {
      final created = await _createDefaultVariantForProduct(
          row.product.id, row.product.name);
      if (created != null) {
        fetched = [created];
      }
    }
    if (fetched.isEmpty) return null;

    row.variants = fetched;
    final chosen = fetched.firstWhere(
      (v) => v.id == currentSelected,
      orElse: () => fetched.first,
    );
    row.selectedVariantId = chosen.id;
    if (mounted) setState(() {});
    _dataSource.notifyListeners();
    return chosen.id;
  }

  Future<List<ProductVariant>> _fetchVariantsForProduct(int productId) async {
    try {
      final api = context.read<ApiClient>();
      final r = await _dio.get(
        'products/$productId/variantsuser',
        queryParameters: {'email': api.session!.email.toString()},
      );

      dynamic data = r.data;
      if (data is Map && data['data'] is List) data = data['data'];
      if (data is Map && data['variants'] is List) data = data['variants'];
      final list = (data is List) ? data : <dynamic>[];

      final vs = list
          .whereType<Map>()
          .map((vv) {
            final v = Map<String, dynamic>.from(vv);
            return ProductVariant(
              id: _asInt(v['id']),
              name: (v['name'] ?? 'Varyant').toString(),
              price: _latestPriceOfMine(v, _myUserId) ??
                  _asDouble(
                      v['user_price'] ?? v['price'] ?? v['average_price']),
              unit: (v['unit'] ?? 'ADET').toString().toUpperCase(),
              sku: v['sku']?.toString(),
              image: v['image']?.toString(),
            );
          })
          .where((v) => v.id > 0)
          .toList();

      if (vs.isNotEmpty) {
        _variantsCache[productId] = vs;
      }
      return vs;
    } catch (_) {
      return const [];
    }
  }

  Future<ProductVariant?> _createDefaultVariantForProduct(
      int productId, String productName) async {
    try {
      final r = await _dio.post('products/$productId/variants', data: {
        'name': 'ADET',
        'unit': 'ADET',
        'sku': _buildSku(productName, 'ADET'),
        'active': true,
      });

      final id = _asInt(
        (r.data is Map && r.data['variant'] is Map)
            ? r.data['variant']['id']
            : (r.data is Map && r.data['id'] != null)
                ? r.data['id']
                : 0,
      );
      if (id <= 0) return null;

      return ProductVariant(
        id: id,
        name: 'ADET',
        price: 0.0,
        unit: 'ADET',
        sku: _buildSku(productName, 'ADET'),
        image: null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveAll() async {
    final list = _rows.where((e) => e.dirty).toList();
    if (list.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilecek değişiklik yok')),
      );
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('Ürünler kaydediliyor...'),
        ),
      );
    }

    int ok = 0;
    int fail = 0;
    for (final r in list) {
      final saved = await _saveRow(
        r,
        showSuccessSnack: false,
        showErrorSnack: false,
      );
      if (saved) {
        ok++;
      } else {
        fail++;
      }
    }

    if (!mounted) return;
    if (fail == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncelleme işlemi tamamlandı')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Güncelleme tamamlandı. Başarılı: $ok, Hatalı: $fail',
          ),
        ),
      );
    }
  }

  // ----------------- VARIANT ADD -----------------
  Future<({String name, String unit, double? price})?> _askVariant(
      BuildContext ctx) async {
    final primary = Theme.of(ctx).colorScheme.primary;
    final formKey = GlobalKey<FormState>();
    final nameC = TextEditingController();
    final priceC = TextEditingController();
    String selectedUnit = _unitOptions.first;
    bool saving = false;

    final result =
        await showDialog<({String name, String unit, double? price})>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.playlist_add,
                  color: primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text('Varyant Ekle'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameC,
                    decoration:
                        _proFieldDecoration(context, label: 'Varyant adı *'),
                    autofocus: true,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Varyant adı zorunlu'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedUnit,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(14),
                    decoration: _proFieldDecoration(context, label: 'Birim'),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: primary,
                    ),
                    items: _unitOptions
                        .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                        .toList(),
                    onChanged: (v) =>
                        setS(() => selectedUnit = v ?? selectedUnit),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: priceC,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    decoration: _proFieldDecoration(
                      context,
                      label: 'Başlangıç fiyatı (₺)',
                      hint: 'Opsiyonel',
                    ),
                    style: const TextStyle(color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.of(dialogCtx).pop(null),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: primary),
              onPressed: saving
                  ? null
                  : () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      final raw = priceC.text.trim();
                      final parsed = raw.isEmpty
                          ? null
                          : double.tryParse(raw.replaceAll(',', '.'));
                      setS(() => saving = true);
                      Navigator.of(dialogCtx).pop((
                        name: nameC.text.trim(),
                        unit: selectedUnit,
                        price: parsed
                      ));
                    },
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Ekle'),
            ),
          ],
        ),
      ),
    );

    nameC.dispose();
    priceC.dispose();
    return result;
  }

  Future<void> _addVariantForRow(_RowVM row) async {
    final input = await _askVariant(context);
    if (input == null) return;

    try {
      final create =
          await _dio.post('products/${row.product.id}/variants', data: {
        'name': input.name,
        'unit': input.unit,
        'sku': _buildSku(row.product.name, input.unit),
        'active': true,
      });

      final newId = _asInt(
        (create.data is Map && create.data['variant'] != null)
            ? (create.data['variant']['id'])
            : (create.data is Map && create.data['id'] != null)
                ? create.data['id']
                : 0,
      );

      final api = context.read<ApiClient>();
      if (input.price != null) {
        await _dio.post('user-product-prices/upsert', data: {
          'email': api.session!.email.toString(),
          'product_variant_id': newId,
          'price': input.price,
          'active': true,
        });
      }

      final pv = ProductVariant(
        id: newId,
        name: input.name,
        price: input.price ?? 0.0,
        unit: input.unit,
        sku: null,
        image: null,
      );

      row.variants = [...row.variants, pv];
      row.selectedVariantId = newId;
      row.priceC.text = (pv.price ?? 0.0).toStringAsFixed(2);
      row.dirty = input.price != null ? false : true;

      _variantsCache[row.product.id] = row.variants;

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Varyant eklendi')));
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      _dataSource.notifyListeners();
    }
  }

  // ----------------- PRODUCT ADD -----------------
  Future<void> _addProduct() async {
    await showAddProductSheet(
      context,
      cats: _cats,
      preselectedCatId: _selectedCat,
      unitOptions: _unitOptions,
      onSubmit: _submitProductForm,
    );
  }

  Future<bool> _submitProductForm(AddProductForm form) async {
    try {
      final dio = _dio;

      String? imagePath;
      if (form.imageBytes != null && form.imageName != null) {
        final fd = FormData.fromMap({
          'image': MultipartFile.fromBytes(form.imageBytes!,
              filename: form.imageName!),
        });
        final up = await dio.post('upload', data: fd);
        if (up.data is Map && up.data['path'] is String) {
          imagePath = up.data['path'] as String;
        } else if (up.data is Map &&
            up.data['data'] is Map &&
            up.data['data']['path'] is String) {
          imagePath = up.data['data']['path'] as String;
        }
      }

      final api = context.read<ApiClient>();

      final payload = <String, dynamic>{
        'name': form.name,
        if (form.description != null) 'description': form.description,
        if (imagePath != null) 'image': imagePath,
        'active': true,
        if (form.categoryId != null) 'category_ids': [form.categoryId],
        'email': api.session!.email.toString(),
      };

      int productId = 0;
      try {
        final created = await dio.post('productsfull', data: payload);
        productId = _asInt(
          (created.data is Map &&
                  created.data['product'] is Map &&
                  created.data['product']['id'] != null)
              ? created.data['product']['id']
              : (created.data is Map && created.data['id'] != null)
                  ? created.data['id']
                  : 0,
        );
      } on DioException catch (e) {
        final err = (e.response?.data ?? '').toString().toLowerCase();
        final isSkuDefaultError =
            (err.contains('sku') && err.contains('default value')) ||
                err.contains("field 'sku' doesn't have a default value") ||
                err.contains('field `sku` doesn\'t have a default value') ||
                err.contains('sku doesn\'t have a default value');
        if (!isSkuDefaultError) rethrow;

        final fallbackPayload = <String, dynamic>{
          'name': form.name,
          if (form.description != null) 'description': form.description,
          if (imagePath != null) 'image': imagePath,
          if (form.categoryId != null) 'category_id': form.categoryId,
          'active': true,
        };
        final created2 =
            await dio.post(AppConfig.createProductPath, data: fallbackPayload);
        productId = _asInt(
          (created2.data is Map && created2.data['id'] != null)
              ? created2.data['id']
              : (created2.data is Map &&
                      created2.data['product'] is Map &&
                      created2.data['product']['id'] != null)
                  ? created2.data['product']['id']
                  : 0,
        );
      }
      if (productId <= 0) throw Exception('Product ID alınamadı.');

      // productsfull içinde varyant ekleme akışı bazı ortamlarda sku alanını
      // yutabiliyor. Bu yüzden varyantı 2. adımda explicit endpoint ile oluştur.
      if (form.variantName != null || form.variantPrice != null) {
        final unit = (form.variantName ?? 'ADET').toUpperCase();
        final variantRes =
            await dio.post('products/$productId/variants', data: {
          'name': unit,
          'unit': unit,
          'sku': _buildSku(form.name, unit),
          'active': true,
        });

        final variantId = _asInt(
          (variantRes.data is Map && variantRes.data['variant'] is Map)
              ? variantRes.data['variant']['id']
              : (variantRes.data is Map && variantRes.data['id'] != null)
                  ? variantRes.data['id']
                  : 0,
        );

        if (variantId > 0 && form.variantPrice != null) {
          await dio.post('user-product-prices/upsert', data: {
            'email': api.session!.email.toString(),
            'product_variant_id': variantId,
            'price': form.variantPrice,
            'active': true,
          });
        }
      }

      _firstRowIndex = 0;
      await _fetchRows(reset: true, page: 1);

      if (!mounted) return true;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ürün eklendi')));
      return true;
    } on DioException catch (e) {
      if (!mounted) return false;
      final status = e.response?.statusCode;
      final body = e.response?.data;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Hata ($status): ${body is String ? body : body.toString()}')),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Hata: $e')));
      return false;
    } finally {
      _dataSource.notifyListeners();
    }
  }

  Future<String?> _uploadImageBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    final fd = FormData.fromMap({
      'image': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final up = await _dio.post('upload', data: fd);
    final data = up.data;
    if (data is Map && data['path'] is String) return data['path'] as String;
    if (data is Map &&
        data['data'] is Map &&
        (data['data'] as Map)['path'] is String) {
      return (data['data'] as Map)['path'] as String;
    }
    return null;
  }

  Future<void> _updateProductImage(_RowVM row) async {
    if (_updatingImageIds.contains(row.product.id)) return;

    Uint8List? bytes;
    String? filename;
    await pickImageBytes(
      onPicked: (pickedBytes, pickedName) {
        bytes = pickedBytes;
        filename = pickedName;
      },
    );
    if (bytes == null || filename == null) return;

    setState(() => _updatingImageIds.add(row.product.id));
    _dataSource.notifyListeners();

    try {
      final imagePath =
          await _uploadImageBytes(bytes: bytes!, filename: filename!);
      if (imagePath == null) {
        throw Exception('Yüklenen resim yolu alınamadı.');
      }

      await context.read<ApiClient>().updateProduct(
            row.product.id,
            ProductUpdate(image: imagePath),
          );

      row.product = row.product.copyWith(image: AppConfig.imageUrl(imagePath));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${row.product.name} resmi güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resim güncellenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingImageIds.remove(row.product.id));
      } else {
        _updatingImageIds.remove(row.product.id);
      }
      _dataSource.notifyListeners();
    }
  }

  // ----------------- HELPERS -----------------
  String _money(num? v) => ((v ?? 0).toDouble()).toStringAsFixed(2);

  String _variantLabel(ProductVariant v) {
    final name = (v.name ?? 'Varyant').toString();
    final unit = (v.unit ?? 'ADET').toString().toUpperCase();
    final price = _money(v.price);
    return '$name ($unit) — ₺$price';
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

      int _asIntLocal(dynamic v) {
        if (v is int) return v;
        if (v is String) return int.tryParse(v) ?? 0;
        if (v is num) return v.toInt();
        return 0;
      }

      double _asDoubleLocal(dynamic v) {
        if (v is double) return v;
        if (v is int) return v.toDouble();
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
        return 0.0;
      }

      final id = _asIntLocal(j['id']);
      final name = (j['name'] ?? j['title'] ?? '').toString();
      final catId = _asIntLocal(j['category_id'] ?? j['categoryId']);

      final imagePath = j['image']?.toString() ?? '';
      final imageUrl = AppConfig.imageUrl(imagePath);

      List<ProductVariant> variants = [];
      if (j['variants'] is List) {
        variants = (j['variants'] as List).whereType<Map>().map((vv) {
          final v = Map<String, dynamic>.from(vv);
          return ProductVariant(
            id: _asIntLocal(v['id']),
            name: (v['name'] ?? 'Standart').toString(),
            price: _asDoubleLocal(v['price'] ?? v['average_price']),
            unit: (v['unit'] ?? 'ADET').toString().toUpperCase(),
            sku: v['sku']?.toString(),
            image: v['image']?.toString(),
          );
        }).toList();
      } else {
        variants = [
          ProductVariant(
            id: id,
            name: (j['variant_name'] ?? 'Standart').toString(),
            price: _asDoubleLocal(j['price']),
            unit: (j['unit'] ?? 'ADET').toString().toUpperCase(),
            sku: j['sku']?.toString(),
            image: j['variant_image']?.toString(),
          ),
        ];
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

  double? _latestPriceOfMine(Map<String, dynamic> v, int? myId) {
    if (myId == null) return null;
    final list = v['prices'];
    if (list is! List) return null;

    final mine = list.whereType<Map>().where((p) {
      final uid = _asInt(p['user_id']);
      return uid == myId;
    }).toList();

    if (mine.isEmpty) return null;

    mine.sort((a, b) => _asInt(b['id']).compareTo(_asInt(a['id'])));
    return _asDouble(mine.first['price']);
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final cs = HaldekiUI.lightScheme(context).copyWith(
      primary: _primaryStrong,
      secondary: _primaryStrong,
    );

    final themed = HaldekiUI.withRectButtons(context, cs).copyWith(
      scaffoldBackgroundColor: _bg,
      textTheme: Theme.of(context)
          .textTheme
          .apply(bodyColor: Colors.black, displayColor: Colors.black),
      primaryTextTheme: Theme.of(context).primaryTextTheme.apply(
            bodyColor: Colors.black,
            displayColor: Colors.black,
          ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: _ctrlPad,
        labelStyle: const TextStyle(color: Colors.black87),
        hintStyle: const TextStyle(color: Colors.black87),
        prefixStyle: const TextStyle(color: Colors.black87),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_ctrlRadius),
          borderSide: const BorderSide(color: _borderC),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_ctrlRadius),
          borderSide: const BorderSide(color: _borderC),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_ctrlRadius),
          borderSide: BorderSide(color: cs.primary, width: 1.6),
        ),
      ),
    );

    final dirtyCount = _rows.where((e) => e.dirty).length;

    return Theme(
      data: themed,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopHeader(context, dirtyCount),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final columns = c.maxWidth > 1180 ? 4 : 2;
                    final spacing = 10.0;
                    final itemWidth =
                        (c.maxWidth - (spacing * (columns - 1))) / columns;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _statCard(
                            context,
                            icon: Icons.inventory_2_outlined,
                            title: 'Toplam Ürün',
                            value:
                                '${_totalRows > 0 ? _totalRows : _rows.length}',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _statCard(
                            context,
                            icon: Icons.edit_note,
                            title: 'Bekleyen Değişiklik',
                            value: '$dirtyCount',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _statCard(
                            context,
                            icon: Icons.category_outlined,
                            title: 'Kategori',
                            value: _selectedCat == null
                                ? 'Tum Kategoriler'
                                : 'Secili',
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _statCard(
                            context,
                            icon: Icons.badge_outlined,
                            title: 'Kullanici',
                            value: (_myUserId ?? 0).toString(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildFiltersCard(context, dirtyCount),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _errorBanner(context, _error!),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildTableCard(context, dirtyCount),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context, int dirtyCount) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, cs.primary.withOpacity(.06)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _borderC),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.primary.withOpacity(.22)),
                  ),
                  child: Icon(Icons.price_change_outlined, color: cs.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fiyat Listesi',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Profesyonel fiyat yonetimi: filtrele, duzenle, kaydet',
                        style: TextStyle(color: Colors.black87, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (dirtyCount > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.primary.withOpacity(.20)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          '$dirtyCount degisiklik',
                          style: TextStyle(
                              color: cs.primary, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _loadingRows
                      ? null
                      : () async {
                          _firstRowIndex = 0;
                          await _fetchRows(reset: true, page: 1);
                        },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Yenile'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    side: const BorderSide(color: _borderC),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Yeni Urun'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _borderC),
                  ),
                  child: Text(
                    '${_totalRows > 0 ? _totalRows : _rows.length} kayit',
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outline(cs)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _soft(cs.primary, .10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _soft(cs.primary, .18)),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersCard(BuildContext context, int dirtyCount) {
    final cs = Theme.of(context).colorScheme;
    final hasQuery = _search.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_r16),
        border: Border.all(color: _outline(cs)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtreler ve Toplu Islem',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _loadingCats
                  ? const SizedBox(
                      width: 240,
                      child: Text(
                        'Kategoriler yukleniyor...',
                        style: TextStyle(color: Colors.black87),
                      ),
                    )
                  : SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<int?>(
                        value: _selectedCat,
                        borderRadius: BorderRadius.circular(14),
                        decoration: _proFieldDecoration(
                          context,
                          label: 'Kategori',
                          prefixIcon: Icon(
                            Icons.category_outlined,
                            color: cs.primary,
                            size: 20,
                          ),
                        ),
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: cs.primary,
                        ),
                        onChanged: (v) async {
                          setState(() => _selectedCat = v);
                          _firstRowIndex = 0;
                          await _fetchRows(reset: true, page: 1);
                        },
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Tumu'),
                          ),
                          ..._cats.map(
                            (c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          ),
                        ],
                      ),
                    ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _outline(cs)),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Oran (%)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 72,
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _proFieldDecoration(
                          context,
                          hint: '%',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Yukselt',
                      icon: const Icon(Icons.trending_up),
                      onPressed: () => applyRate(increase: true),
                    ),
                    IconButton(
                      tooltip: 'Dusur',
                      icon: const Icon(Icons.trending_down),
                      onPressed: () => applyRate(increase: false),
                    ),
                  ],
                ),
              ),
              if (dirtyCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _soft(cs.primary, .10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _soft(cs.primary, .22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Degisiklik: $dirtyCount',
                        style: TextStyle(
                            color: cs.primary, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _loadingRows
                    ? null
                    : () async {
                        _search.clear();
                        setState(() {});
                        _firstRowIndex = 0;
                        await _fetchRows(reset: true, page: 1);
                      },
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Temizle'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  side: const BorderSide(color: _borderC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _search,
            decoration: _proFieldDecoration(
              context,
              hint: 'Ürün / varyant ara…',
              prefixIcon: Icon(Icons.search, color: cs.primary),
            ).copyWith(
              suffixIcon: hasQuery
                  ? IconButton(
                      tooltip: 'Temizle',
                      onPressed: () async {
                        _search.clear();
                        setState(() {});
                        _firstRowIndex = 0;
                        await _fetchRows(reset: true, page: 1);
                      },
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
            onSubmitted: (_) => _onSearch(),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context, String msg) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(.30),
        borderRadius: BorderRadius.circular(_r16),
        border: Border.all(color: cs.error.withOpacity(.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg, maxLines: 2, overflow: TextOverflow.ellipsis)),
          TextButton.icon(
            onPressed: () async {
              _firstRowIndex = 0;
              await _fetchRows(reset: true, page: 1);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard(BuildContext context, int dirtyCount) {
    final cs = Theme.of(context).colorScheme;

    final headingBg = cs.primary.withOpacity(.04); // ✅ primary tint
    final divider = const Color(0xFFE9ECF3);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_r16),
        border: Border.all(color: _outline(cs)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_r16),
        child: _loadingRows && _rows.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : Theme(
                data: Theme.of(context).copyWith(dividerColor: divider),
                child: PaginatedDataTable2(
                  columnSpacing: 20,
                  horizontalMargin: 16,
                  minWidth: 980,
                  dividerThickness: .9,
                  border: TableBorder(
                    top: BorderSide(color: divider),
                    bottom: BorderSide(color: divider),
                    left: BorderSide(color: divider),
                    right: BorderSide(color: divider),
                    horizontalInside: BorderSide(color: divider),
                    verticalInside: BorderSide(color: divider),
                  ),
                  headingRowColor: WidgetStatePropertyAll(headingBg),
                  headingTextStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                  headingRowHeight: 50,
                  dataRowHeight: 86,
                  showFirstLastButtons: true,
                  wrapInCard: false,
                  fit: FlexFit.tight,
                  header: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Fiyatlar',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.08),
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: cs.primary.withOpacity(.18)),
                        ),
                        child: Text(
                          '${_totalRows > 0 ? _totalRows : _rows.length} kayıt',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (_fetchingMore)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: dirtyCount > 0 ? _saveAll : null,
                        icon: const Icon(Icons.save, size: 18),
                        label: Text(
                          dirtyCount > 0
                              ? 'Hepsini Kaydet ($dirtyCount)'
                              : 'Hepsini Kaydet',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: cs.surfaceVariant,
                          disabledForegroundColor: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  rowsPerPage: _rowsPerPage,
                  availableRowsPerPage: const [10, 20, 50, 100, 200],
                  onRowsPerPageChanged: (v) async {
                    if (v == null) return;
                    setState(() => _rowsPerPage = v);
                    _firstRowIndex = 0;
                    await _fetchRows(reset: true, page: 1);
                  },
                  onPageChanged: (firstRowIndex) async {
                    _firstRowIndex = firstRowIndex;
                    final page = (firstRowIndex ~/ _rowsPerPage) + 1;
                    await _fetchRows(reset: true, page: page);
                  },
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  showCheckboxColumn: false,
                  columns: [
                    DataColumn2(
                      label: const Text('Ürün'),
                      size: ColumnSize.L,
                      onSort: (i, asc) {
                        setState(() {
                          _sortColumnIndex = i;
                          _sortAscending = asc;
                          _rows.sort((a, b) => asc
                              ? a.product.name
                                  .toLowerCase()
                                  .compareTo(b.product.name.toLowerCase())
                              : b.product.name
                                  .toLowerCase()
                                  .compareTo(a.product.name.toLowerCase()));
                        });
                        _dataSource.notifyListeners();
                      },
                    ),
                    const DataColumn2(
                        label: Text('Varyant'), size: ColumnSize.L),
                    const DataColumn2(label: Text(''), size: ColumnSize.S),
                    const DataColumn2(
                        label: Text('Fiyat (₺)'), size: ColumnSize.S),
                    const DataColumn2(label: Text(''), size: ColumnSize.S),
                  ],
                  source: _dataSource,
                ),
              ),
      ),
    );
  }
}

// ================== DataTableSource (SERVER PAGING) ==================
class _PriceDataSource extends DataTableSource {
  final List<_RowVM> Function() getRows;
  final int? Function() myUserId;
  final String Function(ProductVariant) variantLabel;

  final Future<void> Function(_RowVM) onSaveRow;
  final Future<void> Function(_RowVM) onAddVariant;
  final Future<void> Function(_RowVM) onUpdateImage;
  final VoidCallback? onChanged;

  // ✅ server paging
  final int Function() getFirstRowIndex;
  final int Function() getTotalRows;

  // ✅ theme
  final Color Function() getPrimary;

  _PriceDataSource({
    required this.getRows,
    required this.myUserId,
    required this.variantLabel,
    required this.onSaveRow,
    required this.onAddVariant,
    required this.onUpdateImage,
    this.onChanged,
    required this.getFirstRowIndex,
    required this.getTotalRows,
    required this.getPrimary,
  });

  void _tick() {
    notifyListeners();
    onChanged?.call();
  }

  @override
  DataRow? getRow(int index) {
    final rows = getRows();
    final localIndex = index - getFirstRowIndex();
    if (localIndex < 0 || localIndex >= rows.length) return null;

    final row = rows[localIndex];

    final selected = row.variants.isNotEmpty
        ? row.variants.firstWhere(
            (v) => v.id == row.selectedVariantId,
            orElse: () => row.variants.first,
          )
        : null;

    final stripe = localIndex.isEven;
    final primary = getPrimary();

    return DataRow.byIndex(
      index: index,
      color: MaterialStateProperty.resolveWith((states) {
        // ✅ Hover + Focus highlight (theme primary tint)
        if (states.contains(MaterialState.hovered) ||
            states.contains(MaterialState.focused)) {
          return primary.withOpacity(.06);
        }
        return stripe ? const Color(0xFFFCFDFE) : Colors.white;
      }),
      cells: [
        // Ürün
        DataCell(Row(
          children: [
            // ✅ Dirty indicator
            if (row.dirty)
              Container(
                width: 4,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: getPrimary(),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FA),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border.fromBorderSide(
                    BorderSide(color: Color(0xFFE6E8EF)),
                  ),
                ),
                child: (row.product.image).toString().isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          row.product.image.startsWith('http')
                              ? row.product.image
                              : AppConfig.imageUrl(row.product.image),
                          width: 50,
                          height: 50,
                          cacheWidth: 100,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.image_not_supported, size: 20),
                        ),
                      )
                    : const Icon(Icons.inventory_2_outlined, size: 22),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.product.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      fontSize: 16,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaTag(
                        text: '${row.variants.length} varyant',
                        textColor: Colors.black87,
                        bgColor: const Color(0xFFF2F4F8),
                      ),
                      if (selected != null)
                        _metaTag(
                          text: selected.name,
                          textColor: primary,
                          bgColor: primary.withOpacity(.10),
                        ),
                      Tooltip(
                        message: 'Ürün resmini güncelle',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () async {
                            await onUpdateImage(row);
                            _tick();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.image_outlined,
                              size: 18,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        )),

        // Varyant dropdown
        DataCell(SizedBox(
          width: 320,
          child: Builder(
            builder: (ctx) {
              final cs = Theme.of(ctx).colorScheme;
              return DropdownButtonFormField<int>(
                value: row.selectedVariantId ?? selected?.id,
                isExpanded: true,
                menuMaxHeight: 340,
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(14),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: Icon(Icons.unfold_more_rounded,
                      color: cs.primary, size: 18),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE6E8EF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.primary, width: 1.8),
                  ),
                ),
                items: row.variants
                    .map(
                      (v) => DropdownMenuItem<int>(
                        value: v.id,
                        child: Text(
                          variantLabel(v),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final nv = row.variants.firstWhere((e) => e.id == val,
                      orElse: () => row.variants.first);
                  row.selectedVariantId = val;
                  row.priceC.text = (nv.price ?? 0.0).toStringAsFixed(2);
                  row.dirty = true;
                  _tick();
                },
              );
            },
          ),
        )),

        // Varyant ekle
        DataCell(
          OutlinedButton.icon(
            onPressed: () async {
              await onAddVariant(row);
              _tick();
            },
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Varyant'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: primary.withOpacity(.30)),
            ),
          ),
        ),

        // Fiyat input
        DataCell(
          SizedBox(
            width: 190,
            child: Builder(
              builder: (ctx) {
                final cs = Theme.of(ctx).colorScheme;
                return TextField(
                  controller: row.priceC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                  ],
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '₺ ',
                    prefixStyle: TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.w700),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE6E8EF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: cs.primary, width: 1.6),
                    ),
                    filled: row.dirty,
                    fillColor:
                        row.dirty ? cs.primary.withOpacity(.10) : Colors.white,
                  ),
                  onChanged: (_) {
                    row.dirty = true;
                    _tick();
                  },
                  onSubmitted: (_) async {
                    await onSaveRow(row);
                    _tick();
                  },
                );
              },
            ),
          ),
        ),

        // Kaydet
        DataCell(
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (ctx) {
                final cs = Theme.of(ctx).colorScheme;
                return FilledButton.icon(
                  onPressed: row.dirty
                      ? () async {
                          await onSaveRow(row);
                          _tick();
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    minimumSize: const Size(124, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    backgroundColor: row.dirty ? cs.primary : cs.surfaceVariant,
                    foregroundColor: row.dirty ? Colors.white : Colors.black87,
                  ),
                  icon: const Icon(Icons.check, size: 22),
                  label: const Text(
                    'Kaydet',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  int get rowCount => getTotalRows();

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;

  Widget _metaTag({
    required String text,
    required Color textColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
