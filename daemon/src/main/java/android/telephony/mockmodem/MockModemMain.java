package android.telephony.mockmodem;

import android.os.Looper;

/**
 * Entry point for the root app_process daemon.
 */
public class MockModemMain {
    private static final String TAG = "MockModemMain";

    public static void main(String[] args) {
        // MockModemConfigBase constructs a Handler immediately; the Looper
        // must be prepared before any service initialization.
        Looper.prepareMainLooper();

        MockModemService service = new MockModemService();
        service.init();
        StandaloneRadioRegistrar.register(service);

        // MockNetworkService defaults to the no-service bootstrap state in its
        // constructor, so early framework registration queries observe it without
        // an explicit publish. The module daemon is intentionally not configurable:
        // it provides one fixed mock SIM that registers home once ready.

        // Wait for the framework to bind every radio interface and install
        // response/indication callbacks, then publish the fixed bootstrap state.
        while (!service.waitForRadioInterfaces(30000)) {
            System.out.println(
                    "radio interfaces not ready; still waiting, missing="
                            + service.getMissingRadioInterfaces());
        }
        if (!service.initialize()) {
            throw new IllegalStateException("failed to initialize bootstrap SIM state");
        }
        System.out.println("mock modem initialized with static SIM bootstrap state");

        // app_process already serves binder transactions on its own pool;
        // the main thread just keeps the process alive.
        Looper.loop();
    }
}
