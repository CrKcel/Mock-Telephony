package android.telephony.mockmodem;

/** Minimal dependency-free test runner for the JVM unit tests. */
final class TestRunner {
    private static int pass;
    private static int fail;

    private TestRunner() {}

    static void check(String name, boolean condition) {
        if (condition) {
            pass++;
            System.out.println("  ok   " + name);
        } else {
            fail++;
            System.out.println("  FAIL " + name);
        }
    }

    static void done() {
        System.out.println("java tests: " + pass + " passed, " + fail + " failed");
        if (fail > 0) {
            System.exit(1);
        }
    }
}
