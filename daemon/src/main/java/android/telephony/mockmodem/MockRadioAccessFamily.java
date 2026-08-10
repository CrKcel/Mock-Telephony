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

/**
 * Standalone copy of the stable RAT bitmask constants and the RAF-to-network
 * mode conversion used by the CTS mock network service.
 */
final class MockRadioAccessFamily {
    // Values mirror TelephonyManager.NETWORK_TYPE_BITMASK_* (API stable).
    static final int RAF_UNKNOWN = 0;
    static final int RAF_GPRS = 1 << 0;
    static final int RAF_EDGE = 1 << 1;
    static final int RAF_UMTS = 1 << 2;
    static final int RAF_CDMA = 1 << 3;
    static final int RAF_EVDO_0 = 1 << 4;
    static final int RAF_EVDO_A = 1 << 5;
    static final int RAF_1xRTT = 1 << 6;
    static final int RAF_HSDPA = 1 << 7;
    static final int RAF_HSUPA = 1 << 8;
    static final int RAF_HSPA = 1 << 9;
    static final int RAF_IDEN = 1 << 10;
    static final int RAF_EVDO_B = 1 << 11;
    static final int RAF_LTE = 1 << 12;
    static final int RAF_EHRPD = 1 << 13;
    static final int RAF_HSPAP = 1 << 14;
    static final int RAF_GSM = 1 << 15;
    static final int RAF_TD_SCDMA = 1 << 16;
    static final int RAF_LTE_CA = 1 << 18;
    static final int RAF_NR = 1 << 19;

    private static final int GSM = RAF_GSM | RAF_GPRS | RAF_EDGE;
    private static final int CDMA = RAF_CDMA | RAF_1xRTT;
    private static final int EVDO = RAF_EVDO_0 | RAF_EVDO_A | RAF_EVDO_B | RAF_EHRPD;
    private static final int HS = RAF_HSUPA | RAF_HSDPA | RAF_HSPA | RAF_HSPAP;
    private static final int WCDMA = HS | RAF_UMTS;
    private static final int LTE = RAF_LTE | RAF_LTE_CA;
    private static final int NR = RAF_NR;

    private static int getAdjustedRaf(int raf) {
        raf = ((GSM & raf) > 0) ? (GSM | raf) : raf;
        raf = ((WCDMA & raf) > 0) ? (WCDMA | raf) : raf;
        raf = ((CDMA & raf) > 0) ? (CDMA | raf) : raf;
        raf = ((EVDO & raf) > 0) ? (EVDO | raf) : raf;
        raf = ((LTE & raf) > 0) ? (LTE | raf) : raf;
        raf = ((NR & raf) > 0) ? (NR | raf) : raf;
        return raf;
    }

    static int getNetworkTypeFromRaf(int raf) {
        raf = getAdjustedRaf(raf);
        if (raf == (GSM | WCDMA)) return MockRilConstants.NETWORK_MODE_WCDMA_PREF;
        if (raf == GSM) return MockRilConstants.NETWORK_MODE_GSM_ONLY;
        if (raf == WCDMA) return MockRilConstants.NETWORK_MODE_WCDMA_ONLY;
        if (raf == (CDMA | EVDO)) return MockRilConstants.NETWORK_MODE_CDMA;
        if (raf == (LTE | CDMA | EVDO)) return MockRilConstants.NETWORK_MODE_LTE_CDMA_EVDO;
        if (raf == (LTE | GSM | WCDMA)) return MockRilConstants.NETWORK_MODE_LTE_GSM_WCDMA;
        if (raf == (LTE | CDMA | EVDO | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_LTE_CDMA_EVDO_GSM_WCDMA;
        }
        if (raf == LTE) return MockRilConstants.NETWORK_MODE_LTE_ONLY;
        if (raf == (LTE | WCDMA)) return MockRilConstants.NETWORK_MODE_LTE_WCDMA;
        if (raf == CDMA) return MockRilConstants.NETWORK_MODE_CDMA_NO_EVDO;
        if (raf == EVDO) return MockRilConstants.NETWORK_MODE_EVDO_NO_CDMA;
        if (raf == (GSM | WCDMA | CDMA | EVDO)) return MockRilConstants.NETWORK_MODE_GLOBAL;
        if (raf == RAF_TD_SCDMA) return MockRilConstants.NETWORK_MODE_TDSCDMA_ONLY;
        if (raf == (RAF_TD_SCDMA | WCDMA)) return MockRilConstants.NETWORK_MODE_TDSCDMA_WCDMA;
        if (raf == (LTE | RAF_TD_SCDMA)) return MockRilConstants.NETWORK_MODE_LTE_TDSCDMA;
        if (raf == (RAF_TD_SCDMA | GSM)) return MockRilConstants.NETWORK_MODE_TDSCDMA_GSM;
        if (raf == (LTE | RAF_TD_SCDMA | GSM)) return MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_GSM;
        if (raf == (RAF_TD_SCDMA | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_TDSCDMA_GSM_WCDMA;
        }
        if (raf == (LTE | RAF_TD_SCDMA | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_WCDMA;
        }
        if (raf == (LTE | RAF_TD_SCDMA | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_GSM_WCDMA;
        }
        if (raf == (RAF_TD_SCDMA | CDMA | EVDO | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_TDSCDMA_CDMA_EVDO_GSM_WCDMA;
        }
        if (raf == (LTE | RAF_TD_SCDMA | CDMA | EVDO | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA;
        }
        if (raf == NR) return MockRilConstants.NETWORK_MODE_NR_ONLY;
        if (raf == (NR | LTE)) return MockRilConstants.NETWORK_MODE_NR_LTE;
        if (raf == (NR | LTE | CDMA | EVDO)) return MockRilConstants.NETWORK_MODE_NR_LTE_CDMA_EVDO;
        if (raf == (NR | LTE | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_GSM_WCDMA;
        }
        if (raf == (NR | LTE | CDMA | EVDO | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA;
        }
        if (raf == (NR | LTE | WCDMA)) return MockRilConstants.NETWORK_MODE_NR_LTE_WCDMA;
        if (raf == (NR | LTE | RAF_TD_SCDMA)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA;
        }
        if (raf == (NR | LTE | RAF_TD_SCDMA | GSM)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_GSM;
        }
        if (raf == (NR | LTE | RAF_TD_SCDMA | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_WCDMA;
        }
        if (raf == (NR | LTE | RAF_TD_SCDMA | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA;
        }
        if (raf == (NR | LTE | RAF_TD_SCDMA | CDMA | EVDO | GSM | WCDMA)) {
            return MockRilConstants.NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA;
        }
        return MockRilConstants.PREFERRED_NETWORK_MODE;
    }

    private MockRadioAccessFamily() {
    }
}
