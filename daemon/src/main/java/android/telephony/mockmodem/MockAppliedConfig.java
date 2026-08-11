package android.telephony.mockmodem;

/**
 * Value carrier for the static bootstrap network state. The module daemon fixes one present mock
 * SIM that registers home on its PLMN, so it only ever applies {@link #inService}. The module
 * fork carries no carrier presets: the apply path stores only the registration state and the
 * applied operator/RAT from these fields.
 */
public final class MockAppliedConfig {
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
