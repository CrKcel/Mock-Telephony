package android.os;

/**
 * Compile-time stub for the hidden framework class.  The boot classpath
 * implementation is used at runtime (the daemon runs with app_process).
 */
public class AsyncResult {
    public Object userObj;
    public Object result;
    public Throwable exception;

    public AsyncResult(Object userObj, Object result, Throwable exception) {
        this.userObj = userObj;
        this.result = result;
        this.exception = exception;
    }
}
