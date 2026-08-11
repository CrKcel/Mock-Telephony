package android.telephony.mockmodem;

import android.hardware.radio.sim.AppStatus;

/** JVM regression tests for MockSimService's static present mock SIM state. */
public final class MockSimServiceTest {
    public static void main(String[] args) {
        presentSimByDefault();
        presentSimSlotConfiguration();
        TestRunner.done();
    }

    private static void presentSimByDefault() {
        MockSimService sim = new MockSimService(null, 0);
        TestRunner.check("card present", sim.isCardPresent());
        TestRunner.check("one SIM application", sim.getNumOfSimApp() == 1);
        TestRunner.check("one application entry", sim.getSimApp().length == 1);
        TestRunner.check(
                "application is READY",
                sim.getSimApp()[0].appState == AppStatus.APP_STATE_READY);
        TestRunner.check(
                "application is a USIM",
                sim.getSimApp()[0].appType == AppStatus.APP_TYPE_USIM);
        TestRunner.check("active application present", sim.getActiveSimAppData() != null);
    }

    private static void presentSimSlotConfiguration() {
        MockSimService sim = new MockSimService(null, 0);
        TestRunner.check("single SIM port", sim.getNumOfSimPortInfo() == 1);
        TestRunner.check("port active", sim.isSlotPortActive());
        TestRunner.check("physical slot 0", sim.getPhysicalSlotId() == 0);
        TestRunner.check("logical slot 0", sim.getLogicalSlotId() == 0);
        TestRunner.check("mock ATR non-empty", !sim.getATR().isEmpty());
        TestRunner.check("empty EID (physical card)", sim.getEID().isEmpty());
        TestRunner.check("pin state disabled", sim.getUniversalPinState() == 3);
        TestRunner.check("GSM app index 0", sim.getGsmAppIndex() == 0);
        TestRunner.check("no CDMA app index", sim.getCdmaAppIndex() == -1);
    }
}
