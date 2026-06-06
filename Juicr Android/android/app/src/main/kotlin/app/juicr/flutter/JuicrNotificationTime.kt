package app.juicr.flutter

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

object JuicrNotificationTime {
    fun todayStamp(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Calendar.getInstance().time)
    }
}
