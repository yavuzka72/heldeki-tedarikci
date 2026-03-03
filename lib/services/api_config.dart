class ApiConfig {
  /// iOS Sim: http://192.168.64.2
  /// Android Emu: http://10.0.2.2:8000
  /// Prod: http://192.168.64.2
  static String base = 'http://192.168.64.2'; // değiştirilebilir
  static String get v1 => '$base/api/v1';
}
