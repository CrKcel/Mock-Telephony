/*
 * Copyright (C) 2021 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package android.telephony.mockmodem;

import android.hardware.radio.RadioTechnology;
import android.hardware.radio.network.CellIdentity;
import android.hardware.radio.network.CellInfo;
import android.hardware.radio.network.OperatorInfo;
import android.hardware.radio.network.RegState;
import android.hardware.radio.network.SignalStrength;
import android.util.Log;

/**
 * Module fork: no carrier presets. The module registers home on the mock SIM's
 * PLMN once the SIM is present and ready ({@link #updateSimPlmn}); there are no
 * preset cells, operator identities or signal values. The constructor default is
 * the no-service state (no home/roaming camping, empty operator/RAT), so HAL
 * queries are correct before the SIM PLMN is known; {@link #applyNetworkConfig}
 * is retained for the JVM apply-path tests and is not used by the module daemon.
 */
public class MockNetworkService {
    private static final String TAG = "MockNetworkService";

    // Operator name reported while registered on the mock SIM's PLMN.
    private static final String MOCK_OPERATOR_NAME = "SoftBank";

    // Grouping of RAFs
    // 2G
    public static final int GSM =
            MockRadioAccessFamily.RAF_GSM | MockRadioAccessFamily.RAF_GPRS | MockRadioAccessFamily.RAF_EDGE;
    public static final int CDMA =
            MockRadioAccessFamily.RAF_CDMA | MockRadioAccessFamily.RAF_1xRTT;
    // 3G
    public static final int EVDO =
            MockRadioAccessFamily.RAF_EVDO_0
                    | MockRadioAccessFamily.RAF_EVDO_A
                    | MockRadioAccessFamily.RAF_EVDO_B
                    | MockRadioAccessFamily.RAF_EHRPD;
    public static final int HS =
            MockRadioAccessFamily.RAF_HSUPA
                    | MockRadioAccessFamily.RAF_HSDPA
                    | MockRadioAccessFamily.RAF_HSPA
                    | MockRadioAccessFamily.RAF_HSPAP;
    public static final int WCDMA = HS | MockRadioAccessFamily.RAF_UMTS;
    // 4G
    public static final int LTE = MockRadioAccessFamily.RAF_LTE | MockRadioAccessFamily.RAF_LTE_CA;
    // 5G
    public static final int NR = MockRadioAccessFamily.RAF_NR;

    // Network status update reason
    static final int NETWORK_UPDATE_PREFERRED_MODE_CHANGE = 1;

    private int mCsRegState = RegState.NOT_REG_MT_NOT_SEARCHING_OP;
    private int mPsRegState = RegState.NOT_REG_MT_NOT_SEARCHING_OP;

    private boolean mIsHomeCamping = false;
    private boolean mIsRoamingCamping = false;

    private int mRat;
    private String mOperatorName = "";
    private String mOperatorNumeric = "";

    private int mHighRat;

    public MockNetworkService() {
    }

    private int getHighestRatFromNetworkType(int raf) {
        int rat;
        int networkMode = MockRadioAccessFamily.getNetworkTypeFromRaf(raf);

        switch (networkMode) {
            case MockRilConstants.NETWORK_MODE_WCDMA_PREF:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_GSM_ONLY:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_GSM;
                break;
            case MockRilConstants.NETWORK_MODE_WCDMA_ONLY:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_GSM_UMTS:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_CDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_IS95A;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_CDMA_EVDO:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_CDMA_EVDO_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_ONLY:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_CDMA_NO_EVDO:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_IS95A;
                break;
            case MockRilConstants.NETWORK_MODE_EVDO_NO_CDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_EVDO_0;
                break;
            case MockRilConstants.NETWORK_MODE_GLOBAL:
                // GSM | WCDMA | CDMA | EVDO;
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_TDSCDMA_ONLY:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_TD_SCDMA;
                break;
            case MockRilConstants.NETWORK_MODE_TDSCDMA_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_TDSCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_TDSCDMA_GSM:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_TD_SCDMA;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_GSM:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_TDSCDMA_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_TDSCDMA_CDMA_EVDO_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_HSPA;
                break;
            case MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_LTE;
                break;
            case MockRilConstants.NETWORK_MODE_NR_ONLY:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_CDMA_EVDO:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_GSM:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            case MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_NR;
                break;
            default:
                rat = MockServiceState.RIL_RADIO_TECHNOLOGY_UNKNOWN;
                break;
        }
        return rat;
    }

    public android.hardware.radio.network.OperatorInfo getPrimaryCellOperatorInfo() {
        OperatorInfo operatorInfo = new OperatorInfo();
        operatorInfo.alphaLong = mOperatorName;
        operatorInfo.alphaShort = mOperatorName;
        operatorInfo.operatorNumeric = mOperatorNumeric;
        return operatorInfo;
    }

    public android.hardware.radio.network.CellIdentity getPrimaryCellIdentity() {
        return CellIdentity.noinit(true);
    }

    public android.hardware.radio.network.CellInfo[] getCells() {
        return new CellInfo[0];
    }

    public boolean updateHighestRegisteredRat(int raf) {

        int rat = mHighRat;
        mHighRat = getHighestRatFromNetworkType(raf);

        return (rat != mHighRat);
    }

    public void updateNetworkStatus(int reason) {
        if (reason == NETWORK_UPDATE_PREFERRED_MODE_CHANGE) {
            // The bootstrap never applies a preferred-mode change (the setter
            // always fails deterministically), so there is no state to refresh here.
            Log.d(TAG, "updateNetworkStatus: NETWORK_UPDATE_PREFERRED_MODE_CHANGE");
        }
    }

    public int getRegistrationRat() {
        if (!isInService()) {
            return RadioTechnology.UNKNOWN;
        }
        return (mRat != 0) ? mRat : RadioTechnology.UNKNOWN;
    }

    public android.hardware.radio.network.SignalStrength getSignalStrength() {
        android.hardware.radio.network.SignalStrength signalStrength =
                new SignalStrength();

        signalStrength.gsm = new android.hardware.radio.network.GsmSignalStrength();
        signalStrength.cdma = new android.hardware.radio.network.CdmaSignalStrength();
        signalStrength.evdo = new android.hardware.radio.network.EvdoSignalStrength();
        signalStrength.lte = new android.hardware.radio.network.LteSignalStrength();
        signalStrength.tdscdma = new android.hardware.radio.network.TdscdmaSignalStrength();
        signalStrength.wcdma = new android.hardware.radio.network.WcdmaSignalStrength();
        signalStrength.nr = new android.hardware.radio.network.NrSignalStrength();
        signalStrength.nr.csiCqiReport = new byte[0];

        return signalStrength;
    }

    /**
     * Apply one validated network configuration. The module fork carries no preset
     * cells, so only the registration state and the applied operator/RAT are stored;
     * cell identities, signals and carriers are not part of the surface.
     */
    public void applyNetworkConfig(MockAppliedConfig config) {
        int reg;
        if (!config.inService) {
            reg = RegState.NOT_REG_MT_NOT_SEARCHING_OP;
            mIsHomeCamping = false;
            mIsRoamingCamping = false;
            mOperatorName = "";
            mOperatorNumeric = "";
            mRat = 0;
        } else if (config.roaming) {
            reg = RegState.REG_ROAMING;
            mIsHomeCamping = false;
            mIsRoamingCamping = true;
            applyOperator(config);
            mRat = config.rat;
        } else {
            reg = RegState.REG_HOME;
            mIsHomeCamping = true;
            mIsRoamingCamping = false;
            applyOperator(config);
            mRat = config.rat;
        }

        updateServiceState(reg);
    }

    private void applyOperator(MockAppliedConfig config) {
        mOperatorName = config.operatorName;
        mOperatorNumeric = config.operatorNumeric;
        if (mOperatorNumeric.isEmpty() && !config.mcc.isEmpty() && !config.mnc.isEmpty()) {
            mOperatorNumeric = config.mcc + config.mnc;
        }
    }

    public int getRegistration(int domain) {
        if (domain == android.hardware.radio.network.Domain.CS) {
            return mCsRegState;
        } else {
            return mPsRegState;
        }
    }

    public boolean isInService() {
        return ((mCsRegState == RegState.REG_HOME)
                || (mPsRegState == RegState.REG_HOME)
                || (mCsRegState == RegState.REG_ROAMING)
                || (mPsRegState == RegState.REG_ROAMING));
    }

    public void updateSimPlmn(String simPlmn) {
        // Static mock registration
        if (simPlmn == null || simPlmn.isEmpty()) {
            Log.d(TAG, "updateSimPlmn: empty PLMN, staying unregistered");
            return;
        }
        mIsHomeCamping = true;
        mIsRoamingCamping = false;
        mOperatorNumeric = simPlmn;
        mOperatorName = MOCK_OPERATOR_NAME;
        mRat = RadioTechnology.LTE;
        updateServiceState(RegState.REG_HOME);
        Log.d(TAG, "updateSimPlmn: camping home on " + simPlmn);
    }

    /**
     * Set the device enters IN SERVICE
     *
     * @param isRoaming boolean true if the camping network is Roaming service, otherwise Home
     *     service
     * @param inService boolean true if the deviec enters carrier coverge, otherwise the device
     *     leaves the carrier coverage.
     */
    public void setServiceStatus(boolean isRoaming, boolean inService) {
        if (isRoaming) {
            mIsRoamingCamping = inService;
        } else {
            mIsHomeCamping = inService;
        }
    }

    public boolean getIsHomeCamping() {
        return mIsHomeCamping;
    }

    public boolean getIsRoamingCamping() {
        return mIsRoamingCamping;
    }

    public void updateServiceState(int reg) {
        Log.d(TAG, "updateServiceState " + reg);
        switch (reg) {
            case RegState.NOT_REG_MT_SEARCHING_OP:
                mCsRegState = RegState.NOT_REG_MT_SEARCHING_OP;
                mPsRegState = RegState.NOT_REG_MT_SEARCHING_OP;
                break;
            case RegState.REG_HOME:
                mCsRegState = RegState.REG_HOME;
                mPsRegState = RegState.REG_HOME;
                break;
            case RegState.REG_ROAMING:
                mCsRegState = RegState.REG_ROAMING;
                mPsRegState = RegState.REG_ROAMING;
                break;
            case RegState.NOT_REG_MT_NOT_SEARCHING_OP:
            default:
                mCsRegState = RegState.NOT_REG_MT_NOT_SEARCHING_OP;
                mPsRegState = RegState.NOT_REG_MT_NOT_SEARCHING_OP;
                break;
        }
    }

    @Override
    public String toString() {
        return "isInService():" + isInService() + " Rat:" + getRegistrationRat() + "";
    }
}
