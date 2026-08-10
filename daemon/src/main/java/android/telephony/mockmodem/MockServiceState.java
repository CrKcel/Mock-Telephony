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

/** Stable values of the hidden ServiceState.RIL_RADIO_TECHNOLOGY_* constants. */
final class MockServiceState {
    static final int RIL_RADIO_TECHNOLOGY_UNKNOWN = 0;
    static final int RIL_RADIO_TECHNOLOGY_IS95A = 4;
    static final int RIL_RADIO_TECHNOLOGY_EVDO_0 = 7;
    static final int RIL_RADIO_TECHNOLOGY_HSPA = 12;
    static final int RIL_RADIO_TECHNOLOGY_LTE = 14;
    static final int RIL_RADIO_TECHNOLOGY_GSM = 17;
    static final int RIL_RADIO_TECHNOLOGY_TD_SCDMA = 18;
    static final int RIL_RADIO_TECHNOLOGY_NR = 21;

    private MockServiceState() {
    }
}
