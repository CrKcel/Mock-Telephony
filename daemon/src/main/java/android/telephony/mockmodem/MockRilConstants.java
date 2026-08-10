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
 * Standalone copy of the stable RIL network-mode bitmask constants.
 *
 * <p>The CTS mock imports com.android.internal.telephony.RILConstants, which
 * is hidden API and unavailable to a normal priv-app.  These values are the
 * historical AOSP constants and have never changed.
 */
final class MockRilConstants {
    static final int NETWORK_MODE_WCDMA_PREF = 0;
    static final int NETWORK_MODE_GSM_ONLY = 1;
    static final int NETWORK_MODE_WCDMA_ONLY = 2;
    static final int NETWORK_MODE_GSM_UMTS = 3;
    static final int NETWORK_MODE_CDMA = 4;
    static final int NETWORK_MODE_CDMA_NO_EVDO = 5;
    static final int NETWORK_MODE_EVDO_NO_CDMA = 6;
    static final int NETWORK_MODE_GLOBAL = 7;
    static final int NETWORK_MODE_LTE_CDMA_EVDO = 8;
    static final int NETWORK_MODE_LTE_GSM_WCDMA = 9;
    static final int NETWORK_MODE_LTE_CDMA_EVDO_GSM_WCDMA = 10;
    static final int NETWORK_MODE_LTE_ONLY = 11;
    static final int NETWORK_MODE_LTE_WCDMA = 12;
    static final int NETWORK_MODE_TDSCDMA_ONLY = 13;
    static final int NETWORK_MODE_TDSCDMA_WCDMA = 14;
    static final int NETWORK_MODE_LTE_TDSCDMA = 15;
    static final int NETWORK_MODE_TDSCDMA_GSM = 16;
    static final int NETWORK_MODE_LTE_TDSCDMA_GSM = 17;
    static final int NETWORK_MODE_TDSCDMA_GSM_WCDMA = 18;
    static final int NETWORK_MODE_LTE_TDSCDMA_WCDMA = 19;
    static final int NETWORK_MODE_LTE_TDSCDMA_GSM_WCDMA = 20;
    static final int NETWORK_MODE_TDSCDMA_CDMA_EVDO_GSM_WCDMA = 21;
    static final int NETWORK_MODE_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA = 22;
    static final int NETWORK_MODE_NR_ONLY = 23;
    static final int NETWORK_MODE_NR_LTE = 24;
    static final int NETWORK_MODE_NR_LTE_CDMA_EVDO = 25;
    static final int NETWORK_MODE_NR_LTE_GSM_WCDMA = 26;
    static final int NETWORK_MODE_NR_LTE_CDMA_EVDO_GSM_WCDMA = 27;
    static final int NETWORK_MODE_NR_LTE_WCDMA = 28;
    static final int NETWORK_MODE_NR_LTE_TDSCDMA = 29;
    static final int NETWORK_MODE_NR_LTE_TDSCDMA_GSM = 30;
    static final int NETWORK_MODE_NR_LTE_TDSCDMA_WCDMA = 31;
    static final int NETWORK_MODE_NR_LTE_TDSCDMA_GSM_WCDMA = 32;
    static final int NETWORK_MODE_NR_LTE_TDSCDMA_CDMA_EVDO_GSM_WCDMA = 33;
    static final int PREFERRED_NETWORK_MODE = NETWORK_MODE_LTE_GSM_WCDMA;

    private MockRilConstants() {
    }
}
