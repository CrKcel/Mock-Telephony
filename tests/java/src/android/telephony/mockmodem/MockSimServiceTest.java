package android.telephony.mockmodem;

/** JVM regression tests for MockSimService's static absent-SIM state. */
public final class MockSimServiceTest {
    public static void main(String[] args) {
        absentSimByDefault();
        forcedProfileStaysAbsent();
        TestRunner.done();
    }

    private static void absentSimByDefault() {
        MockSimService sim = new MockSimService(null, 0);
        TestRunner.check("no card present", !sim.isCardPresent());
        TestRunner.check("zero SIM applications", sim.getNumOfSimApp() == 0);
        TestRunner.check("empty application array", sim.getSimApp().length == 0);
        TestRunner.check("no active application", sim.getActiveSimAppData() == null);
        TestRunner.check("empty ICCID", sim.getICCID().isEmpty());
    }

    private static void forcedProfileStaysAbsent() {
        MockSimService sim = new MockSimService(null, 0);
        sim.loadSimCard(MockSimService.MOCK_SIM_PROFILE_ID_DEFAULT);
        TestRunner.check("forced default profile stays absent", !sim.isCardPresent());
    }
}
