import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyDark = 'dark_mode';
  static const _keyLang = 'language';

  bool   _isDark   = false;
  String _language = 'tr';

  bool      get isDark    => _isDark;
  String    get language  => _language;
  Locale    get locale    => Locale(_language);
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  static const Map<String, String> _tr = {
    'todays_tasks':    'Bugünün Görevleri',
    'start_location':  'Başlangıç Konumu',
    'no_location':     'Konum alınmadı',
    'get_location':    'Konum Al',
    'optimize_route':  'Rotayı Optimize Et',
    'optimizing':      'Optimize ediliyor...',
    'no_location_err': 'Önce konumunuzu alın',
    'no_tasks_today':  'Bugün görev yok',
    'add_task_hint':   '+ butonuna basarak görev ekle',
    'refresh':         'Yenile',
    'profile':         'Profil',
    'calendar':        'Takvim',
    'benchmark':       'Benchmark',
    'logout':          'Çıkış',
    'status_pending':  'Bekliyor',
    'status_done':     'Tamamlandı',
    'status_cancelled':'İptal',
    'task_name':       'Görev Adı',
    'address':         'Adres',
    'duration':        'Süre (dakika)',
    'priority':        'Öncelik',
    'task_date':       'Tarih',
    'start_time':      'Başlangıç Saati',
    'recurrence':      'Tekrar',
    'recurring_task':  'Tekrarlayan Görev',
    'every_day':       'Her Gün',
    'weekdays':        'Hafta İçi',
    'weekly':          'Haftalık',
    'which_days':      'Hangi günler?',
    'save':            'Kaydet',
    'edit_task':       'Görevi Düzenle',
    'today':           'Bugün',
    'tomorrow':        'Yarın',
    'add_task':        'Görev Ekle',
    'settings':        'Ayarlar',
    'cancel':          'İptal',
    'delete':          'Sil',
    'confirm':         'Onayla',
    'loading':         'Yükleniyor...',
    'no_tasks':        'Görev yok',
    'error':           'Hata',
    'success':         'Başarılı',
  };

  String Function(String) get t => (key) => _tr[key] ?? key;

  SettingsProvider() { _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _isDark   = p.getBool(_keyDark)  ?? false;
    _language = p.getString(_keyLang) ?? 'tr';
    notifyListeners();
  }

  Future<void> toggleDark(bool val) async {
    _isDark = val;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyDark, val);
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyLang, lang);
  }
}