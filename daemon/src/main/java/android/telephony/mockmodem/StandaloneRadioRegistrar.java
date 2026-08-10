package android.telephony.mockmodem;

import android.os.ServiceManager;
import android.util.Log;

/** Registers the module's bootstrap binders with the global servicemanager. */
final class StandaloneRadioRegistrar {
    private static final String TAG = "StandaloneRadioRegistrar";

    private StandaloneRadioRegistrar() {}

    static void register(MockModemService service) {
        markVintfStability(service.getIRadioConfig());
        markVintfStability(service.getIRadioModem());
        markVintfStability(service.getIRadioSim());
        markVintfStability(service.getIRadioNetwork());
        markVintfStability(service.getIRadioData());
        markVintfStability(service.getIRadioMessaging());
        markVintfStability(service.getIRadioVoice());

        ServiceManager.addService(
                "android.hardware.radio.config.IRadioConfig/default", service.getIRadioConfig());
        ServiceManager.addService(
                "android.hardware.radio.modem.IRadioModem/slot1", service.getIRadioModem());
        ServiceManager.addService(
                "android.hardware.radio.sim.IRadioSim/slot1", service.getIRadioSim());
        ServiceManager.addService(
                "android.hardware.radio.network.IRadioNetwork/slot1", service.getIRadioNetwork());
        ServiceManager.addService(
                "android.hardware.radio.data.IRadioData/slot1", service.getIRadioData());
        ServiceManager.addService(
                "android.hardware.radio.messaging.IRadioMessaging/slot1",
                service.getIRadioMessaging());
        ServiceManager.addService(
                "android.hardware.radio.voice.IRadioVoice/slot1", service.getIRadioVoice());
        Log.i(TAG, "Bootstrap Radio HAL AIDL services registered with servicemanager");
    }

    private static void markVintfStability(Object binder) {
        try {
            java.lang.reflect.Method method =
                    Class.forName("android.os.Binder").getDeclaredMethod("markVintfStability");
            method.setAccessible(true);
            method.invoke(binder);
        } catch (Throwable t) {
            Log.e(TAG, "markVintfStability failed", t);
        }
    }
}
