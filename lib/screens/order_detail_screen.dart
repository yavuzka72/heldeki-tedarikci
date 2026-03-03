import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/api_client.dart';
import '../utils/format.dart';

/// Sevkiyat adımı görselleştirme durumları
enum _StageState { done, current, todo }

class OrderDetailScreen extends StatefulWidget {
  final String orderNumber;
  const OrderDetailScreen({super.key, required this.orderNumber});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _loading = true;
  String? _error;
  _OrderVM? _order; // ViewModel

  bool _saving = false; // ✅ Kaydetme esnasında ikinci kez tıklamayı engelle

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _order = null;
    });

    final dio = context.read<ApiClient>().dio;

    Map<String, dynamic>? _firstOrder(dynamic data) {
      if (data is List && data.isNotEmpty) {
        return Map<String, dynamic>.from(data.first as Map);
      }
      if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        final d = m['data'];
        if (d is List && d.isNotEmpty) {
          return Map<String, dynamic>.from(d.first as Map);
        }
        return m;
      }
      return null;
    }

    try {
      _OrderVM? found;
      final api = context.read<ApiClient>();

      // 1) Public endpoint (tedarikçi)
      try {
        final r = await dio.post(
          AppConfig.dealerOrderDetailPath,
          data: {
            'email': api.session!.email.toString(),
            'order_number': widget.orderNumber,
          },
        );
        final raw = _firstOrder(r.data);
        if (raw != null) {
          final parsed = _parseOrderPayload(raw);
          if (parsed.items.isNotEmpty) found = parsed;
        }
      } catch (_) {}

      // 2) /orders/by-number/{number}
      if (found == null) {
        try {
          final r2 = await dio.get('orders/by-number/${widget.orderNumber}');
          final raw = _firstOrder(r2.data);
          if (raw != null) {
            final parsed = _parseOrderPayload(raw);
            if (parsed.items.isNotEmpty) found = parsed;
          }
        } catch (_) {}
      }

      // 3) previous-orders?number=... → id → /orders/{id}
      if (found == null) {
        try {
          final r3 = await dio.get(
            'previous-orders',
            queryParameters: {
              'number': widget.orderNumber,
              'page': 1,
            },
          );
          final list = _extractList(r3.data);
          if (list.isNotEmpty) {
            final first = Map<String, dynamic>.from(list.first as Map);
            final id =
                (first['id'] ?? first['_id'] ?? first['order_id'])?.toString();
            if (id != null && id.isNotEmpty) {
              try {
                final r4 = await dio.get('orders/$id');
                final raw = _firstOrder(r4.data) ?? first;
                final parsed = _parseOrderPayload(raw);
                if (parsed.items.isNotEmpty) found = parsed;
              } catch (_) {
                final parsed = _parseOrderPayload(first);
                if (parsed.items.isNotEmpty) found = parsed;
              }
            } else {
              final parsed = _parseOrderPayload(first);
              if (parsed.items.isNotEmpty) found = parsed;
            }
          }
        } catch (_) {}
      }

      if (found == null) {
        setState(() {
          _error = 'Sipariş bulunamadı';
          _loading = false;
        });
        return;
      }

      setState(() {
        _order = found;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Sipariş yüklenemedi';
        _loading = false;
      });
    }
  }

  // ---- Payload yardımcıları ----
  List _extractList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map) {
      if (payload['data'] is List) return payload['data'];
      if (payload['results'] is List) return payload['results'];
    }
    return const [];
  }

  _OrderVM _parseOrderPayload(dynamic payload) {
    final m = payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};

    String pickStr(List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        final s = v.toString();
        if (s.isNotEmpty) return s;
      }
      return fallback;
    }

    double pickNum(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        if (v is num) return v.toDouble();
        if (v is String) {
          final d = double.tryParse(v.replaceAll(',', '.'));
          if (d != null) return d;
        }
      }
      return 0.0;
    }

    DateTime pickDate(List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String) {
          final d = DateTime.tryParse(v);
          if (d != null) return d;
        }
        if (v is int) {
          final s = v.toString();
          if (s.length >= 13) {
            return DateTime.fromMillisecondsSinceEpoch(v);
          }
          if (s.length >= 10) {
            return DateTime.fromMillisecondsSinceEpoch(v * 1000);
          }
        }
      }
      return DateTime.now();
    }

    String normalizeStatus(String s) {
      final t = s.toLowerCase().trim();
      if (t.contains('hazır')) return 'hazırlanıyor';
      if (t.contains('sevk')) return 'sevk edildi';
      if (t.contains('yol')) return 'yolda';
      if (t.contains('teslim')) return 'teslim edildi';
      if (t.contains('iptal') || t.contains('cancel')) return 'iptal';
      return s;
    }

    final orderNumber =
        pickStr(['orderNumber', 'order_number', 'number', 'code', 'no']);
    final status =
        normalizeStatus(pickStr(['status', 'state', 'order_status']));
    final createdAt =
        pickDate(['createdAt', 'created_at', 'date', 'ordered_at']);
    final address = pickStr(
      [
        'shippingAddress',
        'shipping_address',
        'address',
        'delivery_address',
      ],
    );
    final createdBy = pickStr(
      [
        'createdByName',
        'created_by_name',
        'user_name',
        'customer_name',
        'createdBy',
      ],
    );

    // Kalemler
    List itemsSrc = const [];
    for (final k in ['items', 'order_items', 'lines', 'cart_items']) {
      final v = m[k];
      if (v is List) {
        itemsSrc = v;
        break;
      }
    }

    List<_OrderItemVM> items =
        itemsSrc.whereType<Map>().map<_OrderItemVM>((raw0) {
      final raw = Map<String, dynamic>.from(raw0);

      String pTitle() {
        final pn = raw['productTitle'] ??
            raw['product_title'] ??
            raw['product_name'] ??
            raw['name'] ??
            '';
        final vn = raw['variantName'] ??
            raw['variant_name'] ??
            raw['product_variant_name'];
        return vn == null
            ? pn.toString()
            : '${pn.toString()} - ${vn.toString()}';
      }

      double pickNumItem(List<String> keys) {
        for (final k in keys) {
          final v = raw[k];
          if (v == null) continue;
          if (v is num) return v.toDouble();
          if (v is String) {
            final d = double.tryParse(v.replaceAll(',', '.'));
            if (d != null) return d;
          }
        }
        return 0.0;
      }

      int pickIntItem(List<String> keys) {
        for (final k in keys) {
          final v = raw[k];
          if (v == null) continue;
          if (v is int) return v;
          if (v is num) return v.toInt();
          if (v is String) {
            final i = int.tryParse(v);
            if (i != null) return i;
          }
        }
        return 0;
      }

      final productId = pickIntItem(['product_id', 'productId', 'product']);
      final variantId =
          pickIntItem(['product_variant_id', 'variant_id', 'variantId']);

      final qtyCases =
          pickNumItem(['qtyCases', 'quantity_cases', 'qty', 'quantity']);
      final kgPerCase = pickNumItem([
        'approxKgPerCase',
        'kg_per_case',
        'weight_per_case',
        'weightPerCase'
      ]);
      final pricePerKg = pickNumItem(
          ['pricePerKg', 'unit_price', 'price_per_kg', 'priceKg', 'price']);

      double lineTotal = pickNumItem([
        'lineTotal',
        'line_total',
        'total',
        'amount',
        'line_amount',
        'total_price'
      ]);

      // Eğer lineTotal 0 ama unit_price + qty varsa hesapla
      if (lineTotal == 0.0 && pricePerKg > 0) {
        final kg =
            (kgPerCase > 0 ? kgPerCase : 1.0) * (qtyCases > 0 ? qtyCases : 1.0);
        lineTotal = (kg * pricePerKg);
      }

      return _OrderItemVM(
        productId: productId == 0 ? null : productId,
        variantId: variantId == 0 ? null : variantId,
        productTitle: pTitle(),
        qtyCases: qtyCases == 0 ? null : qtyCases,
        approxKgPerCase: kgPerCase == 0 ? null : kgPerCase,
        pricePerKg: pricePerKg == 0 ? null : pricePerKg,
        lineTotal: lineTotal,
      );
    }).toList();

    // Toplamlar — Tedarikçi tarafı için HER ZAMAN KALEMLERDEN ve %1 KDV
    double itemsSum = 0;
    for (final it in items) {
      itemsSum += it.lineTotal;
    }

    final subtotal = itemsSum;
    final vat = subtotal * 0.01; // ✅ %1 KDV
    final grand = double.parse((subtotal + vat).toStringAsFixed(2));

    return _OrderVM(
      orderNumber: orderNumber.isEmpty ? '—' : orderNumber,
      status: status.isEmpty ? '—' : status,
      createdAt: createdAt,
      shippingAddress: address.isEmpty ? null : address,
      createdByName: createdBy.isEmpty ? '—' : createdBy,
      items: items,
      totals: _Totals(subtotal, vat, grand),
    );
  }

  // ---- Kalemleri güncelle / toplamları yeniden hesapla (%1 KDV) ----
  void _updateItems(List<_OrderItemVM> newItems) {
    final subtotal = newItems.fold<double>(0, (sum, it) => sum + it.lineTotal);
    final vat = subtotal * 0.01; // ✅ %1 KDV
    final grand = double.parse((subtotal + vat).toStringAsFixed(2));

    setState(() {
      _order = _order!.copyWith(
        items: newItems,
        totals: _Totals(subtotal, vat, grand),
      );
    });
  }

  void _removeItem(int index) {
    final current = _order;
    if (current == null) return;
    final items = List<_OrderItemVM>.from(current.items);
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    _updateItems(items);
  }

  Future<void> _showItemDialog({int? index}) async {
    final current = _order;
    if (current == null) return;

    final bool isEdit = index != null;
    final int? editIndex = index;
    final _OrderItemVM? existing =
        (isEdit && editIndex != null) ? current.items[editIndex] : null;

    final titleCtrl = TextEditingController(text: existing?.productTitle ?? '');
    final qtyCtrl = TextEditingController(
        text: existing?.qtyCases?.toStringAsFixed(0) ?? '');
    final kgCtrl = TextEditingController(
        text: existing?.approxKgPerCase?.toStringAsFixed(2) ?? '');
    final priceCtrl = TextEditingController(
        text: existing?.pricePerKg?.toStringAsFixed(2) ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isEdit ? 'Ürünü düzenle' : 'Ürün ekle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ürün adı',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Koli / Miktar',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: kgCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'kg / koli (opsiyonel)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Birim Fiyat (kg/adet)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim().isEmpty
                    ? 'Ürün'
                    : titleCtrl.text.trim();
                final qty =
                    double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;
                final kg =
                    double.tryParse(kgCtrl.text.replaceAll(',', '.')) ?? 0;
                final price =
                    double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0;

                double lineTotal;
                if (qty > 0 && price > 0) {
                  final factor = kg > 0 ? kg : 1.0;
                  lineTotal = qty * factor * price;
                } else {
                  lineTotal = existing?.lineTotal ?? 0.0;
                }

                final newItem = _OrderItemVM(
                  productId: existing?.productId,
                  variantId: existing?.variantId,
                  productTitle: title,
                  qtyCases: qty == 0 ? null : qty,
                  approxKgPerCase: kg == 0 ? null : kg,
                  pricePerKg: price == 0 ? null : price,
                  lineTotal: lineTotal,
                );

                final items = List<_OrderItemVM>.from(current.items);
                if (isEdit && editIndex != null) {
                  items[editIndex] = newItem;
                } else {
                  items.add(newItem);
                }

                _updateItems(items);
                Navigator.of(ctx).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_order == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 64),
              const SizedBox(height: 8),
              Text(_error ?? 'Sipariş bulunamadı'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Geri'),
              ),
            ],
          ),
        ),
      );
    }

    final order = _order!;
    final totals = order.totals;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, box) {
          final isWide = box.maxWidth >= 980;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık & aksiyonlar
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Sipariş Detayı',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        SelectableText(
                          order.orderNumber,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        _statusChip(order.status),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Geri'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // İçerik
              if (isWide)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sol: Kalemler
                      Expanded(child: _itemsCard(order)),
                      const SizedBox(width: 16),
                      // Sağ: iki ayrı kart
                      SizedBox(
                        width: 360,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _summaryCard(context, order, totals),
                            const SizedBox(height: 12),
                            _shipmentCard(order.status),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      _summaryCard(context, order, totals),
                      const SizedBox(height: 12),
                      _shipmentCard(order.status),
                      const SizedBox(height: 16),
                      _itemsCard(order, height: 420),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ================== Kartlar ==================

  /// Kalemler kartı: geniş ekranda Expanded, mobilde sabit yükseklik
  Widget _itemsCard(_OrderVM order, {double? height}) {
    final table = _itemsTable(order);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Kalemler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (height == null)
              Expanded(child: table)
            else
              SizedBox(height: height, child: table),
          ],
        ),
      ),
    );
  }

  /// Ürün satırlarını yatay kaydırılabilir tablo olarak üretir
  Widget _itemsTable(_OrderVM order) {
    return LayoutBuilder(
      builder: (context, box) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.2),
                4: FlexColumnWidth(1.2),
                5: IntrinsicColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                // Header
                TableRow(
                  decoration:
                      BoxDecoration(color: Colors.black.withOpacity(.04)),
                  children: [
                    _headerCell('Ürün', Alignment.centerLeft),
                    _headerCell('Koli / Miktar', Alignment.centerRight),
                    _headerCell('kg/koli', Alignment.centerRight),
                    _headerCell('Fiyat/kg', Alignment.centerRight),
                    _headerCell('Tutar', Alignment.centerRight),
                    _headerCell('İşlem', Alignment.centerRight),
                  ],
                ),
                // Satırlar
                for (int i = 0; i < order.items.length; i++)
                  _itemRow(order.items[i], index: i),
              ],
            ),
          ),
        );
      },
    );
  }

  TableRow _itemRow(_OrderItemVM it, {required int index}) {
    return TableRow(
      children: [
        _bodyCell(it.productTitle, Alignment.centerLeft),
        _bodyCell(
          it.qtyCases?.toStringAsFixed(0) ?? '—',
          Alignment.centerRight,
        ),
        _bodyCell(
          it.approxKgPerCase?.toStringAsFixed(2) ?? '—',
          Alignment.centerRight,
        ),
        _bodyCell(
          it.pricePerKg == null ? '—' : tl(it.pricePerKg!),
          Alignment.centerRight,
        ),
        _bodyCell(tl(it.lineTotal), Alignment.centerRight),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Düzenle',
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _showItemDialog(index: index),
              ),
              IconButton(
                tooltip: 'Sil',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeItem(index),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String text, Alignment alignment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _bodyCell(String text, Alignment alignment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Align(
        alignment: alignment,
        child: Text(text),
      ),
    );
  }

  /// Özet (durum, tarih, adres, oluşturan + toplamlar)
  Widget _summaryCard(BuildContext context, _OrderVM order, _Totals totals) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Özet', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _kv('Durum', _statusLabel(order.status)),
            _kv('Tarih', dt(order.createdAt)),
            if (order.shippingAddress != null)
              _kv('Adres', order.shippingAddress!),
            _kv('Oluşturan', order.createdByName),
            const Divider(height: 24),
            _kv('Ara Toplam', tl(totals.subtotal)),
            _kv('%1 KDV', tl(totals.vat)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Genel Toplam',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(tl(totals.grandTotal),
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveOrderToBackend,
                icon: const Icon(Icons.save),
                label: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveOrderToBackend() async {
    final order = _order;
    if (order == null) return;
    if (_saving) return;

    setState(() => _saving = true);

    try {
      final dio = context.read<ApiClient>().dio;

      final itemsJson = order.items.map((it) {
        final double qtyCases = (it.qtyCases ?? 0).toDouble();
        final double unitPrice = (it.pricePerKg ?? 0).toDouble();
        final double lineTotal = it.lineTotal;

        // quantity: kg / adet gibi düşün → koli * kg/koli
        double quantity;
        if (qtyCases > 0) {
          final double factor =
              (it.approxKgPerCase == null || it.approxKgPerCase == 0)
                  ? 1.0
                  : it.approxKgPerCase!.toDouble();
          quantity = qtyCases * factor;
        } else if (unitPrice > 0) {
          // eski kayıtlarda sadece total + unit_price varsa buradan çıkar
          quantity = lineTotal / unitPrice;
        } else {
          quantity = 0;
        }

        return {
          // backend order_items → product_variant_id üzerinden product_id’yi zaten buluyor
          'product_variant_id': it.variantId ?? it.productId,
          'quantity': double.parse(quantity.toStringAsFixed(3)),
          'unit_price': double.parse(unitPrice.toStringAsFixed(2)),
          'total_price': double.parse(lineTotal.toStringAsFixed(2)),
        };
      }).toList();

      final payload = {
        'order_number': order.orderNumber,
        'items': itemsJson,
        'subtotal':
            double.parse(order.totals.subtotal.toStringAsFixed(2)), // temiz
        'vat': double.parse(order.totals.vat.toStringAsFixed(2)),
        'grand_total': double.parse(order.totals.grandTotal.toStringAsFixed(2)),
      };

      final res = await dio.post('orders/siparisduzenle', data: payload);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (res.data is Map && res.data['message'] is String)
                ? res.data['message'] as String
                : 'Sipariş kaydedildi',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// Sevkiyat Durumu — AYRI KART, dikey (alt alta) zaman çizgisi
  Widget _shipmentCard(String status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sevkiyat Durumu',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _shipmentTimeline(status),
          ],
        ),
      ),
    );
  }

  // ================== Küçük yardımcılar ==================

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.black54)),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final icon = _statusIcon(status);
    final bg = _statusBg(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(_statusLabel(status)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
      case 'bekliyor':
      case 'bekleyen':
        return 'Bekleyen';
      case 'hazırlanıyor':
        return 'Hazırlanıyor';
      case 'sevk edildi':
        return 'Sevk edildi';
      case 'yolda':
        return 'Yolda';
      case 'teslim edildi':
      case 'teslim edil':
        return 'Teslim edildi';
      case 'iptal':
        return 'İptal';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
      case 'bekliyor':
      case 'bekleyen':
        return Icons.hourglass_bottom_outlined;
      case 'hazırlanıyor':
        return Icons.inventory_2_outlined;
      case 'sevk edildi':
        return Icons.local_shipping_outlined;
      case 'yolda':
        return Icons.route_outlined;
      case 'teslim edildi':
      case 'teslim edil':
        return Icons.check_circle_outline;
      case 'iptal':
        return Icons.cancel_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'pending':
      case 'bekliyor':
      case 'bekleyen':
        return Colors.blueGrey.withOpacity(.15);
      case 'hazırlanıyor':
        return Colors.amber.withOpacity(.15);
      case 'sevk edildi':
        return Colors.blue.withOpacity(.15);
      case 'yolda':
        return Colors.indigo.withOpacity(.15);
      case 'teslim edildi':
      case 'teslim edil':
        return Colors.green.withOpacity(.15);
      case 'iptal':
        return Colors.red.withOpacity(.15);
      default:
        return Colors.grey.withOpacity(.15);
    }
  }

  // --- Sevkiyat zaman çizgisi: DİKEY (alt alta)
  Widget _shipmentTimeline(String status) {
    final s = status.toLowerCase().trim();

    int current;
    if (s.contains('iptal') || s.contains('cancel')) {
      current = -1;
    } else if (s.contains('teslim') || s.contains('deliver')) {
      current = 3;
    } else if (s.contains('yol') ||
        s.contains('transit') ||
        s.contains('way')) {
      current = 2;
    } else if (s.contains('sevk') || s.contains('ship')) {
      current = 1;
    } else {
      current = 0; // pending/confirmed/hazırlanıyor
    }

    const stages = [
      ('Hazırlanıyor', Icons.inventory_2_outlined),
      ('Sevk Edildi', Icons.local_shipping_outlined),
      ('Yolda', Icons.route_outlined),
      ('Teslim Edildi', Icons.verified_outlined),
    ];

    if (current == -1) {
      return Row(
        children: const [
          CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFFFFE5E5),
            child: Icon(Icons.cancel_outlined, color: Colors.red),
          ),
          SizedBox(width: 8),
          Text('Sipariş İptal Edildi',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < stages.length; i++)
          _vStage(
            label: stages[i].$1,
            icon: stages[i].$2,
            state: i < current
                ? _StageState.done
                : (i == current ? _StageState.current : _StageState.todo),
            showConnectorBelow: i != stages.length - 1,
          ),
      ],
    );
  }

  // Tek satırlık dikey adım
  Widget _vStage({
    required String label,
    required IconData icon,
    required _StageState state,
    required bool showConnectorBelow,
  }) {
    final Color color = switch (state) {
      _StageState.done => Colors.green,
      _StageState.current => Colors.amber,
      _StageState.todo => Colors.black26,
    };
    final Color lineColor =
        state == _StageState.done ? Colors.green : Colors.black12;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withOpacity(.15),
                child: Icon(icon, color: color, size: 18),
              ),
              if (showConnectorBelow)
                Container(width: 2, height: 24, color: lineColor),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: state == _StageState.todo
                      ? FontWeight.w500
                      : FontWeight.w700,
                  color: state == _StageState.todo
                      ? Colors.black54
                      : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================== ViewModel & toplam hesap ==================

class _OrderItemVM {
  final int? productId;
  final int? variantId; // product_variants.id
  final String productTitle;
  final double? qtyCases; // koli / adet
  final double? approxKgPerCase; // kg/koli (opsiyonel)
  final double? pricePerKg; // birim fiyat
  final double lineTotal;

  _OrderItemVM({
    this.productId,
    this.variantId,
    required this.productTitle,
    required this.qtyCases,
    required this.approxKgPerCase,
    required this.pricePerKg,
    required this.lineTotal,
  });
}

class _Totals {
  final double subtotal;
  final double vat;
  final double grandTotal;
  const _Totals(this.subtotal, this.vat, this.grandTotal);
}

class _OrderVM {
  final String orderNumber;
  final String status;
  final DateTime createdAt;
  final String? shippingAddress;
  final String createdByName;
  final List<_OrderItemVM> items;
  final _Totals totals;

  _OrderVM({
    required this.orderNumber,
    required this.status,
    required this.createdAt,
    required this.shippingAddress,
    required this.createdByName,
    required this.items,
    required this.totals,
  });

  _OrderVM copyWith({
    String? orderNumber,
    String? status,
    DateTime? createdAt,
    String? shippingAddress,
    String? createdByName,
    List<_OrderItemVM>? items,
    _Totals? totals,
  }) {
    return _OrderVM(
      orderNumber: orderNumber ?? this.orderNumber,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      createdByName: createdByName ?? this.createdByName,
      items: items ?? this.items,
      totals: totals ?? this.totals,
    );
  }
}
