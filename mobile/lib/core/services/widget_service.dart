import 'package:home_widget/home_widget.dart';
import '../models/task_model.dart';

class WidgetService {
  static const String _appGroupId   = 'com.example.mobile';
  static const String _widgetName   = 'SmartRouteWidget';

  /// Bugünün görevlerini widget'a yaz
  static Future<void> updateWidget(List<TaskModel> tasks) async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);

      final pending = tasks.where((t) => t.status == 'pending').toList();
      final done    = tasks.where((t) => t.status == 'done').length;
      final total   = tasks.length;

      // Widget'a veri yaz
      await HomeWidget.saveWidgetData<int>('task_total',   total);
      await HomeWidget.saveWidgetData<int>('task_done',    done);
      await HomeWidget.saveWidgetData<int>('task_pending', pending.length);

      // İlk 3 görevi yaz
      for (int i = 0; i < 3; i++) {
        if (i < pending.length) {
          final t = pending[i];
          await HomeWidget.saveWidgetData<String>('task_${i}_name',    t.name);
          await HomeWidget.saveWidgetData<String>('task_${i}_time',
              t.earliestStart > 0 ? _timeStr(t.earliestStart) : '');
          await HomeWidget.saveWidgetData<int>('task_${i}_priority', t.priority);
        } else {
          await HomeWidget.saveWidgetData<String>('task_${i}_name',    '');
          await HomeWidget.saveWidgetData<String>('task_${i}_time',    '');
          await HomeWidget.saveWidgetData<int>('task_${i}_priority',    0);
        }
      }

      // Widget'ı güncelle
      await HomeWidget.updateWidget(
        androidName: _widgetName,
      );
    } catch (e) {
      print('[WidgetService] Hata: $e');
    }
  }

  static String _timeStr(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }
}