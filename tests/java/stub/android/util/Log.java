package android.util;

/**
 * No-op stand-in for the platform android.util.Log used by JVM unit tests.
 * Placed on the runtime classpath ahead of android.jar so native Log calls are
 * never reached.
 */
public final class Log {
    public static int v(String tag, String msg) { return 0; }
    public static int d(String tag, String msg) { return 0; }
    public static int i(String tag, String msg) { return 0; }
    public static int w(String tag, String msg) { return 0; }
    public static int e(String tag, String msg) { return 0; }
    public static int v(String tag, String msg, Throwable tr) { return 0; }
    public static int d(String tag, String msg, Throwable tr) { return 0; }
    public static int i(String tag, String msg, Throwable tr) { return 0; }
    public static int w(String tag, String msg, Throwable tr) { return 0; }
    public static int e(String tag, String msg, Throwable tr) { return 0; }
}
