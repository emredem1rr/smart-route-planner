import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../core/theme/app_theme.dart';

class MapPickerResult {
  final double latitude, longitude;
  final String address;
  const MapPickerResult({
    required this.latitude,
    required this.longitude,
    required this.address,
  });
}

class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  const MapPickerScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _mapCtrl    = MapController();
  final _searchCtrl = TextEditingController();

  LatLng?  _pin;
  String   _address   = '';
  bool     _resolving = false;
  bool     _searching = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _pin = LatLng(widget.initialLat!, widget.initialLng!);
      _reverseGeocode(_pin!);
    } else {
      _goCurrentLocation();
    }
  }

  @override
  void dispose() {
    _mapCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _goCurrentLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final ll  = LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = ll);
      _mapCtrl.move(ll, 15);
      _reverseGeocode(ll);
    } catch (_) {
      // İstanbul merkezi
      final ll = const LatLng(41.0082, 28.9784);
      setState(() => _pin = ll);
      _mapCtrl.move(ll, 12);
    }
  }

  Future<void> _reverseGeocode(LatLng ll) async {
    setState(() { _resolving = true; _address = 'Adres alınıyor...'; });
    try {
      final resp = await http.get(Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
            '?format=json&lat=${ll.latitude}&lon=${ll.longitude}&accept-language=tr',
      ), headers: {'User-Agent': 'SmartRoutePlanner/1.0'});
      final data = jsonDecode(resp.body);
      setState(() => _address = data['display_name'] ?? 'Bilinmeyen adres');
    } catch (_) {
      setState(() => _address = '${ll.latitude.toStringAsFixed(5)}, ${ll.longitude.toStringAsFixed(5)}');
    } finally {
      setState(() => _resolving = false);
    }
  }

  Future<void> _searchAddress(String query) async {
    if (query.length < 3) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    try {
      final resp = await http.get(Uri.parse(
        'https://nominatim.openstreetmap.org/search'
            '?format=json&q=${Uri.encodeComponent(query)}&limit=5&accept-language=tr',
      ), headers: {'User-Agent': 'SmartRoutePlanner/1.0'});
      final List results = jsonDecode(resp.body);
      setState(() => _searchResults = results.cast<Map<String, dynamic>>());
    } catch (_) {
      setState(() => _searchResults = []);
    } finally {
      setState(() => _searching = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> r) {
    final ll = LatLng(double.parse(r['lat']), double.parse(r['lon']));
    setState(() {
      _pin = ll;
      _address = r['display_name'] ?? '';
      _searchCtrl.text = _address;
      _searchResults = [];
    });
    _mapCtrl.move(ll, 15);
  }

  void _onMapTap(_, LatLng ll) {
    setState(() => _pin = ll);
    _reverseGeocode(ll);
  }

  void _confirm() {
    if (_pin == null) return;
    Navigator.pop(context, MapPickerResult(
      latitude:  _pin!.latitude,
      longitude: _pin!.longitude,
      address:   _address,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor:  surf,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight:    64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: AppColors.surfaceHigh(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border)),
              child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
            ),
          ),
        ),
        title: Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.map_rounded, color: Colors.white, size: 15)),
          const SizedBox(width: 10),
          Text('Konum Seç', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
        actions: [
          TextButton(
            onPressed: _pin == null ? null : _confirm,
            child: Text(
              'Seç',
              style: TextStyle(
                color:      _pin == null ? ts : AppColors.orange,
                fontWeight: FontWeight.w700,
                fontSize:   15,
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // Arama kutusu
        Container(
          color: surf,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(children: [
            TextField(
              controller: _searchCtrl,
              style: TextStyle(color: tp, fontSize: 13),
              onChanged: _searchAddress,
              decoration: InputDecoration(
                hintText:   'Adres ara...',
                hintStyle:  TextStyle(color: ts, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18, color: const Color(0xFF6366F1)),
                suffixIcon: _searching
                    ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF6366F1))))
                    : null,
                filled:         true,
                fillColor:      bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: const Color(0xFF6366F1), width: 1.5)),
              ),
            ),
            // Arama sonuçları
            if (_searchResults.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color:        surf,
                  borderRadius: BorderRadius.circular(10),
                  border:       Border.all(color: border),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                      blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: ListView.separated(
                  shrinkWrap:      true,
                  itemCount:       _searchResults.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: border),
                  itemBuilder: (_, i) {
                    final r = _searchResults[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on, color: const Color(0xFF6366F1), size: 18),
                      title: Text(r['display_name'] ?? '',
                          style: TextStyle(color: tp, fontSize: 12),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _selectSearchResult(r),
                    );
                  },
                ),
              ),
          ]),
        ),

        // Harita
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: _pin ?? const LatLng(41.0082, 28.9784),
                initialZoom:   14,
                onTap:         _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.mobile',
                ),
                if (_pin != null)
                  MarkerLayer(markers: [
                    Marker(
                      point:  _pin!,
                      width:  56,
                      height: 56,
                      child:  const Icon(Icons.location_pin,
                          color: const Color(0xFF6366F1), size: 48),
                    ),
                  ]),
              ],
            ),

            // Konum al butonu
            Positioned(
              right: 16, bottom: 16,
              child: FloatingActionButton.small(
                heroTag:         'myloc',
                onPressed:       _goCurrentLocation,
                backgroundColor: surf,
                child: Icon(Icons.my_location, color: const Color(0xFF6366F1), size: 20),
              ),
            ),
          ]),
        ),

        // Alt — seçili adres
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          decoration: BoxDecoration(
            color: surf,
            border: Border(top: BorderSide(color: border)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
                blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.location_on, color: const Color(0xFF6366F1), size: 16),
              const SizedBox(width: 6),
              Text('Seçili Konum', style: TextStyle(
                  color: ts, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            _resolving
                ? Row(children: [
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF6366F1))),
              const SizedBox(width: 8),
              Text('Adres alınıyor...', style: TextStyle(color: ts, fontSize: 13)),
            ])
                : Text(
              _pin == null ? 'Haritaya tıklayarak konum seç' : _address,
              style: TextStyle(
                color:      _pin == null ? ts : tp,
                fontSize:   13,
                fontWeight: _pin == null ? FontWeight.w400 : FontWeight.w600,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pin == null ? null : _confirm,
                icon:  const Icon(Icons.check_rounded, size: 18),
                label: const Text('Bu Konumu Kullan',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.border(context),
                  padding:   const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}