package hmg.phone.profiles;

import android.util.Log;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.LinkedList;
import java.util.List;
import java.util.Locale;

/**
 * Thread-safe in-app diagnostic log buffer.
 * Captures in-vehicle runtime events, IPC invocations, and hardware safety states.
 */
public class AppLogger {
    private static final int MAX_ENTRIES = 250;
    private static final LinkedList<String> sLogBuffer = new LinkedList<String>();
    private static final SimpleDateFormat sDateFormat = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US);

    public static synchronized void i(String tag, String message) {
        Log.i(tag, message);
        append("INFO", tag, message);
    }

    public static synchronized void w(String tag, String message) {
        Log.w(tag, message);
        append("WARN", tag, message);
    }

    public static synchronized void e(String tag, String message) {
        Log.e(tag, message);
        append("ERR ", tag, message);
    }

    public static synchronized void e(String tag, String message, Throwable t) {
        Log.e(tag, message, t);
        String msg = message + (t != null ? (" (" + t.getMessage() + ")") : "");
        append("ERR ", tag, msg);
    }

    private static synchronized void append(String level, String tag, String message) {
        String ts = sDateFormat.format(new Date());
        String entry = "[" + ts + "] [" + level + "] [" + tag + "] " + message;
        sLogBuffer.add(entry);
        while (sLogBuffer.size() > MAX_ENTRIES) {
            sLogBuffer.removeFirst();
        }
    }

    public static synchronized List<String> getEntries() {
        return new ArrayList<String>(sLogBuffer);
    }

    public static synchronized String getFormattedLogs() {
        if (sLogBuffer.isEmpty()) {
            return "No in-app log events recorded yet.\nPerform an action (e.g. Refresh, Test Switch) to generate diagnostic events.";
        }
        StringBuilder sb = new StringBuilder();
        for (String entry : sLogBuffer) {
            sb.append(entry).append("\n");
        }
        return sb.toString();
    }

    public static synchronized void clear() {
        sLogBuffer.clear();
    }
}
