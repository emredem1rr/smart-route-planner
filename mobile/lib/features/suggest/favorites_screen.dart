import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import 'place_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _storage = StorageService();
  bool _loading = true;
  List<Map<String, dynamic>> _places = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _storage.getToken();
      final resp = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/places/favorites'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(resp.body);

      if (data['success'] == true && mounted) {
        setState(() =>
        _places = List<Map<String, dynamic>>.from(data['places']));
      }
    } catch (_) {}

    setState(() => _loading = false);
  }

  Future<void> _remove(String placeId) async {
    try {
      final token = await _storage.getToken();
      await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/places/favorites/$placeId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      setState(() =>
          _places.removeWhere((p) => p['place_id'] == placeId));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.bg(context);
    final surf = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp = AppColors.textPrimary(context);
    final ts = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,

      // ✅ APPBAR
      appBar: AppBar(
        backgroundColor: surf,
        elevation: 0,
        surfaceTintColor: Colors.transparent,

        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
          ),
        ),

        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bookmark_rounded,
                  color: Colors.white, size: 15),
            ),
            const SizedBox(width: 10),
            Text(
              'Favori Mekanlar',
              style: TextStyle(
                color: tp,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: ts),
            onPressed: _load,
          ),
        ],

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),

      // ✅ BODY BURAYA TAŞINDI
      body: _loading
          ? Center(
        child: CircularProgressIndicator(
          color: AppColors.orange,
        ),
      )
          : _places.isEmpty
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded,
                size: 56, color: ts),
            const SizedBox(height: 12),
            Text('Favori mekan yok',
                style: TextStyle(color: ts, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              'Keşfet sekmesinden mekan ekleyebilirsin',
              style: TextStyle(color: ts, fontSize: 12),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _places.length,
        itemBuilder: (_, i) {
          final p = _places[i];
          final lat = (p['latitude'] as num).toDouble();
          final lng = (p['longitude'] as num).toDouble();
          final rat =
          (p['rating'] as num? ?? 0).toDouble();

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: ListTile(
              contentPadding:
              const EdgeInsets.fromLTRB(14, 8, 8, 8),

              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                  AppColors.orange.withOpacity(0.1),
                  borderRadius:
                  BorderRadius.circular(12),
                ),
                child: const Icon(Icons.place_rounded,
                    color: AppColors.orange, size: 22),
              ),

              title: Text(
                p['name'] as String? ?? '',
                style: TextStyle(
                  color: tp,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),

              subtitle: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  if ((p['address'] as String? ?? '')
                      .isNotEmpty)
                    Text(
                      p['address'] as String,
                      style: TextStyle(
                          color: ts, fontSize: 12),
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                    ),
                  if (rat > 0)
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.warn,
                            size: 12),
                        const SizedBox(width: 3),
                        Text(
                          rat.toStringAsFixed(1),
                          style: TextStyle(
                              color: ts,
                              fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),

              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.open_in_new_rounded,
                      color: AppColors.orange,
                      size: 20,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaceDetailScreen(
                              placeId:
                              p['place_id'] as String,
                              name:
                              p['name'] as String? ??
                                  '',
                              address:
                              p['address'] as String? ??
                                  '',
                              latitude: lat,
                              longitude: lng,
                              rating: rat,
                              types: [],
                            ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.bookmark_remove_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    onPressed: () =>
                        _remove(p['place_id']
                        as String),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}