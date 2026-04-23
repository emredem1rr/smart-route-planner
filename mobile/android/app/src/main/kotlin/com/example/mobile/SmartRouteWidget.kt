package com.example.mobile

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class SmartRouteWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        val views = RemoteViews(context.packageName, R.layout.smart_route_widget)

        val total   = widgetData.getInt("task_total",   0)
        val done    = widgetData.getInt("task_done",    0)
        val pending = widgetData.getInt("task_pending", 0)

        views.setTextViewText(R.id.widget_stats, "$done/$total tamamlandı")

        // Görev 1
        val name0 = widgetData.getString("task_0_name", "") ?: ""
        val time0 = widgetData.getString("task_0_time", "") ?: ""
        views.setTextViewText(R.id.task_0_name, name0)
        views.setTextViewText(R.id.task_0_time, time0)

        // Görev 2
        val name1 = widgetData.getString("task_1_name", "") ?: ""
        val time1 = widgetData.getString("task_1_time", "") ?: ""
        views.setTextViewText(R.id.task_1_name, name1)
        views.setTextViewText(R.id.task_1_time, time1)

        // Görev 3
        val name2 = widgetData.getString("task_2_name", "") ?: ""
        val time2 = widgetData.getString("task_2_time", "") ?: ""
        views.setTextViewText(R.id.task_2_name, name2)
        views.setTextViewText(R.id.task_2_time, time2)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}