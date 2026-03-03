// lib/services/session.dart
import 'dart:convert';

class UserSession {
  final int userId;
  final int dealerId;
  final int vendorId;
  final String email;
  final String name;
  final String? city;
  final String? district;

  final String? adress;
  final bool rememberMe;

  const UserSession({
    required this.userId,
    required this.dealerId,
    required this.vendorId,
    required this.email,
    required this.name,
    this.city,
    this.district,
    this.adress,
    this.rememberMe = false,
  });

  // --- JSON ---
  Map<String, dynamic> toJson() => {
        'userId': userId,
        'dealerId': dealerId,
        'vendorId': vendorId,
        'email': email,
        'name': name,
        'city': city,
        'district': district,
        'adress': adress,
      };

  factory UserSession.fromJson(Map<String, dynamic> m) => UserSession(
        userId: m['userId'] ?? 0,
        dealerId: m['dealerId'] ?? 0,
        vendorId: m['vendorId'] ?? 0,
        email: (m['email'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        city: m['city'] as String?,
        district: m['district'] as String?,
        adress: m['adress'] as String?,
        rememberMe: m['rememberMe'] ?? false,
      );

  // --- copyWith (LoginScreen hatası için eklendi) ---
  UserSession copyWith({
    int? userId,
    int? dealerId,
    int? vendorId,
    String? email,
    String? name,
    String? city,
    String? district,
    String? adress,
    bool? rememberMe,
  }) {
    return UserSession(
      userId: userId ?? this.userId,
      dealerId: dealerId ?? this.dealerId,
      vendorId: vendorId ?? this.vendorId,
      email: email ?? this.email,
      name: name ?? this.name,
      city: city ?? this.city,
      district: district ?? this.district,
      adress: adress ?? this.adress,
      rememberMe: rememberMe ?? this.rememberMe,
    );
  }

  // --- Yardımcı parse fonksiyonları ---
  static int? _pickInt(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is String) {
        final p = int.tryParse(v);
        if (p != null) return p;
      }
    }
    return null;
  }

  static String? _pickStr(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// Login yanıtından, kökte veya `data` / `user` içinde gelebilecek alanları esnekçe okur.
  static UserSession fromLoginResponse(
    dynamic data, {
    String? emailFallback,
    String? nameFallback,
    bool rememberMe = false, // 👈 parametre eklendi
  }) {
    Map root = {};
    if (data is Map) {
      root = data;
      if (root['data'] is Map) root = root['data'];
    }

    Map user = {};
    if (root['user'] is Map) {
      user = root['user'];
    } else {
      user = root;
    }

    final userId = _pickInt(user, ['id', 'user_id']) ?? 0;
    final vendorId = _pickInt(user, ['vendor_id']) ?? userId;
    final dealerId = _pickInt(user, ['dealer_id']) ?? vendorId;
    final email = _pickStr(user, ['email']) ?? emailFallback ?? '';
    final name = _pickStr(user, ['name']) ?? nameFallback ?? '';
    final city = _pickStr(user, ['city', 'il']);
    final district = _pickStr(user, ['district', 'ilce']);
    final adress = _pickStr(user, ['adress', 'address']);

    return UserSession(
      userId: userId,
      dealerId: dealerId,
      vendorId: vendorId,
      email: email,
      name: name,
      city: city,
      district: district,
      adress: adress,
      rememberMe: rememberMe, // 👈 set edildi
    );
  }

  String toEncoded() => jsonEncode(toJson());
  factory UserSession.fromEncoded(String s) =>
      UserSession.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
