/*
 * Copyright (C) 2022 The Android Open Source Project
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

import android.content.Context;
import android.hardware.radio.sim.AppStatus;
import android.hardware.radio.sim.PersoSubstate;
import android.hardware.radio.sim.PinState;
import android.util.Log;

import java.util.ArrayList;

public class MockSimService {
    private static final String TAG = "MockSimService";

    /* Type of SIM IO command */
    public static final int COMMAND_READ_BINARY = 0xb0;
    public static final int COMMAND_GET_RESPONSE = 0xc0;

    /* EF Id definition */
    public static final int EF_ICCID = 0x2FE2;
    public static final int EF_IMSI = 0x6F07;
    public static final int EF_SPN = 0x6F46;
    public static final int EF_GID1 = 0x6F3E;
    public static final int EF_GID2 = 0x6F3F;


    /* Support SIM slot */
    private static final int MOCK_SIM_SLOT_1 = 0;
    public static final int MOCK_SIM_SLOT_MIN = 1;
    public static final int MOCK_SIM_SLOT_MAX = 3;

    /* Default value definition */
    private static final int MOCK_SIM_DEFAULT_SLOTID = MOCK_SIM_SLOT_1;
    private static final int DEFAULT_NUM_OF_SIM_PORT_INFO = 1;
    private static final int DEFAULT_NUM_OF_SIM_APP = 0;
    private static final int DEFAULT_GSM_APP_IDX = 0;
    private static final int DEFAULT_CDMA_APP_IDX = -1;
    private static final int DEFAULT_IMS_APP_IDX = -1;
    // SIM1 slot status
    private static final boolean DEFAULT_SIM1_CARD_PRESENT = true;
    private static final String DEFAULT_SIM1_ATR = "3F9F96801FC88031E073FE211B64E5A00800";
    private static final String DEFAULT_SIM1_EID = "";
    private static final String DEFAULT_SIM1_ICCID = "89812015689753245695";
    private static final boolean DEFAULT_SIM1_PORT_ACTIVE = true;
    private static final int DEFAULT_SIM1_PORT_ID = 0;
    private static final int DEFAULT_SIM1_LOGICAL_SLOT_ID = 0;
    private static final int DEFAULT_SIM1_PHYSICAL_SLOT_ID = 0;
    private static final int DEFAULT_SIM1_UNIVERSAL_PIN_STATE = PinState.DISABLED;

    // Static mock SIM identity. The module daemon carries one fixed present SIM; 
    // these are static defaults, consistent with how the modem config values (baseband/IMEI/...) are defined.
    private static final String MOCK_MCC = "440";
    private static final String MOCK_MNC = "20";
    private static final String MOCK_MSIN = "3819472074";
    // GET_RESPONSE metadata for EF_ICCID, in the same 0000<size><fileId>040000ffff01020002
    // layout that buildEfFileInfo emits for the other transparent EFs. The 2-byte file size
    // sits at bytes 2-3 (0x000a = 10 bytes, the BCD-encoded 20-digit ICCID). Must stay even
    // length: the framework IccIoResult constructor hexStringToBytes() throws on odd hex.
    private static final String MOCK_ICCID_INFO = "0000000a2fe2040000ffff01020002";
    private static final String MOCK_SPN = "SoftBank";
    private static final String MOCK_GID1 = "00";
    private static final String MOCK_GID2 = "00";
    private static final String MOCK_AID = "A0004040871002";
    private static final String MOCK_SIM_PATH = "3F06";

    private Context mContext;

    // SIM Slot status
    private int mPhysicalSlotId;
    private int mLogicalSlotId;
    private int mSlotPortId;
    private boolean mIsSlotPortActive;
    private boolean mIsCardPresent;

    // SIM card data
    private String mEID;
    private String mATR;
    private int mUniversalPinState;

    private AppStatus[] mSimApp;
    private ArrayList<SimAppData> mSimAppList;

    public class SimAppData {
        private static final int EF_INFO_DATA = 0;
        private static final int EF_BINARY_DATA = 1;

        private int mSimAppId;
        private String mAid;
        private boolean mIsCurrentActive;
        private String mPath;
        private int mFdnStatus;
        private int mPin1State;
        private String mImsi;
        private String mMcc;
        private String mMnc;
        private String mMsin;
        private String[] mIccid;
        private String mSpn = "";
        private String mGid1 = "00";
        private String mGid2 = "00";

        private void initSimAppData(int simappid, String aid, String path, boolean status) {
            mSimAppId = simappid;
            mAid = aid;
            mIsCurrentActive = status;
            mPath = path;
            mIccid = new String[2];
        }

        public SimAppData(int simappid, String aid, String path) {
            initSimAppData(simappid, aid, path, false);
        }

        public SimAppData(int simappid, String aid, String path, boolean status) {
            initSimAppData(simappid, aid, path, status);
        }

        public int getSimAppId() {
            return mSimAppId;
        }

        public String getAid() {
            return mAid;
        }

        public boolean isCurrentActive() {
            return mIsCurrentActive;
        }

        public String getPath() {
            return mPath;
        }

        public int getFdnStatus() {
            return mFdnStatus;
        }

        public void setFdnStatus(int status) {
            mFdnStatus = status;
        }

        public int getPin1State() {
            return mPin1State;
        }

        public void setPin1State(int state) {
            mPin1State = state;
        }

        public String getImsi() {
            return mMcc + mMnc + mMsin;
        }

        public void setImsi(String mcc, String mnc, String msin) {
            setMcc(mcc);
            setMnc(mnc);
            setMsin(msin);
        }

        public String getMcc() {
            return mMcc;
        }

        public void setMcc(String mcc) {
            mMcc = mcc;
        }

        public String getMnc() {
            return mMnc;
        }

        public void setMnc(String mnc) {
            mMnc = mnc;
        }

        public String getMsin() {
            return mMsin;
        }

        public void setMsin(String msin) {
            mMsin = msin;
        }

        public String getIccidInfo() {
            return mIccid[EF_INFO_DATA];
        }

        public void setIccidInfo(String info) {
            mIccid[EF_INFO_DATA] = info;
        }

        public String getIccid() {
            return mIccid[EF_BINARY_DATA];
        }

        public void setIccid(String iccid) {
            mIccid[EF_BINARY_DATA] = iccid;
        }

        public String getSpn() {
            return mSpn;
        }

        public void setSpn(String spn) {
            mSpn = spn;
        }

        public String getGid1() {
            return mGid1;
        }

        public void setGid1(String gid) {
            mGid1 = gid;
        }

        public String getGid2() {
            return mGid2;
        }

        public void setGid2(String gid) {
            mGid2 = gid;
        }
    }

    public MockSimService(Context context, int slotId) {
        mContext = context;

        if (slotId >= MOCK_SIM_SLOT_MAX) {
            Log.e(
                    TAG,
                    "Invalid slot id("
                            + slotId
                            + "). Using default slot id("
                            + MOCK_SIM_DEFAULT_SLOTID
                            + ").");
            slotId = MOCK_SIM_DEFAULT_SLOTID;
        }

        // Static mock SIM bootstrap: the slot always presents the fixed mock SIM card.
        initMockSimCard(slotId);
    }

    private void initMockSimCard(int slotId) {
        if (slotId > MockModemConfigInterface.MAX_NUM_OF_SIM_SLOT) {
            Log.e(
                    TAG,
                    "Physical slot id("
                            + slotId
                            + ") is invalid. Using default slot id("
                            + MOCK_SIM_DEFAULT_SLOTID
                            + ").");
            mPhysicalSlotId = MOCK_SIM_DEFAULT_SLOTID;
        } else {
            mPhysicalSlotId = slotId;
        }
        Log.i(TAG, "Static mock SIM bootstrap for physical slot[" + mPhysicalSlotId + "]");

        // Initiate slot status
        initMockSimSlot();

        // Load the static SIM card state
        loadMockSimCard();
    }

    private void initMockSimSlot() {
        switch (mPhysicalSlotId) {
            case MOCK_SIM_SLOT_1:
                mLogicalSlotId = DEFAULT_SIM1_LOGICAL_SLOT_ID;
                mSlotPortId = DEFAULT_SIM1_PORT_ID;
                mIsSlotPortActive = DEFAULT_SIM1_PORT_ACTIVE;
                mIsCardPresent = DEFAULT_SIM1_CARD_PRESENT;
                break;
        }
    }


    private boolean loadSimApp() {
        if (mSimAppList == null) {
            mSimAppList = new ArrayList<SimAppData>();
        } else {
            mSimAppList.clear();
        }

        // Static mock SIM bootstrap: one ready USIM application.
        SimAppData app = new SimAppData(0, MOCK_AID, MOCK_SIM_PATH, true);
        app.setMcc(MOCK_MCC);
        app.setMnc(MOCK_MNC);
        app.setMsin(MOCK_MSIN);
        app.setIccid(DEFAULT_SIM1_ICCID);
        app.setIccidInfo(MOCK_ICCID_INFO);
        app.setSpn(MOCK_SPN);
        app.setGid1(MOCK_GID1);
        app.setGid2(MOCK_GID2);
        app.setFdnStatus(0);
        app.setPin1State(PinState.DISABLED);
        mSimAppList.add(app);

        AppStatus appStatus = new AppStatus();
        appStatus.appType = AppStatus.APP_TYPE_USIM;
        appStatus.appState = AppStatus.APP_STATE_READY;
        appStatus.persoSubstate = PersoSubstate.UNKNOWN;
        appStatus.aidPtr = MOCK_AID;
        appStatus.appLabelPtr = "";
        appStatus.pin1Replaced = false;
        appStatus.pin1 = PinState.DISABLED;
        appStatus.pin2 = PinState.DISABLED;
        mSimApp = new AppStatus[] {appStatus};
        return true;
    }

    private boolean loadMockSimCard() {
        switch (mPhysicalSlotId) {
            case MOCK_SIM_SLOT_1:
                mATR = DEFAULT_SIM1_ATR;
                mEID = DEFAULT_SIM1_EID;
                mUniversalPinState = DEFAULT_SIM1_UNIVERSAL_PIN_STATE;
                break;
        }
        mIsCardPresent = true;
        return loadSimApp();
    }

    public boolean isSlotPortActive() {
        return mIsSlotPortActive;
    }

    public boolean isCardPresent() {
        return mIsCardPresent;
    }

    public int getNumOfSimPortInfo() {
        return DEFAULT_NUM_OF_SIM_PORT_INFO;
    }

    public int getPhysicalSlotId() {
        return mPhysicalSlotId;
    }

    public int getLogicalSlotId() {
        return mLogicalSlotId;
    }

    public int getSlotPortId() {
        return mSlotPortId;
    }

    public String getEID() {
        return mEID;
    }

    public String getATR() {
        return mATR;
    }

    public String getICCID() {
        String iccid = "";
        SimAppData activeSimAppData = getActiveSimAppData();

        if (activeSimAppData != null) {
            iccid = activeSimAppData.getIccid();
        }

        return iccid;
    }

    public int getUniversalPinState() {
        return mUniversalPinState;
    }

    // Static mock SIM bootstrap: the single ready USIM occupies the GSM/UMTS app index.
    public int getGsmAppIndex() {
        return DEFAULT_GSM_APP_IDX;
    }

    public int getCdmaAppIndex() {
        return DEFAULT_CDMA_APP_IDX;
    }

    public int getImsAppIndex() {
        return DEFAULT_IMS_APP_IDX;
    }

    public int getNumOfSimApp() {
        return (mSimApp == null) ? DEFAULT_NUM_OF_SIM_APP : mSimApp.length;
    }

    public AppStatus[] getSimApp() {
        return mSimApp;
    }

    public ArrayList<SimAppData> getSimAppList() {
        return mSimAppList;
    }

    public SimAppData getActiveSimAppData() {
        SimAppData activeSimAppData = null;

        for (int simAppIdx = 0; simAppIdx < mSimAppList.size(); simAppIdx++) {
            if (mSimAppList.get(simAppIdx).isCurrentActive()) {
                activeSimAppData = mSimAppList.get(simAppIdx);
                break;
            }
        }

        return activeSimAppData;
    }

    public String getMccMnc() {
        String mcc;
        String mnc;
        String result = "";
        SimAppData activeSimAppData = getActiveSimAppData();

        if (activeSimAppData != null) {
            mcc = activeSimAppData.getMcc();
            mnc = activeSimAppData.getMnc();
            if (mcc != null
                    && mcc.length() == 3
                    && mnc != null
                    && (mnc.length() == 2 || mnc.length() == 3)) {
                result = mcc + mnc;
            } else {
                Log.e(TAG, "Invalid Mcc or Mnc.");
            }
        }
        return result;
    }

    public String getImsi() {
        String imsi = "";
        String mccmnc;
        String msin;
        SimAppData activeSimAppData = getActiveSimAppData();

        if (activeSimAppData != null) {
            mccmnc = getMccMnc();
            msin = activeSimAppData.getMsin();
            if (mccmnc.length() > 0
                    && msin != null
                    && msin.length() > 0
                    && (mccmnc.length() + msin.length()) <= 15) {
                imsi = mccmnc + msin;
            } else {
                Log.e(TAG, "Invalid Imsi.");
            }
        }
        return imsi;
    }
}
