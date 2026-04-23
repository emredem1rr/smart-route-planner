import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingService {
  static const String _googleApiKey = 'AIzaSyBQ-u9Y2fKKuTCDBj3Mc-9c3v16N0snpf8';
  static const String _googleBase   =
      'https://maps.googleapis.com/maps/api/geocode/json';

  Future<Map<String, dynamic>?> addressToCoordinates(String address) async {
    // 1. Google ile dene (en iyi sonuç)
    var result = await _searchGoogle(address);
    if (result != null) return result;

    // 2. Nominatim ile dene
    result = await _searchNominatim(address);
    if (result != null) return result;

    // 3. Photon ile dene
    result = await _searchPhoton(address);
    return result;
  }

  Future<Map<String, dynamic>?> _searchGoogle(String address) async {
    try {
      final url = Uri.parse(_googleBase).replace(queryParameters: {
        'address':  address,
        'key':      _googleApiKey,
        'region':   'tr',
        'language': 'tr',
      });

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      final json    = jsonDecode(response.body);
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final location  = results[0]['geometry']['location'];
      final formatted = results[0]['formatted_address'] as String;

      return {
        'latitude':          (location['lat'] as num).toDouble(),
        'longitude':         (location['lng'] as num).toDouble(),
        'formatted_address': formatted,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _searchNominatim(String address) async {
    try {
      final encoded  = Uri.encodeComponent(address);
      final url      = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?q=$encoded&format=json&limit=1&addressdetails=1&countrycodes=tr',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'SmartRoutePlanner/1.0',
        'Accept':     'application/json',
      }).timeout(const Duration(seconds: 10));

      final list = jsonDecode(response.body) as List;
      if (list.isEmpty) return null;

      return {
        'latitude':          double.parse(list[0]['lat'] as String),
        'longitude':         double.parse(list[0]['lon'] as String),
        'formatted_address': list[0]['display_name'] as String,
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _searchPhoton(String address) async {
    try {
      final encoded  = Uri.encodeComponent(address);
      final url      = Uri.parse(
        'https://photon.komoot.io/api/?q=$encoded&limit=1&lang=tr',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'SmartRoutePlanner/1.0',
      }).timeout(const Duration(seconds: 10));

      final json     = jsonDecode(response.body);
      final features = json['features'] as List?;
      if (features == null || features.isEmpty) return null;

      final coords = features[0]['geometry']['coordinates'] as List;
      final props  = features[0]['properties'] as Map<String, dynamic>;
      final name   = props['name'] as String? ?? address;

      return {
        'latitude':          (coords[1] as num).toDouble(),
        'longitude':         (coords[0] as num).toDouble(),
        'formatted_address': name,
      };
    } catch (_) {
      return null;
    }
  }
}