import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'place_detail_screen.dart';
import 'favorites_screen.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/location_service.dart';
import '../../core/models/task_model.dart';
import '../../core/models/optimize_request_model.dart';
import '../../core/services/api_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/theme/app_theme.dart';
import '../route/route_result_screen.dart';

// ── Modeller ──────────────────────────────────────────────────────────────────

class PlaceItem {
  final String name, address, placeId, aiReason;
  final double rating, latitude, longitude, matchScore;
  final List<String> types;
  final int priceLevel;
  final bool? openNow;
  bool selected;

  PlaceItem({
    required this.name,
    required this.address,
    required this.placeId,
    required this.aiReason,
    required this.rating,
    required this.latitude,
    required this.longitude,
    required this.matchScore,
    required this.types,
    this.priceLevel = -1,
    this.openNow,
    this.selected   = true,
  });

  factory PlaceItem.fromJson(Map<String, dynamic> j) => PlaceItem(
    name        : j['name']         ?? '',
    address     : j['address']      ?? '',
    placeId     : j['place_id']     ?? '',
    aiReason    : j['ai_reason']    ?? '',
    rating      : (j['rating']      ?? 0).toDouble(),
    latitude    : (j['latitude']    ?? 0).toDouble(),
    longitude   : (j['longitude']   ?? 0).toDouble(),
    matchScore  : (j['match_score'] ?? 0).toDouble(),
    types       : List<String>.from(j['types'] ?? []),
    priceLevel  : (j['price_level'] ?? -1) as int,
    openNow     : j['open_now'] as bool?,
  );
}

class UserPreferences {
  String ageGroup, budget, groupType, indoorOutdoor;
  bool wheelchair, childFriendly;

  UserPreferences({
    this.ageGroup      = 'yetiskin',
    this.budget        = 'orta',
    this.groupType     = 'yalniz',
    this.indoorOutdoor = 'ikisi',
    this.wheelchair    = false,
    this.childFriendly = false,
  });

  Map<String, dynamic> toJson() => {
    'age_group'      : ageGroup,
    'budget'         : budget,
    'group_type'     : groupType,
    'indoor_outdoor' : indoorOutdoor,
    'wheelchair'     : wheelchair,
    'child_friendly' : childFriendly,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> j) => UserPreferences(
    ageGroup      : j['age_group']      ?? 'yetiskin',
    budget        : j['budget']         ?? 'orta',
    groupType     : j['group_type']     ?? 'yalniz',
    indoorOutdoor : j['indoor_outdoor'] ?? 'ikisi',
    wheelchair    : j['wheelchair']     ?? false,
    childFriendly : j['child_friendly'] ?? false,
  );
}

// ── 5 Kategori ────────────────────────────────────────────────────────────────

// Google Places API'de gerçek karşılığı olan kategoriler
const _categories = [
  {'key': 'restaurant', 'label': 'Yemek',     'icon': Icons.restaurant_outlined,    'gtype': 'restaurant|cafe|bakery|bar'},
  {'key': 'tourist_attraction', 'label': 'Gezinti', 'icon': Icons.museum_outlined,  'gtype': 'museum|tourist_attraction|church|mosque|synagogue'},
  {'key': 'amusement_park', 'label': 'Eğlence', 'icon': Icons.celebration_outlined,'gtype': 'amusement_park|movie_theater|bowling_alley|night_club'},
  {'key': 'shopping_mall', 'label': 'Alışveriş','icon': Icons.shopping_bag_outlined,'gtype': 'shopping_mall|store|clothing_store|book_store'},
  {'key': 'park',       'label': 'Doğa',       'icon': Icons.park_outlined,         'gtype': 'park|natural_feature|campground'},
];

// ── Ana Ekran ─────────────────────────────────────────────────────────────────

class SuggestScreen extends StatefulWidget {
  const SuggestScreen({super.key});
  @override
  State<SuggestScreen> createState() => _SuggestScreenState();
}

class _SuggestScreenState extends State<SuggestScreen> with AutomaticKeepAliveClientMixin {
  final _cityCtrl     = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _maxCtrl      = TextEditingController(text: '8');

  final Set<String> _activeCategories = {'yemek'};
  List<String>    _cityHistory = [];
  String          _category    = 'restaurant';
  String          _subcategory = '';
  int             _radiusKm    = 0;
  UserPreferences _prefs       = UserPreferences();
  String          _lastCity    = '';

  // Her kategori için ayrı state
  final Map<String, List<PlaceItem>> _catPlaces  = {};
  final Map<String, String>          _catSummary = {};
  final Map<String, bool>            _catLoading = {};
  final Map<String, String?>         _catError   = {};

  // Aktif kategorinin state'i
  List<PlaceItem> get _places  => _catPlaces[_category]  ?? [];
  String          get _summary => _catSummary[_category] ?? '';
  bool            get _loading => _catLoading[_category] ?? false;
  String?         get _error   => _catError[_category];

  // Cache — şehir|kategori|subcat|radius → sonuçlar (persistent)
  final Map<String, List<PlaceItem>> _memCache   = {};
  final Map<String, String>          _memSummary = {};

  // Eski uyumluluk
  Map<String, List<PlaceItem>> get _resultsCache => _memCache;
  Map<String, String>          get _summaryCache => _memSummary;
  static final Map<String, List<PlaceItem>> _globalCache        = {};
  static final Map<String, String>          _globalSummaryCache = {};

  String get _cacheKey => '${_activeCategories.toList()..sort()}|$_subcategory|$_radiusKm';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _loadPrefs(); }

  @override
  void dispose() {
    _cityCtrl.dispose(); _districtCtrl.dispose(); _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final raw = await StorageService().getString('user_preferences_v2');
    if (raw != null) {
      try { setState(() => _prefs = UserPreferences.fromJson(jsonDecode(raw))); } catch (_) {}
    }
    _loadCityHistory();
    _loadPersistentCache();
  }

  // Persistent cache — uygulama kapanıp açılsa da korunsun
  Future<void> _loadPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys  = prefs.getStringList('suggest_cache_keys') ?? [];
      for (final key in keys) {
        final raw = prefs.getString('suggest_cache_$key');
        if (raw != null) {
          final data    = jsonDecode(raw);
          final places  = (data['places'] as List).map((p) => PlaceItem.fromJson(p)).toList();
          final summary = data['summary'] as String? ?? '';
          _memCache[key]   = places;
          _memSummary[key] = summary;
          // global cache'e de yükle
          _globalCache[key]        = places;
          _globalSummaryCache[key] = summary;
        }
      }
    } catch (_) {}
  }

  Future<void> _savePersistentCache(String key, List<PlaceItem> places, String summary) async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final keys      = prefs.getStringList('suggest_cache_keys') ?? [];
      if (!keys.contains(key)) {
        keys.add(key);
        // Max 20 kayıt tut
        if (keys.length > 20) {
          final oldest = keys.removeAt(0);
          await prefs.remove('suggest_cache_$oldest');
        }
        await prefs.setStringList('suggest_cache_keys', keys);
      }
      await prefs.setString('suggest_cache_$key', jsonEncode({
        'places':  places.map((p) => {
          'name':        p.name,
          'address':     p.address,
          'place_id':    p.placeId,
          'ai_reason':   p.aiReason,
          'rating':      p.rating,
          'latitude':    p.latitude,
          'longitude':   p.longitude,
          'match_score': p.matchScore,
          'types':       p.types,
          'price_level': p.priceLevel,
          'open_now':    p.openNow,
        }).toList(),
        'summary': summary,
      }));
    } catch (_) {}
  }

  Future<void> _savePrefs() async =>
      StorageService().setString('user_preferences_v2', jsonEncode(_prefs.toJson()));

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.success,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _loadCityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cityHistory = prefs.getStringList('city_history') ?? [];
    });
  }

  Future<void> _saveCityToHistory(String city) async {
    if (city.isEmpty) return;
    _cityHistory.remove(city); // tekrar ekleme
    _cityHistory.insert(0, city);
    if (_cityHistory.length > 8) _cityHistory = _cityHistory.sublist(0, 8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('city_history', _cityHistory);
    setState(() {});
  }

  Future<void> _search() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) {
      setState(() {
        _catPlaces.clear(); _catSummary.clear();
        _catLoading.clear(); _catError.clear();
      });
      return;
    }

    _saveCityToHistory(city);

    // Şehir değiştiyse tüm kategori state'lerini sıfırla
    final district = _districtCtrl.text.trim();
    // Şehir VEYA ilçe değiştiyse cache'i sıfırla
    final locationKey = '${city.toLowerCase()}|$district';
    if (_lastCity.isNotEmpty && _lastCity.toLowerCase() != locationKey) {
      setState(() {
        _catPlaces.clear(); _catSummary.clear();
        _catLoading.clear(); _catError.clear();
        _memCache.clear(); _memSummary.clear();
      });
    }
    _lastCity = '${city.toLowerCase()}|$district';
    final cacheKey = '${city.toLowerCase()}|$district|$_category|$_subcategory|$_radiusKm';

    // Cache'de bu şehir+kategori varsa anında göster
    if (_memCache.containsKey(cacheKey)) {
      setState(() {
        _catPlaces[_category]  = List.from(_memCache[cacheKey]!);
        _catSummary[_category] = _memSummary[cacheKey] ?? '';
        _catError[_category]   = null;
      });
      // Arka planda tazele + diğer kategorileri prefetch et
      _fetchAndCache(city, _category, _subcategory, _radiusKm, cacheKey, background: true);
      _prefetchOtherCategories(city);
      return;
    }

    // Cache yok — önce istenen kategori için hemen fetch başlat (kullanıcı görsün)
    // Aynı anda arka planda diğerleri de başlasın
    await _fetchAndCache(city, _category, _subcategory, _radiusKm, cacheKey, background: false);
    // Aktif fetch bitti, şimdi diğerlerini arka planda başlat
    _prefetchOtherCategories(city);
  }

  Future<void> _fetchAndCache(
      String city, String category, String subcategory, int radius, String cacheKey,
      {required bool background}
      ) async {
    if (!background && mounted) setState(() => _catLoading[category] = true);
    try {
      final resp = await http.post(
        Uri.parse('${ApiConstants.optimizationBaseUrl}/suggest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'city'        : city,
          'district'    : _districtCtrl.text.trim(),
          'category'    : category,
          'subcategory' : subcategory,
          'radius_km'   : radius,
          'api_key'     : ApiConstants.googleApiKey,
          'max_results' : int.tryParse(_maxCtrl.text) ?? 8,
          'preferences' : _prefs.toJson(),
        }),
      ).timeout(const Duration(seconds: 120));

      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        final places  = (data['places'] as List).map((p) => PlaceItem.fromJson(p)).toList();
        final summary = data['summary'] as String? ?? '';

        // Bellek cache
        _memCache[cacheKey]    = places;
        _memSummary[cacheKey]  = summary;
        _globalCache[cacheKey]        = places;
        _globalSummaryCache[cacheKey] = summary;

        // Persistent cache
        _savePersistentCache(cacheKey, places, summary);

        // Kategori state'ini güncelle
        if (mounted) {
          setState(() {
            _catPlaces[category]  = places;
            _catSummary[category] = summary;
            _catError[category]   = null;
          });
        }
      } else {
        if (!background && mounted) {
          setState(() => _catError[category] = data['error'] ?? 'Hata oluştu.');
        }
      }
    } catch (e) {
      if (!background && mounted) {
        setState(() => _catError[category] = 'Bağlantı hatası: $e');
      }
    } finally {
      if (!background && mounted) setState(() => _catLoading[category] = false);
    }
  }

  // Arka planda diğer kategorileri prefetch et — kullanıcıya karışmaz
  void _prefetchOtherCategories(String city) {
    const cats = ['restaurant', 'tourist_attraction', 'amusement_park', 'shopping_mall', 'park'];
    final district = _districtCtrl.text.trim();
    int delay = 2;
    for (final cat in cats) {
      if (cat == _category) continue;
      final key = '${city.toLowerCase()}|$district|$cat||$_radiusKm';
      if (_memCache.containsKey(key)) continue;
      final d = delay;
      Future.delayed(Duration(seconds: d), () {
        if (!mounted) return;
        _fetchAndCache(city, cat, '', _radiusKm, key, background: true);
      });
      delay += 4;
    }
  }


  Future<void> _deleteAndRefresh(PlaceItem place) async {
    final excludeIds = _places.map((p) => p.placeId).toList();
    setState(() => _catPlaces[_category]?.removeWhere((p) => p.placeId == place.placeId));
    final loading = PlaceItem(
      name: 'Yeni mekan aranıyor...', address: '', placeId: '__loading__',
      aiReason: '', rating: 0, latitude: 0, longitude: 0,
      matchScore: 0, types: [], selected: false,
    );
    setState(() {
      if (_catPlaces[_category] != null) {
        _catPlaces[_category]!.add(loading);
      } else {
        _catPlaces[_category] = [loading];
      }
    });

    try {
      final resp = await http.post(
        Uri.parse('${ApiConstants.optimizationBaseUrl}/suggest/refresh-place'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'city'        : _cityCtrl.text.trim(),
          'district'    : _districtCtrl.text.trim(),
          'category'    : _activeCategories.join(','),
          'subcategory' : _subcategory,
          'radius_km'   : _radiusKm,
          'api_key'     : ApiConstants.googleApiKey,
          'exclude_ids' : excludeIds,
          'preferences' : _prefs.toJson(),
        }),
      ).timeout(const Duration(seconds: 60));

      final data = jsonDecode(resp.body);
      setState(() => _catPlaces[_category]?.removeWhere((p) => p.placeId == '__loading__'));
      if (data['success'] == true) {
        setState(() => _places.add(PlaceItem.fromJson(data['place'])));
      } else {
        _snack('Yeni mekan bulunamadı.', error: true);
      }
    } catch (_) {
      setState(() => _catPlaces[_category]?.removeWhere((p) => p.placeId == '__loading__'));
      _snack('Bağlantı hatası.', error: true);
    }
  }

  Future<int?> _askDuration(String placeName) async {
    int selected = 60;
    return await showDialog<int>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface(context),
          title: Text(
            placeName,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 15, fontWeight: FontWeight.w700,
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Bu mekanda ne kadar vakit geçireceksin?',
                style: TextStyle(color: AppColors.textSecond(context), fontSize: 13)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [30, 60, 90, 120, 180].map((min) {
                final label = min < 60
                    ? '$min dk'
                    : min == 60 ? '1 saat'
                    : min == 90 ? '1.5 saat'
                    : '${min ~/ 60} saat';
                final isSel = selected == min;
                return GestureDetector(
                  onTap: () => setDialogState(() => selected = min),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? const Color(0xFF6366F1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSel ? const Color(0xFF6366F1) : AppColors.border(context),
                      ),
                    ),
                    child: Text(label,
                      style: TextStyle(
                        color: isSel ? Colors.white : AppColors.textSecond(context),
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('İptal', style: TextStyle(color: AppColors.textSecond(context))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Tamam'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _optimizeRoute() async {
    final selected = _places.where((p) => p.selected).toList();
    if (selected.isEmpty) { _snack('En az 1 mekan seçin.', error: true); return; }

    // Tarih seç
    final pickedDate = await showDatePicker(
      context:      context,
      initialDate:  DateTime.now(),
      firstDate:    DateTime.now(),
      lastDate:     DateTime.now().add(const Duration(days: 365)),
      locale:       const Locale('tr', 'TR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary:   const Color(0xFF6366F1),
            onPrimary: Colors.white,
            surface:   AppColors.surface(context),
            onSurface: AppColors.textPrimary(context),
          ),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !mounted) return;
    final taskDate = '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';

    setState(() => _catLoading[_category] = true);
    try {
      final position = await LocationService().getCurrentLocation();
      final tasks = selected.asMap().entries.map((e) => TaskModel(
        id: e.key + 1, name: e.value.name, address: e.value.address,
        latitude: e.value.latitude, longitude: e.value.longitude,
        duration: 0,
        priority: 3, earliestStart: 0, latestFinish: 1440,
        taskDate: taskDate,
        status: 'pending', isRecurring: false,
      )).toList();

      final response = await ApiService().optimize(OptimizeRequest(
        startLocation: StartLocation(latitude: position.latitude, longitude: position.longitude),
        tasks:  tasks,
        config: OptimizationConfig(
            heuristic: 'euclidean', populationSize: 50,
            generations: 100, useRealRoads: true),
      ));
      if (!mounted) return;

      if (response.success && response.result != null) {
        final save = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title:   const Text('Rota Hazır!'),
            content: const Text('Mekanları görev listene de eklemek ister misin?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Sadece rotayı gör')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true),
                  child: const Text('Evet, kaydet')),
            ],
          ),
        );
        if (save == true && mounted) {
          int saved = 0;
          for (final t in tasks) { if (await SyncService().saveTask(t)) saved++; }
          if (mounted) _snack('$saved mekan görev listene eklendi!');
        }
        if (!mounted) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => RouteResultScreen(response: response),
        ));
      } else {
        _snack(response.error ?? 'Optimizasyon başarısız.', error: true);
      }
    } catch (e) {
      _snack('Hata: $e', error: true);
    } finally {
      setState(() => _catLoading[_category] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryPicker(context),
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      appBar: AppBar(
        backgroundColor:  surf,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.surfaceHigh(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border)),
            child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
          ),
        ),
        title: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.explore_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('Şehir Keşfet', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            child: Container(
              width: 34, height: 34,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                  color: AppColors.surfaceHigh(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border)),
              child: const Icon(Icons.bookmark_rounded,
                  color: Color(0xFF6366F1), size: 17),
            ),
          ),
          GestureDetector(
            onTap: () => _showPrefsSheet(surf, border, tp, ts),
            child: Container(
              width: 34, height: 34,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                  color: AppColors.surfaceHigh(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border)),
              child: Icon(Icons.tune_rounded, color: tp, size: 17),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Column(children: [
        _buildSearchBar(surf, border, tp, ts),
        _buildCategoryBar(surf, border, tp, ts),
        _buildSubcategoryBar(surf, border, tp, ts),
        _buildRadiusBar(surf, border, tp, ts),
        Expanded(child: _buildContent(surf, border, tp, ts)),
        if (_places.isNotEmpty && !_loading) _buildRouteButton(),
      ]),
    );
  }

  Widget _buildSearchBar(Color surf, Color border, Color tp, Color ts) {
    return Container(
      color:   surf,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(children: [
        Row(children: [
          Expanded(
            flex: 5,
            child: _field(
              controller: _cityCtrl, hint: 'Şehir',
              icon: Icons.location_city_outlined,
              surf: surf, border: border, tp: tp, ts: ts,
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: _field(
              controller: _districtCtrl, hint: 'İlçe (opsiyonel)',
              icon: Icons.map_outlined,
              surf: surf, border: border, tp: tp, ts: ts,
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: _field(
              controller: _maxCtrl, hint: '8',
              icon: Icons.format_list_numbered,
              keyboardType: TextInputType.number,
              surf: surf, border: border, tp: tp, ts: ts,
              showIcon: false,
            ),
          ),
        ]),
        // Şehir geçmişi — Row'dan ayrı, tam genişlikte
        if (_cityHistory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: _cityHistory.map((c) =>
                  GestureDetector(
                    onTap: () { _cityCtrl.text = c; _search(); },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.history, size: 11, color: Color(0xFF6366F1)),
                        const SizedBox(width: 4),
                        Text(c, style: const TextStyle(color: const Color(0xFF6366F1),
                            fontSize: 11, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  )
              ).toList()),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _search,
            icon:  const Icon(Icons.auto_awesome, size: 17),
            label: const Text('AI ile Keşfet',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              padding:   const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }

  // Alt kategori bar — seçili kategoriye göre dinamik
  Widget _buildSubcategoryBar(Color surf, Color border, Color tp, Color ts) {
    final subcats = _getSubcategories();
    if (subcats.isEmpty) return const SizedBox.shrink();

    return Container(
      color:  surf,
      height: 44,
      child: ListView.separated(
        padding:          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection:  Axis.horizontal,
        itemCount:        subcats.length + 1,  // +1 "Tümü"
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            final sel = _subcategory.isEmpty;
            return _subChip('Tümü', '', sel, border, ts);
          }
          final sub = subcats[i - 1];
          final sel = _subcategory == sub['key'];
          return _subChip(sub['label']!, sub['key']!, sel, border, ts);
        },
      ),
    );
  }

  Widget _subChip(String label, String key, bool sel, Color border, Color ts) {
    return GestureDetector(
      onTap: () => setState(() {
        _subcategory = key;
        final newKey = '$_category|$key|$_radiusKm';
        _catPlaces[_category]  = _resultsCache[newKey] ?? [];
        _catSummary[_category] = _summaryCache[newKey] ?? '';
        _catError[_category]   = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding:  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color:        sel ? const Color(0xFF6366F1).withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(
              color: sel ? const Color(0xFF6366F1) : border, width: sel ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize:   12,
              color:      sel ? const Color(0xFF6366F1) : ts,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
            )),
      ),
    );
  }

  List<Map<String, String>> _getSubcategories() {
    // Google Places API type'larına birebir karşılık gelen alt kategoriler
    const subs = {
      'restaurant' : [
        {'key': 'restaurant', 'label': 'Restoran'},
        {'key': 'cafe',       'label': 'Kafe'},
        {'key': 'bakery',     'label': 'Pastane & Fırın'},
        {'key': 'bar',        'label': 'Bar'},
      ],
      'tourist_attraction': [
        {'key': 'museum',             'label': 'Müzeler'},
        {'key': 'tourist_attraction', 'label': 'Tarihi Yerler'},
        {'key': 'art_gallery',        'label': 'Sanat Galerisi'},
        {'key': 'church',             'label': 'Dini Mekanlar'},
      ],
      'amusement_park': [
        {'key': 'amusement_park',  'label': 'Eğlence Parkı'},
        {'key': 'movie_theater',   'label': 'Sinema'},
        {'key': 'bowling_alley',   'label': 'Bowling'},
        {'key': 'night_club',      'label': 'Gece Hayatı'},
      ],
      'shopping_mall': [
        {'key': 'shopping_mall', 'label': 'AVM'},
        {'key': 'clothing_store','label': 'Giyim'},
        {'key': 'book_store',    'label': 'Kitapçı'},
        {'key': 'supermarket',   'label': 'Market'},
      ],
      'park': [
        {'key': 'park',        'label': 'Park & Bahçe'},
        {'key': 'campground',  'label': 'Kamp & Doğa'},
        {'key': 'zoo',         'label': 'Hayvanat Bahçesi'},
        {'key': 'beach',       'label': 'Plaj & Sahil'},
      ],
    };
    return List<Map<String, String>>.from(subs[_category] ?? []);
  }

  Widget _buildRadiusBar(Color surf, Color border, Color tp, Color ts) {
    final district = _districtCtrl.text.trim();
    final areaName = district.isNotEmpty ? district : _cityCtrl.text.trim();
    final label = _radiusKm == 0 ? (areaName.isEmpty ? 'Tüm Alan' : 'Tüm $areaName') : '$_radiusKm km';
    return Container(
      color:   AppColors.bg(context),
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(children: [
        Icon(Icons.my_location_rounded, size: 14, color: const Color(0xFF3D9CF5)),
        const SizedBox(width: 6),
        Text('Yarıçap:', style: TextStyle(fontSize: 12, color: ts)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color:        const Color(0xFF3D9CF5).withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border:       Border.all(color: const Color(0xFF3D9CF5).withOpacity(0.4)),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: Color(0xFF3D9CF5))),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor:   const Color(0xFF3D9CF5),
              inactiveTrackColor: const Color(0xFF3D9CF5).withOpacity(0.15),
              thumbColor:         const Color(0xFF3D9CF5),
              overlayColor:       const Color(0xFF3D9CF5).withOpacity(0.12),
              trackHeight:        3,
              thumbShape:         const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value:      _radiusKm.toDouble(),
              min:        0,
              max:        50,
              divisions:  50,
              onChanged: (v) => setState(() => _radiusKm = v.toInt()),
              onChangeEnd: (v) {
                final rKey = '$_category|$_subcategory|${v.toInt()}';
                setState(() {
                  _catPlaces[_category]  = _resultsCache[rKey] ?? [];
                  _catSummary[_category] = _summaryCache[rKey] ?? '';
                  _catError[_category]   = null;
                });
              },
            ),
          ),
        ),
      ]),
    );
  }
  Widget _field({
    required TextEditingController controller,
    required String hint, required IconData icon,
    required Color surf, required Color border,
    required Color tp, required Color ts,
    TextInputType? keyboardType,
    ValueChanged<String>? onSubmitted,
    bool showIcon = true,
  }) {
    return TextField(
      controller: controller, keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: TextStyle(color: tp, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint, hintStyle: TextStyle(color: ts, fontSize: 12),
        prefixIcon: showIcon ? Icon(icon, color: ts, size: 17) : null,
        filled: true, fillColor: surf,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: const Color(0xFF6366F1), width: 1.5)),
      ),
    );
  }

  Widget _buildCategoryBar(Color surf, Color border, Color tp, Color ts) {
    return Container(
      color:  surf,
      height: 52,
      child: ListView.separated(
        padding:          const EdgeInsets.fromLTRB(16, 8, 16, 8),
        scrollDirection:  Axis.horizontal,
        itemCount:        _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final key = cat['key'] as String;
          final sel = key == _category;
          // Prefetch loading göstergesi
          final isPrefetching = !sel && _catLoading[key] == true;
          return GestureDetector(
            onTap: () {
              setState(() {
                _category    = key;
                _subcategory = '';
                _catError[key] = null;
              });
              final city = _cityCtrl.text.trim();
              if (city.isNotEmpty) _search();
              else setState(() { _catPlaces[key] = []; _catSummary[key] = ''; });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color:        sel ? const Color(0xFF6366F1) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border:       Border.all(
                    color: sel ? const Color(0xFF6366F1) : border,
                    width: sel ? 1.5 : 1),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (isPrefetching)
                  SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: ts,
                      ))
                else
                  Icon(cat['icon'] as IconData, size: 14,
                      color: sel ? Colors.white : ts),
                const SizedBox(width: 5),
                Text(cat['label'] as String,
                    style: TextStyle(
                      color:      sel ? Colors.white : ts,
                      fontSize:   12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    )),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(Color surf, Color border, Color tp, Color ts) {
    if (_loading) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: const Color(0xFF6366F1)),
        const SizedBox(height: 16),
        Text('AI mekanları analiz ediyor...',
            style: TextStyle(color: tp, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Text('30–60 saniye sürebilir.',
            style: TextStyle(color: ts, fontSize: 12)),
      ]));
    }

    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.dangerDim, shape: BoxShape.circle),
            child: const Icon(Icons.error_outline, color: AppColors.danger, size: 32),
          ),
          const SizedBox(height: 14),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.danger, fontSize: 14)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _search,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Tekrar Dene'),
          ),
        ]),
      ));
    }

    if (_places.isEmpty) {
      // Boş durum — kategori seçilmiş, arama bekleniyor
      final cat = _categories.firstWhere((c) => c['key'] == _category);
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(color: const Color(0xFFEEF2FF), shape: BoxShape.circle),
          child: Icon(cat['icon'] as IconData, size: 36, color: const Color(0xFF6366F1)),
        ),
        const SizedBox(height: 14),
        Text('${cat['label']} için şehir gir',
            style: TextStyle(color: tp, fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 6),
        Text('Sağ üstteki ayarlar ile tercihlerini belirle',
            style: TextStyle(color: ts, fontSize: 13)),
      ]));
    }

    return Column(children: [
      if (_summary.isNotEmpty)
        Container(
          margin:  const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:        const Color(0xFF3D9CF5).withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: const Color(0xFF3D9CF5).withOpacity(0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome, color: Color(0xFF3D9CF5), size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(_summary,
                style: TextStyle(fontSize: 12, color: ts))),
          ]),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_places.where((p) => p.selected).length}/${_places.length} seçili',
                style: TextStyle(color: tp, fontWeight: FontWeight.w600, fontSize: 13)),
            GestureDetector(
              onTap: () => setState(() {
                final all = _places.every((p) => p.selected);
                for (final p in _places) p.selected = !all;
              }),
              child: const Text('Tümünü Seç/Kaldır',
                  style: TextStyle(color: const Color(0xFF6366F1),
                      fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),

      Expanded(
        child: ListView.builder(
          padding:     const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount:   _places.length,
          itemBuilder: (_, i) => _buildPlaceCard(_places[i], surf, border, tp, ts),
        ),
      ),
    ]);
  }

  Widget _buildPlaceCard(PlaceItem p, Color surf, Color border, Color tp, Color ts) {
    if (p.placeId == '__loading__') {
      return Container(
        margin:  const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: surf, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(children: [
          SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF6366F1))),
          const SizedBox(width: 12),
          Text('Yeni mekan aranıyor...', style: TextStyle(color: ts, fontSize: 13)),
        ]),
      );
    }

    final matchPct   = (p.matchScore * 100).toInt();
    final matchColor = matchPct >= 70
        ? AppColors.success
        : matchPct >= 40
        ? AppColors.warn
        : AppColors.danger;

    // Fiyat göstergesi
    String priceLabel = '';
    if (p.priceLevel == 0) priceLabel = 'Ücretsiz';
    else if (p.priceLevel == 1) priceLabel = '₺';
    else if (p.priceLevel == 2) priceLabel = '₺₺';
    else if (p.priceLevel == 3) priceLabel = '₺₺₺';
    else if (p.priceLevel == 4) priceLabel = '₺₺₺₺';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surf, borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: p.selected ? const Color(0xFF6366F1).withOpacity(0.4) : border,
          width: p.selected ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => p.selected = !p.selected),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: p.selected ? const Color(0xFF6366F1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: p.selected ? const Color(0xFF6366F1) : border, width: 1.5),
                ),
                child: p.selected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(p.name,
                  style: TextStyle(color: tp, fontWeight: FontWeight.w600, fontSize: 14))),
              if (priceLabel.isNotEmpty) ...[
                Text(priceLabel, style: TextStyle(color: ts, fontSize: 11)),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color:        matchColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border:       Border.all(color: matchColor.withOpacity(0.3)),
                ),
                child: Text('%$matchPct',
                    style: TextStyle(fontSize: 10, color: matchColor,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),

        if (p.aiReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 0, 14, 6),
            child: Row(children: [
              const Icon(Icons.auto_awesome, size: 12, color: AppColors.warn),
              const SizedBox(width: 4),
              Expanded(child: Text(p.aiReason,
                  style: TextStyle(fontSize: 12, color: ts))),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(46, 0, 14, 10),
          child: Row(children: [
            const Icon(Icons.star_rounded, size: 13, color: AppColors.warn),
            const SizedBox(width: 3),
            Text('${p.rating}', style: TextStyle(fontSize: 12, color: ts)),
            if (p.openNow != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color:        p.openNow!
                      ? AppColors.success.withOpacity(0.12)
                      : AppColors.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  p.openNow! ? 'Açık' : 'Kapalı',
                  style: TextStyle(
                    fontSize: 10,
                    color:    p.openNow! ? AppColors.success : AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF3D9CF5)),
            const SizedBox(width: 3),
            Expanded(child: Text(p.address,
                style: TextStyle(fontSize: 11, color: ts),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(children: [
            _FavoriteButton(place: p),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PlaceDetailScreen(
                  placeId:   p.placeId,
                  name:      p.name,
                  address:   p.address,
                  latitude:  p.latitude,
                  longitude: p.longitude,
                  rating:    p.rating,
                  types:     p.types,
                  aiReason:  p.aiReason,
                ),
              )),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline_rounded, size: 13, color: const Color(0xFF6366F1)),
                  SizedBox(width: 4),
                  Text('Detay & Yorumlar',
                      style: TextStyle(fontSize: 11, color: const Color(0xFF6366F1),
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _deleteAndRefresh(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: AppColors.dangerDim, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.danger),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  void _showCategoryPicker(BuildContext context) {
    const categories = [
      {'key': 'yemek',     'label': 'Yemek & Kafe',      'icon': Icons.restaurant_outlined},
      {'key': 'gezinti',   'label': 'Gezinti & Kültür',   'icon': Icons.museum_outlined},
      {'key': 'eglence',   'label': 'Eğlence & Aktivite', 'icon': Icons.celebration_outlined},
      {'key': 'alisveris', 'label': 'Alışveriş',          'icon': Icons.shopping_bag_outlined},
      {'key': 'doga',      'label': 'Doğa & Park',        'icon': Icons.park_outlined},
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border(context),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text('Yeni Arama',
                style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Hangi kategoride arama yapmak istiyorsun?',
                style: TextStyle(
                    color: AppColors.textSecond(context), fontSize: 13)),
            const SizedBox(height: 16),
            ...categories.map((cat) => ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(cat['icon'] as IconData,
                    color: const Color(0xFF6366F1), size: 20),
              ),
              title: Text(cat['label'] as String,
                  style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.arrow_forward_ios,
                  size: 14, color: AppColors.textDim(context)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => _CategorySearchPage(
                    city:        _cityCtrl.text.trim(),
                    district:    _districtCtrl.text.trim(),
                    category:    cat['key'] as String,
                    preferences: _prefs,
                  ),
                ));
              },
            )).toList(),
          ]),
        ),
      ),
    );
  }

  Widget _buildRouteButton() {
    final count = _places.where((p) => p.selected).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color:  AppColors.surface(context),
        border: Border(top: BorderSide(color: AppColors.border(context))),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _optimizeRoute,
          icon:  const Icon(Icons.route_rounded, size: 18),
          label: Text('Rotayı Optimize Et ($count mekan)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            padding:   const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  void _showPrefsSheet(Color surf, Color border, Color tp, Color ts) {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    surf,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PrefsSheet(
        prefs:  _prefs,
        onSave: (p) { setState(() => _prefs = p); _savePrefs(); },
      ),
    );
  }
}

// ── Favori Butonu ─────────────────────────────────────────────────────────────
class _FavoriteButton extends StatefulWidget {
  final PlaceItem place;
  const _FavoriteButton({required this.place});
  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _isFav     = false;
  bool _loading   = false;
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkFav();
  }

  @override
  void dispose() { _noteCtrl.dispose(); super.dispose(); }

  Future<void> _checkFav() async {
    try {
      final token = await StorageService().getToken();
      final resp  = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/places/favorites/${widget.place.placeId}/check'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(resp.body);
      if (mounted) setState(() => _isFav = data['is_favorite'] == true);
    } catch (_) {}
  }

  Future<void> _toggle() async {
    setState(() => _loading = true);
    try {
      final token = await StorageService().getToken();
      if (_isFav) {
        await http.delete(
          Uri.parse('${ApiConstants.baseUrl}/places/favorites/${widget.place.placeId}'),
          headers: {'Authorization': 'Bearer $token'},
        );
        setState(() => _isFav = false);
      } else {
        // Not ekleyebilmek için dialog göster
        await _showFavDialog(token!);
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _showFavDialog(String token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Row(children: [
          const Icon(Icons.bookmark_add_rounded, color: const Color(0xFF6366F1), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.place.name,
              style: TextStyle(color: AppColors.textPrimary(context),
                  fontSize: 14, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Favorilere eklemek istiyor musun?',
              style: TextStyle(color: AppColors.textSecond(context), fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            style: TextStyle(color: AppColors.textPrimary(context), fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Not ekle (opsiyonel)...',
              hintStyle: TextStyle(color: AppColors.textSecond(context), fontSize: 12),
              filled: true, fillColor: AppColors.bg(context),
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border(context))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.border(context))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: const Color(0xFF6366F1), width: 1.5)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal', style: TextStyle(color: AppColors.textSecond(context))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/places/favorites'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'place_id' : widget.place.placeId,
          'name'     : widget.place.name,
          'address'  : widget.place.address,
          'latitude' : widget.place.latitude,
          'longitude': widget.place.longitude,
          'rating'   : widget.place.rating,
          'types'    : widget.place.types,
          'note'     : _noteCtrl.text.trim(),
        }),
      );
      setState(() => _isFav = true);
      _noteCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _loading ? null : _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _isFav
              ? AppColors.warn.withOpacity(0.12)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isFav ? AppColors.warn : AppColors.border(context),
          ),
        ),
        child: _loading
            ? const SizedBox(width: 13, height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.warn))
            : Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            _isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 13,
            color: _isFav ? AppColors.warn : AppColors.textSecond(context),
          ),
          const SizedBox(width: 4),
          Text(
            _isFav ? 'Favoride' : 'Favori',
            style: TextStyle(
              fontSize: 11,
              color: _isFav ? AppColors.warn : AppColors.textSecond(context),
              fontWeight: _isFav ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Kategori Arama Sayfası (+ butonundan açılır) ─────────────────────────────
class _CategorySearchPage extends StatefulWidget {
  final String city, district, category;
  final UserPreferences preferences;
  const _CategorySearchPage({
    required this.city, required this.district,
    required this.category, required this.preferences,
  });
  @override
  State<_CategorySearchPage> createState() => _CategorySearchPageState();
}

class _CategorySearchPageState extends State<_CategorySearchPage> {
  final _cityCtrl     = TextEditingController();
  final _districtCtrl = TextEditingController();
  List<String>    _cityHistory = [];
  String          _subcategory = '';
  int             _radiusKm   = 0;
  bool            _loading    = false;
  String?         _error;
  String          _summary    = '';
  List<PlaceItem> _places     = [];
  late UserPreferences _prefs;

  static const _catLabels = {
    'yemek'    : 'Yemek & Kafe',
    'gezinti'  : 'Gezinti & Kültür',
    'eglence'  : 'Eğlence & Aktivite',
    'alisveris': 'Alışveriş',
    'doga'     : 'Doğa & Park',
  };

  static const _subcatMap = {
    'yemek'    : [
      {'key': 'restoran', 'label': 'Restoran'},
      {'key': 'kafe',     'label': 'Kafe'},
      {'key': 'fastfood', 'label': 'Fast Food'},
      {'key': 'pastane',  'label': 'Pastane'},
      {'key': 'cokcocuk', 'label': 'Aile Dostu'},
    ],
    'gezinti'  : [
      {'key': 'muzeler',  'label': 'Müzeler'},
      {'key': 'tarihi',   'label': 'Tarihi Yerler'},
      {'key': 'sanat',    'label': 'Sanat'},
      {'key': 'ibadet',   'label': 'Dini Mekanlar'},
    ],
    'eglence'  : [
      {'key': 'sinema',   'label': 'Sinema'},
      {'key': 'bowling',  'label': 'Bowling & Oyun'},
      {'key': 'cocuk',    'label': 'Anne & Çocuk'},
      {'key': 'konser',   'label': 'Konser & Tiyatro'},
    ],
    'alisveris': [
      {'key': 'avm',      'label': 'AVM'},
      {'key': 'carsi',    'label': 'Çarşı & Pazar'},
      {'key': 'butik',    'label': 'Butik & Mağaza'},
    ],
    'doga'     : [
      {'key': 'park',     'label': 'Park & Bahçe'},
      {'key': 'doga',     'label': 'Doğa & Orman'},
      {'key': 'plaj',     'label': 'Plaj & Sahil'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _loadCatCityHistory();
    _prefs = widget.preferences;
    _cityCtrl.text     = widget.city;
    _districtCtrl.text = widget.district;
    if (widget.city.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  Future<void> _loadCatCityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() {
      _cityHistory = prefs.getStringList('city_history') ?? [];
    });
  }

  Future<void> _saveCatCityHistory(String city) async {
    if (city.isEmpty) return;
    _cityHistory.remove(city);
    _cityHistory.insert(0, city);
    if (_cityHistory.length > 8) _cityHistory = _cityHistory.sublist(0, 8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('city_history', _cityHistory);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _districtCtrl.dispose();
    super.dispose();
  }



  Future<void> _search() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse('${ApiConstants.optimizationBaseUrl}/suggest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'city'        : city,
          'district'    : _districtCtrl.text.trim(),
          'category'    : widget.category,
          'subcategory' : _subcategory,
          'radius_km'   : _radiusKm,
          'api_key'     : ApiConstants.googleApiKey,
          'max_results' : 10,
          'preferences' : _prefs.toJson(),
        }),
      ).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        setState(() {
          _summary = data['summary'] ?? '';
          _places  = (data['places'] as List).map((p) => PlaceItem.fromJson(p)).toList();
        });
      } else {
        setState(() => _error = data['error'] ?? 'Hata oluştu.');
      }
    } catch (e) {
      setState(() => _error = 'Bağlantı hatası: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);
    final subs   = _subcatMap[widget.category] ?? [];
    final catLabel = _catLabels[widget.category] ?? widget.category;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor:  surf,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        title: Text(catLabel,
            style: TextStyle(color: tp, fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Column(children: [
        // Şehir alanı
        Container(
          color: surf,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(children: [
            Row(children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _cityCtrl,
                  style: TextStyle(color: tp, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Şehir',
                    hintStyle: TextStyle(color: ts, fontSize: 12),
                    prefixIcon: Icon(Icons.location_city_outlined, color: ts, size: 17),
                    filled: true, fillColor: surf,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: const Color(0xFF6366F1), width: 1.5)),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _districtCtrl,
                  style: TextStyle(color: tp, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'İlçe (opsiyonel)',
                    hintStyle: TextStyle(color: ts, fontSize: 12),
                    filled: true, fillColor: surf,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: const Color(0xFF6366F1), width: 1.5)),
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search, size: 17),
                label: Text(_loading ? 'Aranıyor...' : 'Ara',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
        ),
        // Alt kategoriler
        if (subs.isNotEmpty)
          Container(
            color: surf, height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: subs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                if (i == 0) {
                  final sel = _subcategory.isEmpty;
                  return GestureDetector(
                    onTap: () => setState(() { _subcategory = ''; _places = []; }),
                    child: _subChipW('Tümü', sel, border, ts),
                  );
                }
                final sub = subs[i - 1];
                final sel = _subcategory == sub['key'];
                return GestureDetector(
                  onTap: () => setState(() { _subcategory = sub['key']!; _places = []; }),
                  child: _subChipW(sub['label']!, sel, border, ts),
                );
              },
            ),
          ),
        // Yarıçap
        Container(
          color: bg,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            Icon(Icons.my_location_rounded, size: 13, color: const Color(0xFF3D9CF5)),
            const SizedBox(width: 6),
            Text('Yarıçap:', style: TextStyle(fontSize: 12, color: ts)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF3D9CF5).withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3D9CF5).withOpacity(0.4)),
              ),
              child: Text(_radiusKm == 0 ? 'Tüm Şehir' : '$_radiusKm km',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3D9CF5))),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor:   const Color(0xFF3D9CF5),
                  inactiveTrackColor: const Color(0xFF3D9CF5).withOpacity(0.15),
                  thumbColor:         const Color(0xFF3D9CF5),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: _radiusKm.toDouble(), min: 0, max: 50, divisions: 50,
                  onChanged: (v) => setState(() => _radiusKm = v.toInt()),
                  onChangeEnd: (_) => _places = [],
                ),
              ),
            ),
          ]),
        ),
        // İçerik
        Expanded(
          child: _error != null
              ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _search,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
                    child: const Text('Tekrar Dene')),
              ])))
              : _places.isEmpty && !_loading
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search, size: 48, color: ts),
            const SizedBox(height: 12),
            Text('Şehir gir ve ara', style: TextStyle(color: ts)),
          ]))
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: _places.length,
            itemBuilder: (_, i) {
              final p = _places[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surf,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(children: [
                  const SizedBox(width: 4),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: TextStyle(color: tp,
                        fontWeight: FontWeight.w600, fontSize: 14)),
                    if (p.address.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(p.address, style: TextStyle(color: ts, fontSize: 11),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.star_rounded, size: 13, color: AppColors.warn),
                      const SizedBox(width: 3),
                      Text('${p.rating}', style: TextStyle(color: ts, fontSize: 12)),
                      if (p.openNow != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (p.openNow! ? AppColors.success : AppColors.danger).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(p.openNow! ? 'Açık' : 'Kapalı',
                              style: TextStyle(fontSize: 10,
                                  color: p.openNow! ? AppColors.success : AppColors.danger,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                    if (p.aiReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(p.aiReason, style: TextStyle(color: ts, fontSize: 12),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ])),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _subChipW(String label, bool sel, Color border, Color ts) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color:        sel ? const Color(0xFF6366F1).withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: sel ? const Color(0xFF6366F1) : border, width: sel ? 1.5 : 1),
      ),
      child: Text(label, style: TextStyle(
          fontSize: 12, color: sel ? const Color(0xFF6366F1) : ts,
          fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
    );
  }
}

// ── Tercihler Bottom Sheet ────────────────────────────────────────────────────

class _PrefsSheet extends StatefulWidget {
  final UserPreferences prefs;
  final void Function(UserPreferences) onSave;
  const _PrefsSheet({required this.prefs, required this.onSave});
  @override
  State<_PrefsSheet> createState() => _PrefsSheetState();
}

class _PrefsSheetState extends State<_PrefsSheet> {
  late UserPreferences _p;

  @override
  void initState() {
    super.initState();
    _p = UserPreferences.fromJson(widget.prefs.toJson());
  }

  @override
  Widget build(BuildContext context) {
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);

    return DraggableScrollableSheet(
      expand: false, initialChildSize: 0.7, maxChildSize: 0.9,
      builder: (_, ctrl) => Column(children: [
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Text('Tercihlerim',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: tp)),
        const SizedBox(height: 4),
        Text('Google Maps verisiyle eşleşen filtreler',
            style: TextStyle(fontSize: 12, color: ts)),
        const SizedBox(height: 12),

        Expanded(
          child: ListView(controller: ctrl,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _segRow('Yaş Grubu', [
                {'key': 'cocuk',    'label': '👶 Çocuk'},
                {'key': 'genc',     'label': '🧑 Genç'},
                {'key': 'yetiskin', 'label': '👨 Yetişkin'},
                {'key': 'yasli',    'label': '👴 Yaşlı'},
              ], _p.ageGroup, (v) => _p.ageGroup = v, tp, ts, border),

              _segRow('Bütçe', [
                {'key': 'ekonomik', 'label': '💰 Ekonomik'},
                {'key': 'orta',     'label': '💳 Orta'},
                {'key': 'luks',     'label': '💎 Lüks'},
              ], _p.budget, (v) => _p.budget = v, tp, ts, border),

              _segRow('Grup Tipi', [
                {'key': 'yalniz',  'label': '🧍 Yalnız'},
                {'key': 'cift',    'label': '👫 Çift'},
                {'key': 'aile',    'label': '👨‍👩‍👧 Aile'},
                {'key': 'arkadas', 'label': '👥 Arkadaş'},
              ], _p.groupType, (v) => _p.groupType = v, tp, ts, border),

              _segRow('Mekan Tipi', [
                {'key': 'acik',  'label': '☀️ Açık Alan'},
                {'key': 'kapali','label': '🏠 Kapalı Alan'},
                {'key': 'ikisi', 'label': '🔀 Fark Etmez'},
              ], _p.indoorOutdoor, (v) => _p.indoorOutdoor = v, tp, ts, border),

              Divider(height: 24, color: border),
              Text('Erişilebilirlik',
                  style: TextStyle(color: tp, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),

              _toggle('♿ Engelli Erişimi (tekerlekli sandalye)',
                  _p.wheelchair,    (v) => _p.wheelchair    = v, tp, ts),
              _toggle('👶 Çocuğa Uygun (bar/gece kulübü hariç)',
                  _p.childFriendly, (v) => _p.childFriendly = v, tp, ts),

              const SizedBox(height: 16),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () { widget.onSave(_p); Navigator.pop(context); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
                padding:   const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Tercihleri Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _segRow(String label, List<Map<String, String>> opts, String current,
      void Function(String) onChange, Color tp, Color ts, Color border) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(color: tp, fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: opts.map((o) {
          final sel = current == o['key'];
          return GestureDetector(
            onTap: () => setState(() => onChange(o['key']!)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color:        sel ? const Color(0xFF6366F1).withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: sel ? const Color(0xFF6366F1) : border, width: sel ? 1.5 : 1),
              ),
              child: Text(o['label']!,
                  style: TextStyle(
                    color:      sel ? const Color(0xFF6366F1) : ts,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                    fontSize:   13,
                  )),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _toggle(String label, bool value, void Function(bool) onChange,
      Color tp, Color ts) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title:       Text(label, style: TextStyle(color: tp, fontSize: 13)),
      value:       value,
      activeColor: const Color(0xFF6366F1),
      onChanged:   (v) => setState(() => onChange(v)),
      dense:       true,
    );
  }
}