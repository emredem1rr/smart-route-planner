import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants/api_constants.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';

class RouteHistoryScreen extends StatefulWidget {
  const RouteHistoryScreen({super.key});
  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  final _storage = StorageService();
  bool _loading  = true;
  List<Map<String, dynamic>> _routes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _storage.getToken();
      final resp  = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/routes/history'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        setState(() => _routes = List<Map<String, dynamic>>.from(data['routes']));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  String _algoLabel(String algo) {
    switch (algo) {
      case 'lin_kernighan':        return 'LKH';
      case 'ant_colony':           return 'ACS';
      case 'simulated_annealing':  return 'SA';
      case 'tabu_search':          return 'Tabu';
      case 'genetic':              return 'Genetik';
      default: return algo;
    }
  }

  Color _algoColor(String algo) {
    switch (algo) {
      case 'lin_kernighan':       return const Color(0xFF4CAF50);
      case 'ant_colony':          return const Color(0xFFE91E63);
      case 'simulated_annealing': return const Color(0xFFFF9800);
      case 'tabu_search':         return const Color(0xFF9C27B0);
      case 'genetic':             return const Color(0xFF2196F3);
      default: return AppColors.orange;
    }
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
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.history_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('Rota Geçmişi', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _routes.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.route_outlined, size: 56, color: ts),
        const SizedBox(height: 12),
        Text('Henüz rota geçmişi yok',
            style: TextStyle(color: ts, fontSize: 15)),
        const SizedBox(height: 6),
        Text('Rota optimize ettikçe burada görünür',
            style: TextStyle(color: ts, fontSize: 12)),
      ]))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _routes.length,
        itemBuilder: (_, i) {
          final r         = _routes[i];
          final algo      = r['algorithm_used'] ?? '';
          final color     = _algoColor(algo);
          final date      = r['task_date']?.toString().substring(0, 10) ?? '';
          final dist      = (r['total_distance']    ?? 0.0).toDouble();
          final time      = (r['total_travel_time'] ?? 0.0).toDouble();
          final taskNames = r['task_names']?.toString() ?? '';
          final count     = r['task_count'] ?? 0;

          return Container(
            margin:  const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        surf,
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: border),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_algoLabel(algo),
                      style: TextStyle(color: color,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text(date,
                    style: TextStyle(color: ts, fontSize: 12)),
                const Spacer(),
                Text('$count görev',
                    style: TextStyle(color: ts, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _stat(Icons.route_outlined,
                    '${dist.toStringAsFixed(1)} km', ts),
                const SizedBox(width: 16),
                _stat(Icons.timer_outlined,
                    '${time.toStringAsFixed(0)} dk', ts),
              ]),
              if (taskNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(taskNames,
                    style: TextStyle(color: ts, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _stat(IconData icon, String label, Color ts) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: ts),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: ts, fontSize: 12)),
    ]);
  }
}