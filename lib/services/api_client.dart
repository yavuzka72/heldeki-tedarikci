// lib/services/api_client.dart
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:haldeki_tedarikci_web/models/dealer_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'session.dart';

// Modeller
import 'package:haldeki_tedarikci_web/models/paginated.dart';
import 'package:haldeki_tedarikci_web/models/supplier.dart';
import 'package:haldeki_tedarikci_web/models/category.dart';

class ApiClient {
  // ---------- Singleton ----------
  ApiClient._internal();
  static final ApiClient _i = ApiClient._internal();
  factory ApiClient() => _i;

  // ---------- State ----------
  late final Dio _dio;
  late final SharedPreferences _prefs;
  DealerProfile? currentProfile;

  int? currentUserId;
  int? currentSupplierId; // 👈 EKLENDİ
  String? _token;
  String? currentEmail; // << EKLE

  Dio get dio => _dio;
  String? get token => _token;

  UserSession? _session;
  UserSession? get session => _session;

  // ---------- Init ----------
  Future<void> init22() async {
    _prefs = await SharedPreferences.getInstance();

    _dio = Dio(
      BaseOptions(
        baseUrl: '${AppConfig.apiBase}/', // Örn: http://192.168.64.2/api/v1/
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          'Accept': 'application/json',
          'Accept-Language': 'tr-TR',
        },
      ),
    );

    // Persist edilen token & session’ı yükle
    final t = _prefs.getString('token');
    if (t != null && t.isNotEmpty) {
      _token = t;
      _dio.options.headers['Authorization'] = 'Bearer $t';
    }
    final s = _prefs.getString('user_session');
    if (s != null && s.isNotEmpty) {
      _session = UserSession.fromEncoded(s);
    }

    // Basit log + 401’de oturumu düşür
    _dio.interceptors.add(LogInterceptor(
      requestHeader: false,
      requestBody: true,
      responseHeader: false,
      responseBody: false,
    ));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await setToken(null);
          }
          handler.next(e);
        },
      ),
    );
  }

  Future<void> setCurrentSupplierId(int? id) async {
    currentSupplierId = id;
    if (id == null) {
      await _prefs.remove('current_supplier_id');
    } else {
      await _prefs.setInt('current_supplier_id', id);
    }
  }

  int? _userId;
  int? _dealerId;

  int? get userId => _userId ?? _prefs.getInt('user_id');
  int? get dealerId => _dealerId ?? _prefs.getInt('dealer_id');

  Future<void> inittedarik() async {
    _prefs = await SharedPreferences.getInstance();

    _dio = Dio(
      BaseOptions(
        baseUrl: '${AppConfig.apiBase}/',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          'Accept': 'application/json',
          'Accept-Language': 'tr-TR',
        },
      ),
    );

    // Persist edilen token & session’ı yükle
    final t = _prefs.getString('token');
    if (t != null && t.isNotEmpty) {
      _token = t;
      _dio.options.headers['Authorization'] = 'Bearer $t';
    }
    final s = _prefs.getString('user_session');
    if (s != null && s.isNotEmpty) {
      _session = UserSession.fromEncoded(s);
    }

    // 👇 Tedarikçi ID'yi de persist et
    currentSupplierId = _prefs.getInt('current_supplier_id');

    // Basit log + 401’de oturumu düşür

    // Basit log + 401’de oturumu düşür
    _dio.interceptors.add(LogInterceptor(
      requestHeader: false,
      requestBody: true,
      responseHeader: false,
      responseBody: false,
    ));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await setToken(null);
          }
          handler.next(e);
        },
      ),
    );
  }

  Future<void> setUserId(int? id) async {
    _userId = id;
    if (id == null) {
      await _prefs.remove('user_id');
    } else {
      await _prefs.setInt('user_id', id);
    }
  }

  Future<void> setDealerId(int? id) async {
    _dealerId = id;
    if (id == null) {
      await _prefs.remove('dealer_id');
    } else {
      await _prefs.setInt('dealer_id', id);
    }
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    _dio = Dio(
      BaseOptions(
        baseUrl: '${AppConfig.apiBase}/',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          'Accept': 'application/json',
          'Accept-Language': 'tr-TR',
        },
      ),
    );

    // ID'ler
    _userId = _prefs.getInt('user_id');
    _dealerId = _prefs.getInt('dealer_id');
    currentUserId = _userId;
    currentSupplierId = _prefs.getInt('current_supplier_id');

    // ⬇️ Email + Session geri yükle
    // 1) Session string'den yükle (eğer kaydettiysen)
    final encodedSession = _prefs.getString('user_session');
    if (encodedSession != null && encodedSession.isNotEmpty) {
      try {
        _session = UserSession.fromEncoded(encodedSession);

        currentUserId = _session!.userId;
        await setUserId(_session!.userId);

        if (_session!.email.isNotEmpty) {
          currentEmail = _session!.email;
          await _prefs.setString('current_email', _session!.email);
        }
      } catch (_) {
        // bozuk session string'i varsa sessizce geç
      }
    }

    // 2) Eğer session'dan email gelmediyse, direkt prefs'ten dene
    currentEmail ??= _prefs.getString('current_email');

    // Token
    final token = _prefs.getString('token');
    if (token?.isNotEmpty == true) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }

    // Log + 401 interceptor
    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: false,
      requestHeader: false,
    ));

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await setToken(null);
          }
          handler.next(e);
        },
      ),
    );
  }

  // ---------- Auth / Session ----------
  Future<bool> isLoggedIn() async => _prefs.getString('token') != null;

  Future<Response> login(String email, String password) =>
      _dio.post('login', data: {'email': email, 'password': password});

  Future<Response> me() => _dio.get('auth/me');

  Future<void> setToken(String? token) async {
    _token = token;
    if (token == null || token.isEmpty) {
      await _prefs.remove('token');
      _dio.options.headers.remove('Authorization');
    } else {
      await _prefs.setString('token', token);
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<void> setSession(UserSession session) async {
    _session = session;
    await _prefs.setString('user_session', session.toEncoded());

    currentUserId = session.userId;
    _userId = session.userId;
    await setUserId(session.userId);

    _dealerId = session.dealerId;
    await setDealerId(session.dealerId);

    currentSupplierId = session.vendorId;
    await setCurrentSupplierId(session.vendorId);

    currentEmail = session.email;
    if (session.email.isNotEmpty) {
      await _prefs.setString('current_email', session.email);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post('logout');
    } catch (_) {}
    await setToken(null);
    await _prefs.remove('user_session');
    await _prefs.remove('current_email');
    _session = null;
    currentEmail = null;
  }

  // ---------- Generic JSON yardımcıları ----------
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _dio.get(path, queryParameters: query);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async {
    final res = await _dio.post(
      path,
      data: body,
      queryParameters: query,
      options: headers == null ? null : Options(headers: headers),
    );
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  // Dio ile sayfalı veri (Laravel pagination) çeken yardımcı
  Future<Paginated<T>> getPage<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _dio.get(path, queryParameters: query);
    final m = res.data;
    if (m is Map<String, dynamic>) {
      return Paginated<T>.fromLaravel(m, fromJson);
    }
    // Beklenmeyen yapı
    return Paginated<T>.fromLaravel({'data': m}, fromJson);
  }

  // toJson() olan request objelerini Map'e dönüştür
  dynamic _body(dynamic req) {
    try {
      // ignore: avoid_dynamic_calls
      final m = req?.toJson();
      if (m is Map<String, dynamic>) return m;
    } catch (_) {}
    if (req is Map<String, dynamic>) return req;
    return req;
  }

  // ---------- Orders ----------
  Future<List<dynamic>> previousOrdersByEmail(String email) async {
    final r = await _dio.post('previous-orders', data: {'email': email});
    final d = r.data;
    if (d is List) return d;
    if (d is Map) {
      final data = d['data'];
      if (data is List) return data;
      if (data is Map && data['data'] is List) return (data['data'] as List);
    }
    return const [];
  }

  Future<Map<String, dynamic>> previousOrdersJson() =>
      getJson('previous-orders');
  Future<Map<String, dynamic>> ordersJson() => getJson('orders');

  /// Tedarikçi siparişlerini getir (backend: /supplier-orders).
  /// email veya dealer_id gönderebilirsin (opsiyonel diğer filtreler).
  Future<Response> supplierOrders({
    String? email,
    int? dealerId,
    int? userId,
    String? city,
    String? district,
    String? status, // TR veya EN
    int page = 1,
  }) {
    return _dio.post(
      'supplier-orders',
      data: {
        if (email != null && email.isNotEmpty) 'email': email,
        if (dealerId != null) 'dealer_id': dealerId,
        if (userId != null) 'user_id': userId,
        if (city != null && city.isNotEmpty) 'city': city,
        if (district != null && district.isNotEmpty) 'district': district,
        if (status != null && status.isNotEmpty) 'status': status,
      },
      queryParameters: {'page': page},
    );
  }

  /// Tedarikçi statü güncelle (backend: /supplier-order-update-status).
  /// supplier_status TR ya da EN olabilir; sunucu EN’e çevirip yazar.
  Future<Response> supplierUpdateStatus({
    required String email,
    required String orderNumber,
    required String supplierStatus,
    bool? updateItems,
    String? note,
  }) {
    return _dio.post(
      'supplier-order-update-status',
      data: {
        'email': email,
        'order_number': orderNumber,
        'supplier_status': supplierStatus,
        if (updateItems != null) 'update_items': updateItems,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
  }

  // ---------- Catalog ----------
  Future<Response> categories() => _dio.get('categories');

  Future<Response> listings({String? q, int? categoryId, int page = 1}) =>
      _dio.get('listings', queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (categoryId != null) 'category_id': categoryId,
        'page': page,
      });

  Future<Response> listing(int id) => _dio.get('listings/$id');

  Future<bool> toggleFavorite(int id) async {
    final r = await _dio.post('listings/$id/favorite');
    final d = r.data;
    if (d is Map) return d['liked'] == true;
    return true;
  }

  // ---------- Products ----------
  Future<int> createProduct(dynamic req) async {
    final res = await _dio.post('api/products', data: _body(req));
    final m = res.data;
    if (m is Map && m['id'] != null) return (m['id'] as num).toInt();
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: 'createProduct: Beklenen yanıt alınamadı',
    );
  }

  Future<void> updateProduct(int id, dynamic req) async {
    final res = await _dio.put('api/products/$id', data: _body(req));
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'updateProduct başarısız (${res.statusCode})',
      );
    }
  }

  Future<void> deleteProduct(int id) async {
    final res = await _dio.delete('api/products/$id');
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'deleteProduct başarısız (${res.statusCode})',
      );
    }
  }

  // ---------- Variants & Prices ----------
  Future<Map<String, dynamic>> variants(
    int productId, {
    String? q,
    int page = 1,
  }) async {
    final res = await _dio.get(
      'api/products/$productId/variants',
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        'page': page,
      },
    );
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  Future<int> createVariant(int productId, dynamic req) async {
    final res =
        await _dio.post('api/products/$productId/variants', data: _body(req));
    final m = res.data;
    if (m is Map && m['id'] != null) return (m['id'] as num).toInt();
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: 'createVariant: Beklenen yanıt alınamadı',
    );
  }

  Future<void> setVariantPrice(int variantId, dynamic req) async {
    final res =
        await _dio.post('api/variants/$variantId/set-price', data: _body(req));
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'setVariantPrice başarısız (${res.statusCode})',
      );
    }
  }

  // ---------- Upload ----------
  Future<String> uploadImage(File file) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path),
    });
    final res = await _dio.post('api/upload', data: form);
    final m = res.data;
    if (m is Map && m['path'] is String) return m['path'] as String;
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: 'uploadImage: Beklenen yanıt alınamadı',
    );
  }

  // ---------- Suppliers (sayfalı) ----------
  Future<Paginated<Supplier>> suppliers({String? q, int page = 1}) =>
      getPage<Supplier>(
        'api/suppliers',
        (e) => Supplier.fromJson(e),
        query: {if (q?.isNotEmpty == true) 'q': q, 'page': page},
      );

  Future<int> createSupplier(SupplierCreate req) async {
    final res = await _dio.post('api/suppliers', data: req.toJson());
    final m = res.data;
    if (m is Map && m['id'] != null) return (m['id'] as num).toInt();
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: 'createSupplier: Beklenen yanıt alınamadı',
    );
  }

  Future<void> updateSupplier(int id, SupplierUpdate req) async {
    final res = await _dio.put('api/suppliers/$id', data: req.toJson());
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'updateSupplier başarısız (${res.statusCode})',
      );
    }
  }

  Future<void> deleteSupplier(int id) async {
    final res = await _dio.delete('api/suppliers/$id');
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'deleteSupplier başarısız (${res.statusCode})',
      );
    }
  }

  // ---------- Categories (sayfalı) ----------
  Future<Paginated<Category>> categories2({
    int? supplierId,
    String? q,
    int page = 1,
  }) =>
      getPage<Category>(
        'api/categories',
        (e) => Category.fromJson(e),
        query: {
          if (supplierId != null) 'supplier_id': supplierId,
          if (q?.isNotEmpty == true) 'q': q,
          'page': page,
        },
      );

  Future<int> createCategory(CategoryCreate req) async {
    final res = await _dio.post('api/categories', data: req.toJson());
    final m = res.data;
    if (m is Map && m['id'] != null) return (m['id'] as num).toInt();
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      message: 'createCategory: Beklenen yanıt alınamadı',
    );
  }

  Future<void> updateCategory(int id, CategoryUpdate req) async {
    final res = await _dio.put('api/categories/$id', data: req.toJson());
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'updateCategory başarısız (${res.statusCode})',
      );
    }
  }

  Future<void> deleteCategory(int id) async {
    final res = await _dio.delete('api/categories/$id');
    if ((res.statusCode ?? 200) >= 400) {
      throw DioException(
        requestOptions: res.requestOptions,
        response: res,
        message: 'deleteCategory başarısız (${res.statusCode})',
      );
    }
  }

  Future<DealerProfile> fetchMyProfile() async {
    final res = await _dio.get('profile'); // baseUrl: .../api/v1/

    // Eğer Laravel'de profile() şöyle:
    // return $this->json_custom_response([ 'id' => ..., 'name' => ...]);
    // ise:
    final data = res.data as Map<String, dynamic>;

    // Eğer şöyle döndürürsen:
    // return $this->json_custom_response(['data' => [ 'id' => ..., ...]]);
    // o zaman:
    // final data = res.data['data'] as Map<String, dynamic>;

    final profile = DealerProfile.fromJson(data);
    currentProfile = profile;
    return profile;
  }

// --- PROFİL GÜNCELLEME ---
  Future<DealerProfile> updateMyProfile(Map<String, dynamic> payload) async {
    // endpoint’i senin route’una göre değiştir:
    // örn: POST /api/v1/profile/update -> 'profile/update'
    final res = await _dio.post('profile/update', data: payload);
    final data = res.data;

    final Map<String, dynamic> json;
    if (data is Map<String, dynamic> && data['data'] is Map) {
      json = Map<String, dynamic>.from(data['data'] as Map);
    } else {
      json = Map<String, dynamic>.from(data as Map);
    }

    final profile = DealerProfile.fromJson(json);
    currentProfile = profile;
    return profile;
  }

  Future<void> uploadProfileDocument({
    required String type,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final formData = FormData.fromMap({
      'type': type, // backend’de belge tipini ayırt etmek için
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
      ),
    });

    // Laravel tarafında UserController veya ayrı DocumentController’da
    // örn: Route::post('profile/documents', [UserController::class, 'uploadDocument']);
    await _dio.post('profile/documents', data: formData);
  }

  // --- ŞİFRE DEĞİŞTİRME ---
  Future<void> changePassword(String oldPassword, String newPassword) async {
    // Laravel UserController@changePassword route’u neyse onu kullan:
    // örn: POST /api/v1/change-password
    await _dio.post('change-password', data: {
      'old_password': oldPassword,
      'new_password': newPassword,
    });
  }
}
