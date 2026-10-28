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
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * "Due Today" widget: the same short list the app opens on, painted with the
 * colours of the scheme the app is using right now. Tapping a row opens that
 * task, tapping the header opens the app.
 *
 * Data comes from lib/home_widget_sync.dart, which writes the week of deadlines
 * after every refresh and every task change. Which of those rows are due, and
 * what they are labelled, is decided here: Android redraws the widget on its
 * own updatePeriodMillis tick, so a task that falls due at midnight shows up
 * without the app being opened.
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
        // The plus pill wears the card colour, so it takes the colour the card's
        // own rows use - the pairing Google Calendar gets from colorPrimary and
        // colorOnPrimary.
        views.setInt(R.id.widget_add_pill, "setBackgroundResource", cardDrawable(scheme))
        views.setInt(R.id.widget_add_icon, "setColorFilter", textColour)

        val now = System.currentTimeMillis()
        // The snapshot reaches days ahead; the clock is what makes a row
        // "due today". Five rows is all the card shows.
        val rows = parseRows(data.getString("rows", null))
            .filter { it.due < endOfToday(now) }
            .sortedBy { it.due }
            .take(5)
        val count = rows.size
        views.setTextViewText(R.id.widget_count, if (count == 0) "" else count.toString())
        views.setViewVisibility(R.id.widget_empty, if (rows.isEmpty()) View.VISIBLE else View.GONE)

        // Open the app from the header.
        views.setOnClickPendingIntent(
            R.id.widget_header,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )

        // The plus opens the add-a-task bar: the app focuses it on `sloth://new`.
        views.setOnClickPendingIntent(
            R.id.widget_add,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("sloth://new"),
            ),
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
            item.setTextViewText(R.id.row_meta, dueLabel(row.due, now))
            item.setTextColor(
                R.id.row_meta,
                if (row.due < startOfDay(now)) accentColour else mutedColour,
            )
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
        val tags: String,
        val due: Long,
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
                    tags = json.optString("tags"),
                    due = json.optLong("due"),
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /// Vikunja's wording for the due date, the subset of `TodoFormat.dueLabel`
    /// that survives the "due by today" filter: Today, Yesterday, then a date.
    /// Only rows the app pushed can be dated here, and the app may be closed for
    /// days, so the day has to be read on this side.
    private fun dueLabel(due: Long, now: Long): String = when (dayNumber(due) - dayNumber(now)) {
        0L -> "Today"
        -1L -> "Yesterday"
        else -> {
            val pattern = if (yearOf(due) == yearOf(now)) "EEE d MMM" else "EEE d MMM y"
            SimpleDateFormat(pattern, Locale.getDefault()).format(Date(due))
        }
    }

    private fun calendarOf(ms: Long): Calendar =
        Calendar.getInstance().apply { timeInMillis = ms }

    /// A day ordinal from the local calendar date. Subtracting local midnights
    /// would be off by an hour on a DST day, and by a whole day across one.
    private fun dayNumber(ms: Long): Long {
        val c = calendarOf(ms)
        return c.get(Calendar.YEAR) * 372L +
            c.get(Calendar.MONTH) * 31L +
            c.get(Calendar.DAY_OF_MONTH)
    }

    private fun yearOf(ms: Long): Int = calendarOf(ms).get(Calendar.YEAR)

    private fun startOfDay(ms: Long): Long = calendarOf(ms).apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /// Midnight of tomorrow, exclusive: a task due at 23:59 today is still today.
    private fun endOfToday(ms: Long): Long = calendarOf(startOfDay(ms)).apply {
        add(Calendar.DAY_OF_MONTH, 1)
    }.timeInMillis
}
