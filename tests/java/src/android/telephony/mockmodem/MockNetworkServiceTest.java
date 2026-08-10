package android.telephony.mockmodem;

import android.hardware.radio.RadioTechnology;
import android.hardware.radio.network.Domain;
import android.hardware.radio.network.RegState;

/** JVM regression tests for MockNetworkService (no-carrier-preset module fork). */
public final class MockNetworkServiceTest {
    public static void main(String[] args) {
        constructorDefaultsToNoService();
        updateHighestRegisteredRatReportsChange();
        noServiceReportsNoCells();
        inServiceConfigReportsRegistration();
        TestRunner.done();
    }

    private static void constructorDefaultsToNoService() {
        MockNetworkService svc = new MockNetworkService();
        TestRunner.check(
                "ctor: CS registration is NOT_REG",
                svc.getRegistration(Domain.CS) == RegState.NOT_REG_MT_NOT_SEARCHING_OP);
        TestRunner.check(
                "ctor: PS registration is NOT_REG",
                svc.getRegistration(Domain.PS) == RegState.NOT_REG_MT_NOT_SEARCHING_OP);
        TestRunner.check("ctor: not in service", !svc.isInService());
        TestRunner.check(
                "ctor: not home/roaming camping",
                !svc.getIsHomeCamping() && !svc.getIsRoamingCamping());
        TestRunner.check("ctor: no cells", svc.getCells().length == 0);
        TestRunner.check(
                "ctor: registration RAT is UNKNOWN",
                svc.getRegistrationRat() == RadioTechnology.UNKNOWN);
    }

    private static void updateHighestRegisteredRatReportsChange() {
        MockNetworkService svc = new MockNetworkService();
        int raf =
                MockNetworkService.GSM
                        | MockNetworkService.WCDMA
                        | MockNetworkService.LTE
                        | MockNetworkService.NR;
        TestRunner.check("first update reports a RAT change", svc.updateHighestRegisteredRat(raf));
        TestRunner.check("same update reports no change", !svc.updateHighestRegisteredRat(raf));
    }

    private static void noServiceReportsNoCells() {
        MockNetworkService svc = new MockNetworkService();
        MockAppliedConfig cfg = new MockAppliedConfig();
        cfg.inService = false;
        svc.applyNetworkConfig(cfg);
        TestRunner.check("no-service: no cells reported", svc.getCells().length == 0);
        TestRunner.check(
                "no-service: CS registration NOT_REG",
                svc.getRegistration(Domain.CS) == RegState.NOT_REG_MT_NOT_SEARCHING_OP);
        TestRunner.check(
                "no-service: PS registration NOT_REG",
                svc.getRegistration(Domain.PS) == RegState.NOT_REG_MT_NOT_SEARCHING_OP);
        TestRunner.check(
                "no-service: not camping",
                !svc.getIsHomeCamping() && !svc.getIsRoamingCamping());
    }

    private static void inServiceConfigReportsRegistration() {
        MockNetworkService svc = new MockNetworkService();
        MockAppliedConfig cfg = new MockAppliedConfig();
        cfg.inService = true;
        cfg.rat = RadioTechnology.LTE;
        svc.applyNetworkConfig(cfg);
        TestRunner.check("in-service: is in service", svc.isInService());
        TestRunner.check(
                "in-service: CS registration is REG_HOME",
                svc.getRegistration(Domain.CS) == RegState.REG_HOME);
        TestRunner.check(
                "in-service: registration RAT is LTE",
                svc.getRegistrationRat() == RadioTechnology.LTE);
        TestRunner.check("in-service: home camping", svc.getIsHomeCamping());
    }
}
