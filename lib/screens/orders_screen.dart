// lib/screens/orders_screen.dart
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/api_client.dart';
import '../utils/format.dart';
import 'haldeki_ui.dart';
import '../models/profile_ui.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const Color _haldekiGreen = Color(0xFF74C98D);

  // Data
  List<_Order> _all = [];
  List<_Order> _visible = [];

  // Search & sort
  final _search = TextEditingController();
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // Date filters
  DateTime? _fromDate;
  DateTime? _toDate;

  // UI state
  bool _loading = true;
  String? _error;

  // Bulk select
  final Set<String> _selected = <String>{}; // orderNumber set
  String? _bulkStatus; // TR
  bool _bulkWorking = false;

  // Supplier status options (TR, lowercase)
  static const List<String> _supplierStatusOptions = <String>[
    'bekliyor',
    'hazırlanıyor',
    'sevk edildi',
    'teslim edildi',
    'iptal',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // EN/TR mixed -> TR label key (for UI)
  String _toUiStatus(String input) {
    final t = input.toLowerCase().trim();

    // TR hints
    if (t.contains('bekli')) return 'bekliyor';
    if (t.contains('hazir')) return 'hazırlanıyor';
    if (t.contains('sevk') || t.contains('yol') || t.contains('transit')) {
      return 'sevk edildi';
    }
    if (t.contains('teslim')) return 'teslim edildi';
    if (t.contains('iptal')) return 'iptal';

    // EN -> TR
    switch (t) {
      case 'wait':
      case 'waiting':
      case 'pending':
        return 'bekliyor';
      case 'prepare':
      case 'preparing':
        return 'hazırlanıyor';
      case 'away':
      case 'in_transit':
      case 'on_the_way':
      case 'transit':
      case 'shipped':
        return 'sevk edildi';
      case 'delivered':
      case 'complete':
      case 'completed':
        return 'teslim edildi';
      case 'cancel':
      case 'canceled':
      case 'cancelled':
        return 'iptal';
      default:
        return input.trim().isEmpty ? 'bekliyor' : input.trim();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final email = api.session?.email.trim();
      if (email == null || email.isEmpty) {
        throw StateError('Oturum bulunamadı (email yok).');
      }

      final res = await api.dio.post(
        AppConfig.suppliersOrdersPath,
        data: {'email': email},
        queryParameters: {'page': 1},
      );

      final list = _parseOrdersPayload(res.data);

      setState(() {
        _all = list;
        _visible = List.of(_all);
        _selected
            .removeWhere((ord) => !_visible.any((o) => o.orderNumber == ord));
        _applySort();
      });
    } catch (e) {
      setState(() => _error = 'Siparişler yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // JSON -> _Order[]
  List<_Order> _parseOrdersPayload(dynamic payload) {
    List items;
    if (payload is List) {
      items = payload;
    } else if (payload is Map) {
      if (payload['data'] is List) {
        items = payload['data'];
      } else if (payload['results'] is List) {
        items = payload['results'];
      } else {
        items = const [];
      }
    } else {
      items = const [];
    }

    String pickStr(Map m, List<String> keys, {String fallback = ''}) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        final s = v.toString();
        if (s.isNotEmpty) return s;
      }
      return fallback;
    }

    double pickNum(Map m, List<String> keys) {
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

    DateTime pickDate(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String) {
          final d = DateTime.tryParse(v);
          if (d != null) return d;
        }
        if (v is int) {
          final s = v.toString();
          if (s.length >= 13) return DateTime.fromMillisecondsSinceEpoch(v);
          if (s.length >= 10)
            return DateTime.fromMillisecondsSinceEpoch(v * 1000);
        }
      }
      return DateTime.now();
    }

    return items.whereType<Map>().map((raw0) {
      final raw = Map<String, dynamic>.from(raw0);

      final id = pickStr(raw, ['id', '_id', 'order_id'], fallback: '');
      final number = pickStr(
        raw,
        ['orderNumber', 'order_number', 'number', 'code', 'no'],
        fallback: id.isEmpty ? '—' : '#$id',
      );

      // Only supplier_status
      final rawStatusOnly = pickStr(raw, ['supplier_status'], fallback: '');

      final createdAt = pickDate(
        raw,
        ['createdAt', 'created_at', 'date', 'ordered_at', 'created_at_iso'],
      );
      final total =
          pickNum(raw, ['total', 'total_amount', 'amount', 'grand_total']);
      final address = pickStr(raw, [
        'shippingAddress',
        'shipping_address',
        'address',
        'delivery_address'
      ]);

      // Buyer
      Map<String, dynamic>? buyer =
          raw['buyer'] is Map ? Map<String, dynamic>.from(raw['buyer']) : null;
      final buyerName = buyer != null
          ? pickStr(buyer, ['name'])
          : pickStr(raw, ['buyer_name', 'buyerName']);
      final buyerCity = buyer != null
          ? pickStr(buyer, ['city'])
          : pickStr(raw, ['buyer_city', 'buyerCity']);
      final buyerDistrict = buyer != null
          ? pickStr(buyer, ['district'])
          : pickStr(raw, ['buyer_district', 'buyerDistrict']);

      // Dealer (supplier)
      Map<String, dynamic>? dealer = raw['dealer'] is Map
          ? Map<String, dynamic>.from(raw['dealer'])
          : null;
      final dealerId = dealer != null
          ? pickStr(dealer, ['id'])
          : pickStr(raw, ['dealer_id']);
      final dealerName = dealer != null
          ? pickStr(dealer, ['name'])
          : pickStr(raw, ['dealer_name', 'dealerName']);
      final dealerCity = dealer != null
          ? pickStr(dealer, ['city'])
          : pickStr(raw, ['dealer_city', 'dealerCity']);
      final dealerDist = dealer != null
          ? pickStr(dealer, ['district'])
          : pickStr(raw, ['dealer_district', 'dealerDistrict']);
      final dealerMail = dealer != null
          ? pickStr(dealer, ['email'])
          : pickStr(raw, ['dealer_email']);
      final dealerPhone = dealer != null
          ? pickStr(dealer, ['phone'])
          : pickStr(raw, ['dealer_phone']);

      // createdBy fallback
      final createdBy = pickStr(
        raw,
        [
          'createdByName',
          'created_by_name',
          'user_name',
          'customer_name',
          'createdBy'
        ],
        fallback: buyerName,
      );

      return _Order(
        id: id,
        orderNumber: number,
        supplierStatus: _toUiStatus(rawStatusOnly),
        createdAt: createdAt,
        totalAmount: total,
        shippingAddress: address.isEmpty ? null : address,
        createdByName: createdBy.isEmpty ? '—' : createdBy,
        buyerName: buyerName.isEmpty ? null : buyerName,
        buyerCity: buyerCity.isEmpty ? null : buyerCity,
        buyerDistrict: buyerDistrict.isEmpty ? null : buyerDistrict,
        dealerId: dealerId.isEmpty ? null : dealerId,
        dealerName: dealerName.isEmpty ? null : dealerName,
        dealerCity: dealerCity.isEmpty ? null : dealerCity,
        dealerDistrict: dealerDist.isEmpty ? null : dealerDist,
        dealerEmail: dealerMail.isEmpty ? null : dealerMail,
        dealerPhone: dealerPhone.isEmpty ? null : dealerPhone,
      );
    }).toList();
  }

  // ================== FILTER & SORT ==================

  void _applyFilters() {
    final q = _search.text.trim().toLowerCase();

    setState(() {
      _visible = _all.where((o) {
        final okQuery = q.isEmpty ||
            o.orderNumber.toLowerCase().contains(q) ||
            (o.shippingAddress ?? '').toLowerCase().contains(q) ||
            o.createdByName.toLowerCase().contains(q) ||
            (o.buyerName ?? '').toLowerCase().contains(q) ||
            (o.buyerCity ?? '').toLowerCase().contains(q) ||
            (o.buyerDistrict ?? '').toLowerCase().contains(q) ||
            (o.dealerName ?? '').toLowerCase().contains(q) ||
            (o.dealerCity ?? '').toLowerCase().contains(q) ||
            (o.dealerDistrict ?? '').toLowerCase().contains(q);

        bool okDate = true;
        if (_fromDate != null) {
          final from =
              DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
          if (o.createdAt.isBefore(from)) okDate = false;
        }
        if (_toDate != null) {
          final to = DateTime(
              _toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59, 999);
          if (o.createdAt.isAfter(to)) okDate = false;
        }

        return okQuery && okDate;
      }).toList();

      // Seçili ama artık görünmeyenleri temizle
      _selected
          .removeWhere((ord) => !_visible.any((o) => o.orderNumber == ord));

      _applySort();
    });
  }

  void _applySort() {
    if (_sortColumnIndex == null) return;
    final col = _sortColumnIndex!;
    _visible.sort((a, b) {
      int cmp;
      switch (col) {
        case 0:
          cmp = a.orderNumber.compareTo(b.orderNumber);
          break;
        case 1:
          cmp = (a.dealerName ?? '').compareTo(b.dealerName ?? '');
          break;
        case 2:
          cmp = (a.dealerCity ?? '').compareTo(b.dealerCity ?? '');
          break;
        case 3:
          cmp = (a.dealerDistrict ?? '').compareTo(b.dealerDistrict ?? '');
          break;
        case 4:
          cmp = a.supplierStatus.compareTo(b.supplierStatus);
          break;
        case 5:
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        case 6:
          cmp = a.totalAmount.compareTo(b.totalAmount);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      _applySort();
    });
  }

  // ================== BULK SELECT ==================

  bool get _allVisibleSelected =>
      _visible.isNotEmpty && _selected.length == _visible.length;
  bool get _someVisibleSelected => _selected.isNotEmpty && !_allVisibleSelected;

  void _toggleSelectAllVisible(bool value) {
    setState(() {
      _selected.clear();
      if (value) {
        for (final o in _visible) {
          _selected.add(o.orderNumber);
        }
      }
    });
  }

  void _toggleSelectOne(_Order o, bool value) {
    setState(() {
      if (value) {
        _selected.add(o.orderNumber);
      } else {
        _selected.remove(o.orderNumber);
      }
    });
  }

  Future<void> _applyBulkStatus() async {
    final status = _bulkStatus;
    if (status == null || status.trim().isEmpty) return;
    if (_selected.isEmpty) return;

    final toUpdate =
        _visible.where((o) => _selected.contains(o.orderNumber)).toList();
    if (toUpdate.isEmpty) return;

    setState(() => _bulkWorking = true);

    try {
      // Basit ve garantici: tek tek update (backend'de batch endpoint yoksa bile çalışır)
      for (final o in toUpdate) {
        await _sendSupplierStatusUpdate(o.orderNumber, status);
        if (!mounted) return;

        // local state update
        final ix = _all.indexWhere((e) => e.orderNumber == o.orderNumber);
        if (ix >= 0) _all[ix] = _all[ix].copyWith(supplierStatus: status);

        final vx = _visible.indexWhere((e) => e.orderNumber == o.orderNumber);
        if (vx >= 0)
          _visible[vx] = _visible[vx].copyWith(supplierStatus: status);
      }

      if (!mounted) return;
      setState(() {
        _applySort();
        // istersen seçimi koru; ben koruyorum
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Seçilen ${toUpdate.length} sipariş güncellendi: ${_statusLabel(status)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toplu güncelleme başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _bulkWorking = false);
    }
  }

  // ---------- STATUS UPDATE (single) ----------

  Widget _statusWithEdit(_Order o) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusChipMaster(o.supplierStatus),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Durumu güncelle',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.edit_outlined, size: 16),
          onPressed: () => _pickAndUpdateStatus(o),
        ),
      ],
    );
  }

  Future<void> _pickAndUpdateStatus(_Order o) async {
    String selected = _toUiStatus(o.supplierStatus);

    final newStatusTr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Durumu Güncelle'),
        content: StatefulBuilder(
          builder: (ctx, setS) {
            final v = _supplierStatusOptions.contains(selected)
                ? selected
                : _supplierStatusOptions.first;
            return DropdownButton<String>(
              value: v,
              isExpanded: true,
              items: _supplierStatusOptions
                  .map((s) => DropdownMenuItem<String>(
                        value: s,
                        child: Text(_statusLabel(s)),
                      ))
                  .toList(),
              onChanged: (x) => setS(() => selected = x ?? selected),
            );
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Kaydet')),
        ],
      ),
    );

    if (newStatusTr == null || newStatusTr == _toUiStatus(o.supplierStatus))
      return;

    try {
      await _sendSupplierStatusUpdate(o.orderNumber, newStatusTr);
      if (!mounted) return;

      setState(() {
        final ix = _all.indexWhere((e) => e.orderNumber == o.orderNumber);
        if (ix >= 0) _all[ix] = _all[ix].copyWith(supplierStatus: newStatusTr);
        final vx = _visible.indexWhere((e) => e.orderNumber == o.orderNumber);
        if (vx >= 0)
          _visible[vx] = _visible[vx].copyWith(supplierStatus: newStatusTr);
        _applySort();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Durum güncellendi: ${_statusLabel(newStatusTr)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güncelleme başarısız: $e')),
      );
    }
  }

  Future<void> _sendSupplierStatusUpdate(
      String orderNumber, String statusTr) async {
    final api = context.read<ApiClient>();
    final email = api.session?.email.trim();
    if (email == null || email.isEmpty)
      throw StateError('Oturum bulunamadı (email yok).');

    final String path = AppConfig.supplierUpdateStatusPath;

    await api.dio.post(
      path,
      data: {
        'email': email,
        'order_number': orderNumber,
        'supplier_status': statusTr
      },
    );
  }

  // ---------- Date helpers ----------

  String _formatShortDate(DateTime? d) {
    if (d == null) return 'Seç';
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}.'
        '${d.year}';
  }

  Future<void> _pickFromDate() async {
    final now = DateTime.now();
    final initial = _fromDate ?? now;
    final picked = await _pickDateCompact(
      title: 'Başlangıç Tarihi',
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() => _fromDate = picked);
    _applyFilters();
  }

  Future<void> _pickToDate() async {
    final now = DateTime.now();
    final initial = _toDate ?? now;
    final picked = await _pickDateCompact(
      title: 'Bitiş Tarihi',
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() => _toDate = picked);
    _applyFilters();
  }

  Future<DateTime?> _pickDateCompact({
    required String title,
    required DateTime initialDate,
  }) async {
    final now = DateTime.now();
    DateTime selected = initialDate;
    return showDialog<DateTime>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: ProfileUiTokens.text,
            ),
          ),
          content: SizedBox(
            width: 360,
            child: Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(
                      primary: _haldekiGreen,
                    ),
              ),
              child: CalendarDatePicker(
                initialDate: initialDate,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 2),
                currentDate: now,
                onDateChanged: (d) => selected = d,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Uygula'),
            ),
          ],
        );
      },
    );
  }

  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _applyFilters();
  }

  // ================== BUILD (Genel Özet üstte, Sipariş Listesi altta) ==================

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final themed = HaldekiUI.withRectButtons(context, cs).copyWith(
      scaffoldBackgroundColor: ProfileUiTokens.bg,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ProfileUiTokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ProfileUiTokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _haldekiGreen, width: 1.6),
        ),
      ),
    );

    final totalCount = _visible.length;
    final delivered =
        _visible.where((o) => _isDelivered(o.supplierStatus)).length;
    final preparing = _visible
        .where((o) => _toUiStatus(o.supplierStatus) == 'hazırlanıyor')
        .length;
    final waiting = _visible
        .where((o) => _toUiStatus(o.supplierStatus) == 'bekliyor')
        .length;
    final shipped = _visible
        .where((o) => _toUiStatus(o.supplierStatus) == 'sevk edildi')
        .length;
    final canceled =
        _visible.where((o) => _toUiStatus(o.supplierStatus) == 'iptal').length;

    return Theme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: ProfileUiTokens.bg,
          title: const Text(
            'Tedarikçi • Siparişler',
            style: TextStyle(
                fontWeight: FontWeight.w900, color: ProfileUiTokens.text),
          ),
          actions: [
            IconButton(
              tooltip: "Yenile",
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Geri',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _loading
                ? const LinearProgressIndicator(minHeight: 3)
                : const SizedBox(height: 3),
          ),
        ),
        body: Stack(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null && _all.isEmpty)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ProfileSectionCard(
                    title: 'Bağlantı Sorunu',
                    subtitle: 'Siparişler getirilemedi',
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        const Icon(Icons.cloud_off_outlined, size: 48),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tekrar dene'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              // ✅ TAŞMA DÜZELTME: tüm içerik dikey scroll içinde
              Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildLeftSummaryCard(
                          totalCount: totalCount,
                          waiting: waiting,
                          delivered: delivered,
                          preparing: preparing,
                          shipped: shipped,
                          canceled: canceled,
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (ctx, c) {
                            final wide = c.maxWidth >= 1100;
                            return _buildRightOrdersPanel(wide: wide);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // üst hata bandı
            if (_error != null && _all.isNotEmpty)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ProfileAlertBar(
                    tone: ProfileAlertTone.danger,
                    title: "Uyarı",
                    message: _error!,
                    actionLabel: "Yenile",
                    onAction: _load,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GENEL ÖZET (üst panel)
  // ---------------------------------------------------------------------------

  Widget _buildLeftSummaryCard({
    required int totalCount,
    required int waiting,
    required int delivered,
    required int preparing,
    required int shipped,
    required int canceled,
  }) {
    final hasDates = _fromDate != null || _toDate != null;

    return ProfileSectionCard(
      title: "Genel Özet",
      subtitle: "Hızlı görünüm • filtreler",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _chip(
                  icon: Icons.receipt_long_outlined,
                  label: "Toplam: $totalCount",
                  color: _haldekiGreen),
              _chip(
                  icon: Icons.hourglass_bottom_outlined,
                  label: "Bekliyor: $waiting",
                  color: ProfileUiTokens.muted),
              _chip(
                  icon: Icons.inventory_2_outlined,
                  label: "Hazırlanan: $preparing",
                  color: ProfileUiTokens.amber),
              _chip(
                  icon: Icons.local_shipping_outlined,
                  label: "Sevk: $shipped",
                  color: _haldekiGreen),
              _chip(
                  icon: Icons.check_circle_outline,
                  label: "Teslim: $delivered",
                  color: ProfileUiTokens.green),
              _chip(
                  icon: Icons.cancel_outlined,
                  label: "İptal: $canceled",
                  color: ProfileUiTokens.red),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            "Arama ve Tarih",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: ProfileUiTokens.text.withOpacity(.9),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Sipariş no, bayi',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: ProfileUiTokens.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: ProfileUiTokens.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: _haldekiGreen, width: 1.6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _haldekiGreen.withOpacity(.14),
                      foregroundColor: _haldekiGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.date_range),
                    onPressed: _pickFromDate,
                    label: Text('Başlangıç: ${_formatShortDate(_fromDate)}'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _haldekiGreen.withOpacity(.14),
                      foregroundColor: _haldekiGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.date_range),
                    onPressed: _pickToDate,
                    label: Text('Bitiş: ${_formatShortDate(_toDate)}'),
                  ),
                ),
                if (hasDates) ...[
                  const SizedBox(width: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.clear),
                    onPressed: _clearDateFilters,
                    label: const Text('Temizle'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          /*   ProfileInfoLine(
            icon: Icons.info_outline,
            label: "İpucu",
            value:
                "Tekil güncelleme için listede kalem ikonunu kullan. Toplu işlem için siparişleri seç.",
          ),
          */
        ],
      ),
    );
  }

  Widget _chip(
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SİPARİŞ LİSTESİ (alt panel)
  // ---------------------------------------------------------------------------

  Widget _buildRightOrdersPanel({required bool wide}) {
    return ProfileSectionCard(
      title: "Sipariş Listesi",
      subtitle: wide ? "Geniş görünüm • tablo" : "Mobil görünüm • kart",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_visible.isEmpty) const _EmptyStateMaster(),
          if (_visible.isNotEmpty) ...[
            _bulkActionBar(wide: wide),
            const SizedBox(height: 10),
            if (wide) _ordersWideTableMaster() else _ordersCardsListMaster(),
          ],
        ],
      ),
    );
  }

  Widget _bulkActionBar({required bool wide}) {
    final enabled = _selected.isNotEmpty && !_bulkWorking;
    final dense = !wide;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProfileUiTokens.border),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.checklist_rounded,
                  size: 18, color: ProfileUiTokens.muted),
              const SizedBox(width: 8),
              Text(
                'Seçili: ${_selected.length}',
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: ProfileUiTokens.text),
              ),
            ],
          ),
          SizedBox(
            width: dense ? 260 : 320,
            child: DropdownButtonFormField<String>(
              value: _bulkStatus,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.swap_horiz_rounded),
                hintText: 'Toplu durum seç',
              ),
              items: _supplierStatusOptions
                  .map((s) => DropdownMenuItem<String>(
                        value: s,
                        child: Text(_statusLabel(s)),
                      ))
                  .toList(),
              onChanged:
                  _bulkWorking ? null : (v) => setState(() => _bulkStatus = v),
            ),
          ),
          FilledButton.icon(
            onPressed:
                (enabled && _bulkStatus != null) ? _applyBulkStatus : null,
            icon: _bulkWorking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all_rounded),
            label: Text(_bulkWorking ? 'Uygulanıyor...' : 'Seçilene uygula'),
          ),
          TextButton.icon(
            onPressed: _selected.isEmpty || _bulkWorking
                ? null
                : () => setState(() => _selected.clear()),
            icon: const Icon(Icons.clear_rounded),
            label: const Text('Seçimi temizle'),
          ),
        ],
      ),
    );
  }

  Widget _ordersCardsListMaster() {
    final cs = Theme.of(context).colorScheme;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final o = _visible[i];
        final selected = _selected.contains(o.orderNumber);

        final buyerLine = [
          if ((o.buyerName ?? '').isNotEmpty) o.buyerName!,
          if ((o.buyerCity ?? '').isNotEmpty &&
              (o.buyerDistrict ?? '').isNotEmpty)
            '${o.buyerCity}/${o.buyerDistrict}'
          else if ((o.buyerCity ?? '').isNotEmpty)
            o.buyerCity!
          else if ((o.buyerDistrict ?? '').isNotEmpty)
            o.buyerDistrict!,
        ].join(' • ');

        return InkWell(
          onTap: () =>
              context.go('/orders/${Uri.encodeComponent(o.orderNumber)}'),
          onLongPress: () => _toggleSelectOne(o, !selected),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: selected
                      ? _haldekiGreen.withOpacity(.45)
                      : ProfileUiTokens.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => _toggleSelectOne(o, v ?? false),
                ),
                _leadingBadge(_toUiStatus(o.supplierStatus)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              o.orderNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: ProfileUiTokens.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _statusChipMaster(o.supplierStatus),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (buyerLine.isNotEmpty)
                        Text(
                          buyerLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: ProfileUiTokens.muted),
                        ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule,
                                  size: 16, color: ProfileUiTokens.muted),
                              const SizedBox(width: 6),
                              Text(dt(o.createdAt),
                                  style: const TextStyle(
                                      color: ProfileUiTokens.muted)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.payments_outlined,
                                  size: 16, color: ProfileUiTokens.muted),
                              const SizedBox(width: 6),
                              Text(
                                tl(o.totalAmount),
                                style: const TextStyle(
                                  color: ProfileUiTokens.text,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if ((o.shippingAddress ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 16, color: ProfileUiTokens.muted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                o.shippingAddress!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: ProfileUiTokens.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _miniAction(
                            icon: Icons.open_in_new,
                            label: 'Detay',
                            onTap: () => context.go(
                                '/orders/${Uri.encodeComponent(o.orderNumber)}'),
                          ),
                          const SizedBox(width: 8),
                          _miniAction(
                            icon: Icons.edit_outlined,
                            label: 'Durum',
                            onTap: () => _pickAndUpdateStatus(o),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ordersWideTableMaster() {
    return LayoutBuilder(
      builder: (context, c) {
        final double tableWidth = math.max(c.maxWidth, 1280.0).toDouble();
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: tableWidth),
              child: DataTable(
                columnSpacing: 20,
                headingRowHeight: 48,
                dataRowMinHeight: 58,
                dataRowMaxHeight: 66,
                dividerThickness: 0.8,
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.w900, color: ProfileUiTokens.text),
                columns: [
                  DataColumn(
                    label: Checkbox(
                      value: _allVisibleSelected,
                      tristate: true,
                      onChanged: _bulkWorking
                          ? null
                          : (v) {
                              // tristate: null => some selected
                              final next = !(_allVisibleSelected);
                              _toggleSelectAllVisible(next);
                            },
                    ),
                  ),
                  DataColumn(
                      label: const Text('Sipariş'),
                      onSort: (_, asc) => _onSort(0, asc)),
                  DataColumn(
                      label: const Text('Bayi'),
                      onSort: (_, asc) => _onSort(1, asc)),
                  DataColumn(
                      label: const Text('Şehir'),
                      onSort: (_, asc) => _onSort(2, asc)),
                  DataColumn(
                      label: const Text('İlçe'),
                      onSort: (_, asc) => _onSort(3, asc)),
                  DataColumn(
                      label: const Text('Durum'),
                      onSort: (_, asc) => _onSort(4, asc)),
                  DataColumn(
                      label: const Text('Tarih'),
                      onSort: (_, asc) => _onSort(5, asc)),
                  DataColumn(
                      numeric: true,
                      label: const Text('Tutar'),
                      onSort: (_, asc) => _onSort(6, asc)),
                  const DataColumn(label: Text('Aksiyon')),
                ],
                rows: [
                  for (final o in _visible)
                    DataRow(
                      selected: _selected.contains(o.orderNumber),
                      onSelectChanged: _bulkWorking
                          ? null
                          : (v) => _toggleSelectOne(o, v ?? false),
                      cells: [
                        DataCell(
                          Checkbox(
                            value: _selected.contains(o.orderNumber),
                            onChanged: _bulkWorking
                                ? null
                                : (v) => _toggleSelectOne(o, v ?? false),
                          ),
                        ),
                        DataCell(
                          TextButton.icon(
                            onPressed: () => context.go(
                                '/orders/${Uri.encodeComponent(o.orderNumber)}'),
                            icon: const Icon(Icons.receipt_long_outlined,
                                size: 18),
                            label: Text(o.orderNumber,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                        DataCell(Text(o.dealerName ?? '—')),
                        DataCell(Text(o.dealerCity ?? '—')),
                        DataCell(Text(o.dealerDistrict ?? '—')),
                        DataCell(_statusWithEdit(o)),
                        DataCell(Text(dt(o.createdAt))),
                        DataCell(
                          Text(
                            tl(o.totalAmount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Detay',
                                onPressed: () => context.go(
                                    '/orders/${Uri.encodeComponent(o.orderNumber)}'),
                                icon: const Icon(Icons.open_in_new, size: 20),
                              ),
                              IconButton(
                                tooltip: 'Durumu güncelle',
                                onPressed: () => _pickAndUpdateStatus(o),
                                icon: const Icon(Icons.edit_outlined, size: 20),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  Widget _leadingBadge(String status) {
    IconData icon;
    Color bg;
    Color fg;

    switch (status) {
      case 'bekliyor':
        icon = Icons.hourglass_bottom_outlined;
        bg = ProfileUiTokens.border.withOpacity(.45);
        fg = ProfileUiTokens.muted;
        break;
      case 'hazırlanıyor':
        icon = Icons.inventory_2_outlined;
        bg = ProfileUiTokens.amber.withOpacity(.12);
        fg = ProfileUiTokens.amber;
        break;
      case 'sevk edildi':
        icon = Icons.local_shipping_outlined;
        bg = _haldekiGreen.withOpacity(.12);
        fg = _haldekiGreen;
        break;
      case 'teslim edildi':
        icon = Icons.check_circle_outline;
        bg = ProfileUiTokens.green.withOpacity(.12);
        fg = ProfileUiTokens.green;
        break;
      case 'iptal':
        icon = Icons.cancel_outlined;
        bg = ProfileUiTokens.red.withOpacity(.12);
        fg = ProfileUiTokens.red;
        break;
      default:
        icon = Icons.info_outline;
        bg = ProfileUiTokens.border.withOpacity(.35);
        fg = ProfileUiTokens.muted;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withOpacity(.18)),
      ),
      child: Icon(icon, color: fg, size: 20),
    );
  }

  Widget _miniAction(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ProfileUiTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: ProfileUiTokens.muted),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: ProfileUiTokens.muted, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _statusChipMaster(String statusRaw) {
    final s = _toUiStatus(statusRaw);
    final icon = _statusIcon(s);
    final fg = _statusFg(s);
    final bg = fg.withOpacity(.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(_statusLabel(s),
              style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'bekliyor':
        return 'Bekliyor';
      case 'hazırlanıyor':
        return 'Hazırlanıyor';
      case 'sevk edildi':
        return 'Sevk Edildi';
      case 'teslim edildi':
        return 'Teslim Edildi';
      case 'iptal':
        return 'İptal';
      default:
        return s;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'bekliyor':
        return Icons.hourglass_bottom_outlined;
      case 'hazırlanıyor':
        return Icons.inventory_2_outlined;
      case 'sevk edildi':
        return Icons.local_shipping_outlined;
      case 'teslim edildi':
        return Icons.check_circle_outline;
      case 'iptal':
        return Icons.cancel_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Color _statusFg(String s) {
    switch (s) {
      case 'bekliyor':
        return ProfileUiTokens.muted;
      case 'hazırlanıyor':
        return ProfileUiTokens.amber;
      case 'sevk edildi':
        return _haldekiGreen;
      case 'teslim edildi':
        return ProfileUiTokens.green;
      case 'iptal':
        return ProfileUiTokens.red;
      default:
        return ProfileUiTokens.muted;
    }
  }

  bool _isDelivered(String s) => _toUiStatus(s) == 'teslim edildi';
}

class _EmptyStateMaster extends StatelessWidget {
  const _EmptyStateMaster();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(18.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: ProfileUiTokens.muted),
            SizedBox(height: 10),
            Text('Eşleşen sipariş bulunamadı',
                style: TextStyle(color: ProfileUiTokens.muted)),
          ],
        ),
      ),
    );
  }
}

// --------------------- View-model ---------------------
class _Order {
  final String id;
  final String orderNumber;
  final String supplierStatus; // TR
  final DateTime createdAt;
  final double totalAmount;
  final String? shippingAddress;
  final String createdByName;

  final String? buyerName;
  final String? buyerCity;
  final String? buyerDistrict;

  final String? dealerId;
  final String? dealerName;
  final String? dealerCity;
  final String? dealerDistrict;
  final String? dealerEmail;
  final String? dealerPhone;

  _Order({
    required this.id,
    required this.orderNumber,
    required this.supplierStatus,
    required this.createdAt,
    required this.totalAmount,
    required this.shippingAddress,
    required this.createdByName,
    this.buyerName,
    this.buyerCity,
    this.buyerDistrict,
    this.dealerId,
    this.dealerName,
    this.dealerCity,
    this.dealerDistrict,
    this.dealerEmail,
    this.dealerPhone,
  });

  _Order copyWith({
    String? id,
    String? orderNumber,
    String? supplierStatus,
    DateTime? createdAt,
    double? totalAmount,
    String? shippingAddress,
    String? createdByName,
    String? buyerName,
    String? buyerCity,
    String? buyerDistrict,
    String? dealerId,
    String? dealerName,
    String? dealerCity,
    String? dealerDistrict,
    String? dealerEmail,
    String? dealerPhone,
  }) {
    return _Order(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      supplierStatus: supplierStatus ?? this.supplierStatus,
      createdAt: createdAt ?? this.createdAt,
      totalAmount: totalAmount ?? this.totalAmount,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      createdByName: createdByName ?? this.createdByName,
      buyerName: buyerName ?? this.buyerName,
      buyerCity: buyerCity ?? this.buyerCity,
      buyerDistrict: buyerDistrict ?? this.buyerDistrict,
      dealerId: dealerId ?? this.dealerId,
      dealerName: dealerName ?? this.dealerName,
      dealerCity: dealerCity ?? this.dealerCity,
      dealerDistrict: dealerDistrict ?? this.dealerDistrict,
      dealerEmail: dealerEmail ?? this.dealerEmail,
      dealerPhone: dealerPhone ?? this.dealerPhone,
    );
  }
}
