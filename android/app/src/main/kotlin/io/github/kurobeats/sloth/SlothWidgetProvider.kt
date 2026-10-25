package io.github.kurobeats.sloth

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * "Due Today" widget: the same short list the app opens on, painted with the
 * colours of the scheme the app is using right now. Tapping a row opens that
 * task, tapping the header opens the app.
 *
 * Data comes from lib/home_widget_sync.dart, which writes it after every
 * refresh and every task change.
 */
class SlothWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context, widgetData))
        }
    }

    private fun buildViews(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.sloth_widget_today)
        val headerText = colour(data, "headerText", Color.WHITE)
        val textColour = colour(data, "text", Color.WHITE)
        val mutedColour = colour(data, "muted", Color.GRAY)
        val accentColour = colour(data, "accent", Color.WHITE)

        // Rounded corners come from a per-scheme drawable: RemoteViews cannot
        // tint a shape before Android 12.
        // shortcut: a new scheme needs a matching sloth_widget_card_*.xml.
        val scheme = data.getString("scheme", null)
        views.setInt(R.id.widget_card, "setBackgroundResource", cardDrawable(scheme))
        views.setInt(R.id.widget_header, "setBackgroundResource", headerDrawable(scheme))
        views.setTextColor(R.id.widget_title, headerText)
        views.setTextColor(R.id.widget_count, headerText)
        views.setTextColor(R.id.widget_empty, mutedColour)

        val rows = parseRows(data.getString("rows", null))
        val count = rows.size
        views.setTextViewText(R.id.widget_count, if (count == 0) "" else count.toString())
        views.setViewVisibility(R.id.widget_empty, if (rows.isEmpty()) View.VISIBLE else View.GONE)

        // Open the app from the header.
        views.setOnClickPendingIntent(
            R.id.widget_header,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )

        views.removeAllViews(R.id.widget_list)
        rows.forEach { row ->
            val item = RemoteViews(context.packageName, R.layout.sloth_widget_row)
            item.setTextViewText(R.id.row_title, row.title)
            item.setTextColor(R.id.row_title, textColour)
            item.setTextViewText(R.id.row_tags, row.tags)
            item.setTextColor(R.id.row_tags, mutedColour)
            item.setViewVisibility(
                R.id.row_tags,
                if (row.tags.isEmpty()) View.GONE else View.VISIBLE,
            )
            item.setTextViewText(R.id.row_meta, row.meta)
            item.setTextColor(R.id.row_meta, if (row.overdue) accentColour else mutedColour)
            item.setOnClickPendingIntent(
                R.id.row_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("sloth://task/${row.id}"),
                ),
            )
            views.addView(R.id.widget_list, item)
        }
        return views
    }

    /// home_widget stores ints as longs, so read either.
    private fun colour(data: SharedPreferences, key: String, fallback: Int): Int =
        try {
            data.getInt(key, fallback)
        } catch (_: ClassCastException) {
            data.getLong(key, fallback.toLong()).toInt()
        }

    private fun cardDrawable(scheme: String?): Int = when (scheme) {
        "panda" -> R.drawable.sloth_widget_card_panda
        "catppuccin-mocha" -> R.drawable.sloth_widget_card_mocha
        "gruvbox-light" -> R.drawable.sloth_widget_card_gruvbox
        "everforest-light" -> R.drawable.sloth_widget_card_everforest
        "patina-light" -> R.drawable.sloth_widget_card_patina
        else -> R.drawable.sloth_widget_card_oceanic
    }

    private fun headerDrawable(scheme: String?): Int = when (scheme) {
        "panda" -> R.drawable.sloth_widget_header_panda
        "catppuccin-mocha" -> R.drawable.sloth_widget_header_mocha
        "gruvbox-light" -> R.drawable.sloth_widget_header_gruvbox
        "everforest-light" -> R.drawable.sloth_widget_header_everforest
        "patina-light" -> R.drawable.sloth_widget_header_patina
        else -> R.drawable.sloth_widget_header_oceanic
    }

    private data class Row(
        val id: Int,
        val title: String,
        val meta: String,
        val tags: String,
        val overdue: Boolean,
    )

    private fun parseRows(raw: String?): List<Row> {
        if (raw.isNullOrEmpty()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val json = array.getJSONObject(index)
                Row(
                    id = json.optInt("id"),
                    title = json.optString("title"),
                    meta = json.optString("meta"),
                    tags = json.optString("tags"),
                    overdue = json.optBoolean("overdue"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
