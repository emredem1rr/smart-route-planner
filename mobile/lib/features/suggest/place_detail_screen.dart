import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';

class PlaceDetailScreen extends StatefulWidget {
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double rating;
  final List<String> types;
  final String? aiReason;

  const PlaceDetailScreen({
    super.key,
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.types,
    this.aiReason,
  });

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  final _storage    = StorageService();
  bool  _isFavorite = false;
  bool  _favLoading = false;

  // Yorumlar
  List<Map<String, dynamic>> _reviews   = [];
  double                     _avgRating = 0;
  bool                       _revLoading = true;

  // Yorum yazma
  int    _myRating  = 5;
  final  _commentCtrl = TextEditingController();
  bool   _submitting  = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
    _loadReviews();
  }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _checkFavorite() async {
    try {
      final token = await _storage.getToken();
      final resp  = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/places/favorites/${widget.placeId}/check'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(resp.body);
      if (mounted) setState(() => _isFavorite = data['is_favorite'] == true);
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    setState(() => _favLoading = true);
    try {
      final token = await _storage.getToken();
      if (_isFavorite) {
        await http.delete(
          Uri.parse('${ApiConstants.baseUrl}/places/favorites/${widget.placeId}'),
          headers: {'Authorization': 'Bearer $token'},
        );
        setState(() => _isFavorite = false);
      } else {
        await http.post(
          Uri.parse('${ApiConstants.baseUrl}/places/favorites'),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
          body: jsonEncode({
            'place_id' : widget.placeId,
            'name'     : widget.name,
            'address'  : widget.address,
            'latitude' : widget.latitude,
            'longitude': widget.longitude,
            'rating'   : widget.rating,
            'types'    : widget.types,
          }),
        );
        setState(() => _isFavorite = true);
      }
    } catch (_) {}
    setState(() => _favLoading = false);
  }

  Future<void> _loadReviews() async {
    setState(() => _revLoading = true);
    try {
      final resp = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/places/${Uri.encodeComponent(widget.placeId)}/reviews'),
      );
      final data = jsonDecode(resp.body);
      if (data['success'] == true && mounted) {
        setState(() {
          _reviews   = List<Map<String, dynamic>>.from(data['reviews']);
          _avgRating = (data['avg_rating'] ?? 0).toDouble();
        });
      }
    } catch (_) {}
    setState(() => _revLoading = false);
  }

  Future<void> _submitReview() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final token = await _storage.getToken();
      final resp  = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/places/reviews'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'place_id'  : widget.placeId,
          'place_name': widget.name,
          'rating'    : _myRating,
          'comment'   : _commentCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        _commentCtrl.clear();
        await _loadReviews();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:         const Text('Yorumun kaydedildi'),
            backgroundColor: AppColors.success,
            behavior:        SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    } catch (_) {}
    setState(() => _submitting = false);
  }

  Future<void> _openMaps() async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${widget.latitude},${widget.longitude}');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
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
      body: CustomScrollView(
        slivers: [
          // App bar + harita
          SliverAppBar(
            expandedHeight: 220,
            pinned:         true,
            backgroundColor: surf,
            foregroundColor: tp,
            actions: [
              _favLoading
                  ? const Padding(padding: EdgeInsets.all(12),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                icon: Icon(
                  _isFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: _isFavorite ? const Color(0xFF6366F1) : tp,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(widget.latitude, widget.longitude),
                  initialZoom:   15,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.mobile',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(widget.latitude, widget.longitude),
                      width: 40, height: 48,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.orange, shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: AppColors.orange.withOpacity(0.4),
                                blurRadius: 6)],
                          ),
                          child: const Icon(Icons.place_rounded, color: Colors.white, size: 18),
                        ),
                        Container(width: 2, height: 8, color: AppColors.orange),
                      ]),
                    ),
                  ]),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // Başlık + puan
                Row(children: [
                  Expanded(child: Text(widget.name,
                      style: TextStyle(color: tp, fontSize: 20,
                          fontWeight: FontWeight.w800))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color:        AppColors.warn.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: AppColors.warn, size: 16),
                      const SizedBox(width: 4),
                      Text(widget.rating.toStringAsFixed(1),
                          style: const TextStyle(color: AppColors.warn,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 6),

                // Adres
                if (widget.address.isNotEmpty) ...[
                  Row(children: [
                    Icon(Icons.location_on_outlined, size: 14, color: ts),
                    const SizedBox(width: 6),
                    Expanded(child: Text(widget.address,
                        style: TextStyle(color: ts, fontSize: 13))),
                  ]),
                  const SizedBox(height: 10),
                ],

                // AI öneri
                if (widget.aiReason != null && widget.aiReason!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:        AppColors.orange.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.orange.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.auto_awesome, color: AppColors.orange, size: 14),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.aiReason!,
                          style: TextStyle(color: tp, fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],

                // Yol tarifi butonu
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openMaps,
                    icon:  const Icon(Icons.directions_rounded, size: 18),
                    label: const Text('Yol Tarifi Al'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      padding:   const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Uygulama içi yorumlar başlığı
                Row(children: [
                  Text('Kullanıcı Yorumları',
                      style: TextStyle(color: tp, fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  if (_reviews.isNotEmpty) ...[
                    const Icon(Icons.star_rounded, color: AppColors.warn, size: 14),
                    const SizedBox(width: 3),
                    Text(_avgRating.toStringAsFixed(1),
                        style: const TextStyle(color: AppColors.warn,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Text('(${_reviews.length})',
                        style: TextStyle(color: ts, fontSize: 12)),
                  ],
                ]),
                const SizedBox(height: 12),

                // Yorum yazma kutusu
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surf,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Yorum Yaz', style: TextStyle(color: tp,
                            fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        // Yıldız seçici
                        Row(children: List.generate(5, (i) => GestureDetector(
                          onTap: () => setState(() => _myRating = i + 1),
                          child: Icon(
                            i < _myRating ? Icons.star_rounded : Icons.star_border_rounded,
                            color: AppColors.warn, size: 28,
                          ),
                        ))),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _commentCtrl,
                          maxLines:   3,
                          maxLength:  300,
                          style: TextStyle(color: tp, fontSize: 13),
                          decoration: InputDecoration(
                            hintText:       'Deneyimini paylaş...',
                            hintStyle:      TextStyle(color: ts, fontSize: 12),
                            filled:         true,
                            fillColor:      bg,
                            counterStyle:   TextStyle(color: ts, fontSize: 11),
                            contentPadding: const EdgeInsets.all(12),
                            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submitReview,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _submitting
                                ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Gönder', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ]),
                ),
                const SizedBox(height: 16),

                // Yorumlar listesi
                if (_revLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(color: AppColors.orange)))
                else if (_reviews.isEmpty)
                  Center(child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Henüz yorum yok. İlk yorumu sen yaz!',
                        style: TextStyle(color: ts, fontSize: 13)),
                  ))
                else
                  ..._reviews.map((r) => _reviewCard(r, surf, border, tp, ts)),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> r, Color surf, Color border,
      Color tp, Color ts) {
    final stars = (r['rating'] as int?) ?? 0;
    final date  = (r['created_at'] as String?)?.substring(0, 10) ?? '';
    return Container(
      margin:  const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color:        AppColors.orange.withOpacity(0.12),
              shape:        BoxShape.circle,
            ),
            child: Center(child: Text(
              (r['user_name'] as String? ?? '?').substring(0, 1).toUpperCase(),
              style: const TextStyle(color: AppColors.orange,
                  fontWeight: FontWeight.w700),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r['user_name'] as String? ?? 'Kullanıcı',
                    style: TextStyle(color: tp, fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(date, style: TextStyle(color: ts, fontSize: 11)),
              ])),
          Row(children: List.generate(5, (i) => Icon(
            i < stars ? Icons.star_rounded : Icons.star_border_rounded,
            color: AppColors.warn, size: 14,
          ))),
        ]),
        const SizedBox(height: 8),
        Text(r['comment'] as String? ?? '',
            style: TextStyle(color: tp, fontSize: 13, height: 1.5)),
      ]),
    );
  }
}