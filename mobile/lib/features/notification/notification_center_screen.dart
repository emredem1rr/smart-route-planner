import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../core/theme/app_theme.dart';
import '../../core/services/notification_service.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});
  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<_NotifItem> _notifs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList('notif_history') ?? [];
    setState(() {
      _notifs = raw
          .map((s) => _NotifItem.fromJson(jsonDecode(s)))
          .toList()
          .reversed.toList();
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notif_history');
    setState(() => _notifs = []);
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
        title: Text('Bildirim Merkezi',
            style: TextStyle(color: tp, fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (_notifs.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Temizle',
                  style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _notifs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_none_rounded, size: 56, color: ts),
        const SizedBox(height: 12),
        Text('Bildirim yok', style: TextStyle(color: ts, fontSize: 15)),
      ]))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _notifs.length,
        itemBuilder: (_, i) {
          final n = _notifs[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color:        _typeColor(n.type).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_typeIcon(n.type),
                    color: _typeColor(n.type), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title, style: TextStyle(color: tp,
                        fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(n.body, style: TextStyle(color: ts, fontSize: 12),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(_timeAgo(n.time),
                        style: TextStyle(color: ts, fontSize: 11)),
                  ])),
            ]),
          );
        },
      ),
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'location': return AppColors.info;
      case 'reminder': return AppColors.warn;
      case 'done':     return AppColors.success;
      default:         return AppColors.orange;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'location': return Icons.location_on_rounded;
      case 'reminder': return Icons.alarm_rounded;
      case 'done':     return Icons.check_circle_rounded;
      default:         return Icons.notifications_rounded;
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1)  return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours   < 24) return '${diff.inHours} sa önce';
    return '${diff.inDays} gün önce';
  }
}

class _NotifItem {
  final String   title, body, type;
  final DateTime time;
  _NotifItem({required this.title, required this.body,
    required this.type,  required this.time});

  factory _NotifItem.fromJson(Map<String, dynamic> j) => _NotifItem(
    title: j['title'] as String,
    body:  j['body']  as String,
    type:  j['type']  as String? ?? 'general',
    time:  DateTime.parse(j['time'] as String),
  );

  Map<String, dynamic> toJson() => {
    'title': title, 'body': body,
    'type':  type,  'time': time.toIso8601String(),
  };
}