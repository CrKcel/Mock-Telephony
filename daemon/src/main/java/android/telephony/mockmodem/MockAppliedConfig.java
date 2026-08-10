package android.telephony.mockmodem;

/**
 * Value carrier for the static bootstrap network state. The module daemon fixes one absent SIM
 * slot and no service, so it only ever sets {@link #simProfile} and {@link #inService}. The
 * module fork carries no carrier presets: the apply path stores only the registration state and
 * the applied operator/RAT from these fields.
 */
public final class MockAppliedConfig {
    // SIM profile id (fixed to the absent-SIM default in the module daemon).
    public int simProfile;

    // Network
    public boolean inService = true;
    public String mcc = "";
    public String mnc = "";
    public boolean roaming;
    /** 0 means no specific serving RAT. */
    public int rat;
    public String operatorName = "";
    public String operatorNumeric = "";
}
