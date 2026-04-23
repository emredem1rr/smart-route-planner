// ─────────────────────────────────────────────────────────────
//  ApiConstants — 4 Senaryo için akıllı URL seçimi
//
//  1) Emülatörde geliştirme  : flutter run
//  2) Kablolu geliştirme     : flutter run --dart-define=REAL_DEVICE=true
//  3) Kablo çıktıktan sonra  : WiFi IP ile (aynı ağda)
//  4) APK yüklenmiş          : WiFi IP ile (aynı ağda)
// ─────────────────────────────────────────────────────────────

class ApiConstants {
  // ═══════════════════════════════════════════════════════════
  //  !! SADECE BU SATIRI DEĞİŞTİR !!
  //  Windows'ta: ipconfig → "IPv4 Adresi" → örn: 192.168.1.45
  //  Mac/Linux : ifconfig → en0/wlan0 → inet 192.168.x.x
  static const String pcIp = '172.20.10.2';
  // ═══════════════════════════════════════════════════════════

  static const String googleApiKey =
      'AIzaSyBQ-u9Y2fKKuTCDBj3Mc-9c3v16N0snpf8';

  // flutter run --dart-define=REAL_DEVICE=true ile true olur
  static const bool _cable =
  bool.fromEnvironment('REAL_DEVICE', defaultValue: false);

  // flutter run (dart define olmadan) = emülatör
  static const bool _emulator = !_cable;

  // Hangi host kullanılacak:
  //   Emülatör → 10.0.2.2  (emülatörün host PC alias'ı)
  //   Kablolu  → localhost  (adb reverse ile tünellenir)
  //   APK/WiFi → pcIp       (aynı WiFi ağında direkt IP)
  static String get _host {
    if (_emulator) return '10.0.2.2';
    if (_cable)    return 'localhost';
    return pcIp;
  }

  static String get baseUrl             => 'http://$_host:3000/api';
  static String get optimizationBaseUrl => 'http://$_host:8000';

  // Fallback: localhost çalışmazsa WiFi IP'yi dene
  static String get baseUrlFallback             => 'http://$pcIp:3000/api';
  static String get optimizationBaseUrlFallback => 'http://$pcIp:8000';
}