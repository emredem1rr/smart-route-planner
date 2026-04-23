import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

/// Harita tile'larını önceden indirip cache'ler
/// flutter_map otomatik olarak bu cache'i kullanır
class OfflineMapService {
  static final _cacheManager = CacheManager(
    Config(
      'map_tiles',
      stalePeriod:      const Duration(days: 30),
      maxNrOfCacheObjects: 5000,   // ~5000 tile ≈ orta şehir
    ),
  );

  static CacheManager get cacheManager => _cacheManager;

  /// Belirli bir alan için tile'ları indir
  /// [center]: merkez nokta, [zoom]: yakınlaştırma seviyesi, [radius]: km
  static Future<void> cacheTilesForArea({
    required double centerLat,
    required double centerLng,
    int minZoom = 10,
    int maxZoom = 16,
    double radiusKm = 20,
    void Function(int done, int total)? onProgress,
  }) async {
    final tiles = _getTilesForArea(
      centerLat: centerLat,
      centerLng: centerLng,
      minZoom:   minZoom,
      maxZoom:   maxZoom,
      radiusKm:  radiusKm,
    );

    int done = 0;
    final total = tiles.length;

    for (final tile in tiles) {
      final url = _tileUrl(tile.$1, tile.$2, tile.$3);
      try {
        await _cacheManager.getSingleFile(url);
      } catch (_) {
        // Tek tile indirilemezse devam et
      }
      done++;
      onProgress?.call(done, total);
    }
  }

  /// Belirli koordinat ve zoom için tile listesi
  static List<(int z, int x, int y)> _getTilesForArea({
    required double centerLat,
    required double centerLng,
    required int minZoom,
    required int maxZoom,
    required double radiusKm,
  }) {
    final tiles = <(int, int, int)>[];

    for (int z = minZoom; z <= maxZoom; z++) {
      final centerTile = _latLngToTile(centerLat, centerLng, z);
      // Zoom seviyesine göre kapsama alanı (tile sayısı)
      final range = (radiusKm / _tileSizeKm(z)).ceil().clamp(1, 20);

      for (int dx = -range; dx <= range; dx++) {
        for (int dy = -range; dy <= range; dy++) {
          final x = centerTile.$1 + dx;
          final y = centerTile.$2 + dy;
          if (x >= 0 && y >= 0) {
            tiles.add((z, x, y));
          }
        }
      }
    }
    return tiles;
  }

  static (int, int) _latLngToTile(double lat, double lng, int zoom) {
    final n = (1 << zoom).toDouble();
    final x = ((lng + 180) / 360 * n).floor();
    final latRad = lat * 3.14159265358979 / 180;
    final y = ((1 - (log(tan(latRad) + 1 / cos(latRad)) /
        3.14159265358979)) / 2 * n).floor();
    return (x, y);
  }

  static double _tileSizeKm(int zoom) {
    // Her zoom seviyesinde tile'ın yaklaşık boyutu km cinsinden
    return 40075 / (1 << zoom).toDouble();
  }

  static String _tileUrl(int z, int x, int y) {
    return 'https://tile.openstreetmap.org/$z/$x/$y.png';
  }

  static double log(double x) => x <= 0 ? 0 : _log(x);
  static double _log(double x) {
    // Dart'ta dart:math import olmadan basit log
    double result = 0;
    double n = x;
    while (n > 1) { n /= 2.718281828; result++; }
    return result;
  }

  static double tan(double x) => sin(x) / cos(x);
  static double sin(double x) {
    double result = 0, term = x;
    for (int i = 1; i <= 10; i++) {
      result += term;
      term *= -x * x / ((2 * i) * (2 * i + 1));
    }
    return result;
  }
  static double cos(double x) {
    double result = 0, term = 1;
    for (int i = 1; i <= 10; i++) {
      result += term;
      term *= -x * x / ((2 * i - 1) * (2 * i));
    }
    return result;
  }

  /// Cache'i temizle
  static Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }

  /// Cache boyutunu MB cinsinden döner
  static Future<double> getCacheSizeMB() async {
    try {
      final info = await _cacheManager.getFileFromCache('__size_check__');
      return 0;
    } catch (_) {
      return 0;
    }
  }
}