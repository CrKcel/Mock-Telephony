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

import static android.telephony.mockmodem.MockSimService.COMMAND_GET_RESPONSE;
import static android.telephony.mockmodem.MockSimService.COMMAND_READ_BINARY;
import static android.telephony.mockmodem.MockSimService.EF_GID1;
import static android.telephony.mockmodem.MockSimService.EF_GID2;
import static android.telephony.mockmodem.MockSimService.EF_ICCID;
import static android.telephony.mockmodem.MockSimService.EF_SPN;

import android.hardware.radio.RadioError;
import android.hardware.radio.RadioIndicationType;
import android.hardware.radio.RadioResponseInfo;
import android.hardware.radio.sim.CardStatus;
import android.hardware.radio.sim.IRadioSim;
import android.hardware.radio.sim.IRadioSimIndication;
import android.hardware.radio.sim.IRadioSimResponse;
import android.hardware.radio.sim.SimRefreshResult;
import android.os.AsyncResult;
import android.os.Handler;
import android.os.Message;
import android.os.RemoteException;
import android.telephony.mockmodem.MockModemConfigBase.SimInfoChangedResult;
import android.telephony.mockmodem.MockSimService.SimAppData;
import android.util.Log;

import java.util.ArrayList;
import java.util.Locale;

public class IRadioSimImpl extends IRadioSim.Stub {
    private static final String TAG = "MRSIM";
    private final MockModemService mService;
    private volatile IRadioSimResponse mRadioSimResponse;
    private volatile IRadioSimIndication mRadioSimIndication;
    private final MockModemConfigInterface[] mMockModemConfigInterfaces;
    private Object mCacheUpdateMutex;
    private final Handler mHandler;
    private int mSubId;

    // ***** Events
    static final int EVENT_SIM_CARD_STATUS_CHANGED = 1;
    static final int EVENT_SIM_APP_DATA_CHANGED = 2;
    static final int EVENT_SIM_INFO_CHANGED = 3;

    // ***** Cache of modem attributes/status
    private int mNumOfLogicalSim;
    private CardStatus mCardStatus;
    private ArrayList<SimAppData> mSimAppList = new ArrayList<>();

    public IRadioSimImpl(
            MockModemService service, MockModemConfigInterface[] interfaces, int instanceId) {
        Log.d(TAG, "Instantiated");

        this.mService = service;
        mMockModemConfigInterfaces = interfaces;
        mSubId = instanceId;
        mCardStatus = new CardStatus();
        mCacheUpdateMutex = new Object();
        mHandler = new IRadioSimHandler();
        mNumOfLogicalSim = mMockModemConfigInterfaces.length;

        // Register events
        mMockModemConfigInterfaces[mSubId].registerForCardStatusChanged(
                mHandler, EVENT_SIM_CARD_STATUS_CHANGED, null);

        // Register events
        mMockModemConfigInterfaces[mSubId].registerForSimAppDataChanged(
                mHandler, EVENT_SIM_APP_DATA_CHANGED, null);

        // Register events
        mMockModemConfigInterfaces[mSubId].registerForSimInfoChanged(
                mHandler, EVENT_SIM_INFO_CHANGED, null);
    }

    /** Handler class to handle callbacks */
    private final class IRadioSimHandler extends Handler {
        @Override
        public void handleMessage(Message msg) {
            AsyncResult ar;
            synchronized (mCacheUpdateMutex) {
                switch (msg.what) {
                    case EVENT_SIM_CARD_STATUS_CHANGED:
                        Log.d(TAG, "Received EVENT_SIM_CARD_STATUS_CHANGED");
                        ar = (AsyncResult) msg.obj;
                        if (ar != null && ar.exception == null) {
                            mCardStatus = (CardStatus) ar.result;
                            Log.i(TAG, "Sim card status: " + mCardStatus);
                            simStatusChanged();
                        } else {
                            Log.e(TAG, msg.what + " failure. Exception: " + ar.exception);
                        }
                        break;

                    case EVENT_SIM_APP_DATA_CHANGED:
                        Log.d(TAG, "Received EVENT_SIM_APP_DATA_CHANGED");
                        ar = (AsyncResult) msg.obj;
                        if (ar != null && ar.exception == null) {
                            // Keep mSimAppList non-null at all times: it is read
                            // without a guard by the binder-request methods.
                            ArrayList<SimAppData> newList = (ArrayList<SimAppData>) ar.result;
                            if (newList != null) {
                                mSimAppList = newList;
                                Log.i(TAG, "number of SIM app data: " + mSimAppList.size());
                            } else {
                                Log.e(TAG, "mSimAppList = null; keeping previous list");
                            }
                        } else {
                            Log.e(TAG, msg.what + " failure. Exception: " + ar.exception);
                        }
                        break;

                    case EVENT_SIM_INFO_CHANGED:
                        ar = (AsyncResult) msg.obj;
                        if (ar != null && ar.exception == null) {
                            SimInfoChangedResult simInfoChangeResult =
                                    (SimInfoChangedResult) ar.result;
                            Log.d(TAG, "Received EVENT_SIM_INFO_CHANGED: " + simInfoChangeResult);
                            SimRefreshResult simRefreshResult = new SimRefreshResult();
                            switch (simInfoChangeResult.mSimInfoType) {
                                case SimInfoChangedResult.SIM_INFO_TYPE_MCC_MNC:
                                case SimInfoChangedResult.SIM_INFO_TYPE_IMSI:
                                    if (simRefreshResult != null) {
                                        simRefreshResult.type =
                                                SimRefreshResult.TYPE_SIM_FILE_UPDATE;
                                        simRefreshResult.efId = simInfoChangeResult.mEfId;
                                        simRefreshResult.aid = simInfoChangeResult.mAid;
                                        simRefresh(simRefreshResult);
                                    }
                                    break;
                            }
                        } else {
                            Log.e(TAG, msg.what + " failure. Exception: " + ar.exception);
                        }
                        break;
                }
            }
        }
    }

    // Implementation of IRadioSim functions
    @Override
    public void setResponseFunctions(
            IRadioSimResponse radioSimResponse, IRadioSimIndication radioSimIndication) {
        Log.d(TAG, "setResponseFunctions");
        mRadioSimResponse = radioSimResponse;
        mRadioSimIndication = radioSimIndication;
        mService.registerRadioInterface(
                MockModemService.RADIO_INTERFACE_SIM, radioSimResponse.asBinder());
    }

    @Override
    public void responseAcknowledgement() {
        Log.d(TAG, "responseAcknowledgement");
        // Acknowledged; the module's responses are oneway and need no follow-up.
    }

    @Override
    public void areUiccApplicationsEnabled(int serial) {
        Log.d(TAG, "areUiccApplicationsEnabled");

        boolean enabled = true;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.areUiccApplicationsEnabledResponse(rsp, enabled);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to areUiccApplicationsEnabled from AIDL. Exception" + ex);
        }
    }

    @Override
    public void changeIccPin2ForApp(int serial, String oldPin2, String newPin2, String aid) {
        Log.d(TAG, "changeIccPin2ForApp");

        int remainingRetries = 3;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.changeIccPin2ForAppResponse(rsp, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to changeIccPin2ForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void changeIccPinForApp(int serial, String oldPin, String newPin, String aid) {
        Log.d(TAG, "changeIccPinForApp");

        int remainingRetries = 3;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.changeIccPinForAppResponse(rsp, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to changeIccPinForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void enableUiccApplications(int serial, boolean enable) {
        Log.d(TAG, "enableUiccApplications");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.enableUiccApplicationsResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to enableUiccApplications from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getAllowedCarriers(int serial) {
        Log.d(TAG, "getAllowedCarriers");

        android.hardware.radio.sim.CarrierRestrictions carriers =
                new android.hardware.radio.sim.CarrierRestrictions();
        int multiSimPolicy = android.hardware.radio.sim.SimLockMultiSimPolicy.NO_MULTISIM_POLICY;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.getAllowedCarriersResponse(rsp, carriers, multiSimPolicy);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getAllowedCarriers from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getCdmaSubscription(int serial) {
        Log.d(TAG, "getCdmaSubscription");

        String mdn = "";
        String hSid = "";
        String hNid = "";
        String min = "";
        String prl = "";

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.getCdmaSubscriptionResponse(rsp, mdn, hSid, hNid, min, prl);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getCdmaSubscription from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getCdmaSubscriptionSource(int serial) {
        Log.d(TAG, "getCdmaSubscriptionSource");

        int source = 0; // CdmaSubscriptionSource.RUIM_SIM

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.getCdmaSubscriptionSourceResponse(rsp, source);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getCdmaSubscriptionSource from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getFacilityLockForApp(
            int serial, String facility, String password, int serviceClass, String appId) {
        Log.d(TAG, "getFacilityLockForApp");
        int numOfSimApp = mSimAppList.size();
        int responseError = RadioError.NONE;
        int simAppIdx;
        boolean isHandled = false;
        boolean isFacilitySupport = true;
        int responseData = -1;

        synchronized (mCacheUpdateMutex) {
            // serviceClass is intentionally ignored: the static bootstrap exposes
            // a fixed absent-SIM app model, so FD/SC queries are answered by AID match.
            for (simAppIdx = 0;
                    simAppIdx < numOfSimApp && isFacilitySupport && !isHandled;
                    simAppIdx++) {
                switch (facility) {
                    case "FD": // FDN status query
                        if (appId.equals(mSimAppList.get(simAppIdx).getAid())) {
                            responseData = mSimAppList.get(simAppIdx).getFdnStatus();
                            isHandled = true;
                        }
                        break;
                    case "SC": // PIN1 status query
                        if (appId.equals(mSimAppList.get(simAppIdx).getAid())) {
                            responseData = mSimAppList.get(simAppIdx).getPin1State();
                            isHandled = true;
                        }
                        break;
                    default:
                        isFacilitySupport = false;
                        break;
                }
            }
        }

        if (!isHandled) {
            Log.e(TAG, "Not support sim application aid = " + appId);
            responseError = RadioError.NO_SUCH_ELEMENT;
        } else if (!isFacilitySupport) {
            Log.e(TAG, "Not support facility = " + facility);
            responseError = RadioError.REQUEST_NOT_SUPPORTED;
        } else if (responseData == -1) {
            responseError = RadioError.INTERNAL_ERR;
        }

        RadioResponseInfo rsp = mService.makeSolRsp(serial, responseError);
        try {
            mRadioSimResponse.getFacilityLockForAppResponse(rsp, responseData);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getFacilityLockForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getIccCardStatus(int serial) {
        Log.d(TAG, "getIccCardStatus");
        CardStatus cardStatus;

        synchronized (mCacheUpdateMutex) {
            cardStatus = mCardStatus;
        }

        RadioResponseInfo rsp = mService.makeSolRsp(serial);
        try {
            mRadioSimResponse.getIccCardStatusResponse(rsp, cardStatus);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getIccCardStatus from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getImsiForApp(int serial, String aid) {
        Log.d(TAG, "getImsiForApp");
        String imsi = "";
        int numOfSimApp = mSimAppList.size();
        int responseError = RadioError.NONE;
        int simAppIdx;
        boolean isHandled;

        synchronized (mCacheUpdateMutex) {
            for (simAppIdx = 0, isHandled = false;
                    simAppIdx < numOfSimApp && !isHandled;
                    simAppIdx++) {
                if (aid.equals(mSimAppList.get(simAppIdx).getAid())) {
                    imsi = mSimAppList.get(simAppIdx).getImsi();
                    isHandled = true;
                }
            }
        }

        if (!isHandled) {
            Log.e(TAG, "Not support sim application aid = " + aid);
            responseError = RadioError.NO_SUCH_ELEMENT;
        }

        RadioResponseInfo rsp = mService.makeSolRsp(serial, responseError);
        try {
            mRadioSimResponse.getImsiForAppResponse(rsp, imsi);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getImsiForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getSimPhonebookCapacity(int serial) {
        Log.d(TAG, "getSimPhonebookCapacity");

        android.hardware.radio.sim.PhonebookCapacity capacity =
                new android.hardware.radio.sim.PhonebookCapacity();

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.getSimPhonebookCapacityResponse(rsp, capacity);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getSimPhonebookCapacity from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getSimPhonebookRecords(int serial) {
        Log.d(TAG, "getSimPhonebookRecords");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.getSimPhonebookRecordsResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getSimPhonebookRecords from AIDL. Exception" + ex);
        }
    }

    @Override
    public void iccCloseLogicalChannel(int serial, int channelId) {
        Log.d(TAG, "iccCloseLogicalChannel");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.iccCloseLogicalChannelResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to iccCloseLogicalChannel from AIDL. Exception" + ex);
        }
    }

    private String encodeBcdString(String str) {
        StringBuffer bcdString = new StringBuffer();

        if (str.length() % 2 != 0) {
            Log.d(TAG, "Invalid string(" + str + ") for Bcd format");
            return "";
        }

        for (int i = 0; i < str.length(); i += 2) {
            bcdString.append(str.substring(i + 1, i + 2));
            bcdString.append(str.substring(i, i + 1));
        }

        return bcdString.toString();
    }

    /** Hex-encode the UTF-8 bytes of the given text (used for EF_SPN payload). */
    private String encodeHexString(String str) {
        StringBuilder hex = new StringBuilder();
        for (byte b : str.getBytes(java.nio.charset.StandardCharsets.UTF_8)) {
            hex.append(String.format(Locale.ROOT, "%02x", b));
        }
        return hex.toString();
    }

    /** Return the configured binary payload of the given EF, or an empty string when absent. */
    private String getEfData(int simAppIdx, int fileId) {
        SimAppData app = mSimAppList.get(simAppIdx);
        switch (fileId) {
            case EF_SPN:
                return encodeHexString(app.getSpn());
            case EF_GID1:
                return app.getGid1();
            case EF_GID2:
                return app.getGid2();
            default:
                return "";
        }
    }

    /** Build the 15-byte transparent-EF GET_RESPONSE metadata, sized for the given data length. */
    private String buildEfFileInfo(int fileId, int dataLen) {
        return String.format(Locale.ROOT, "0000%04x%04x040000ffff01020002", dataLen, fileId);
    }

    private int getIccIoResult(
            android.hardware.radio.sim.IccIoResult iccIoResult,
            int command,
            int fileId,
            String path,
            int p1,
            int p2,
            int p3,
            String aid) {
        int numOfSimApp = mSimAppList.size();
        int simAppIdx;
        boolean foundAid;
        int responseError = RadioError.GENERIC_FAILURE;

        if (iccIoResult == null) {
            return responseError;
        }

        synchronized (mCacheUpdateMutex) {
            for (simAppIdx = 0, foundAid = false; simAppIdx < numOfSimApp; simAppIdx++) {
                if (aid.equals(mSimAppList.get(simAppIdx).getAid())) {
                    foundAid = true;
                    break;
                }
            }

            if (!foundAid) {
                Log.e(TAG, "Not support sim application aid = " + aid);
                iccIoResult.sw1 = 0x6A;
                iccIoResult.sw2 = 0x82;
            } else {
                switch (fileId) {
                    case EF_ICCID:
                        if (command == COMMAND_READ_BINARY) {
                            String bcdIccid =
                                    encodeBcdString(mSimAppList.get(simAppIdx).getIccid());
                            iccIoResult.simResponse = bcdIccid;
                            Log.d(TAG, "Get IccIo result: ICCID data returned");
                            iccIoResult.sw1 = 0x90;
                            responseError = RadioError.NONE;
                        } else if (command == COMMAND_GET_RESPONSE) {
                            iccIoResult.simResponse = mSimAppList.get(simAppIdx).getIccidInfo();
                            Log.d(TAG, "Get IccIo result: ICCID metadata returned");
                            iccIoResult.sw1 = 0x90;
                            responseError = RadioError.NONE;
                        } else {
                            Log.d(
                                    TAG,
                                    "Command("
                                            + command
                                            + ") not support for file id = 0x"
                                            + Integer.toHexString(fileId));
                            iccIoResult.sw1 = 0x6A;
                            iccIoResult.sw2 = 0x82;
                        }
                        break;
                    case EF_SPN:
                    case EF_GID1:
                    case EF_GID2:
                        if (command == COMMAND_READ_BINARY) {
                            iccIoResult.simResponse = getEfData(simAppIdx, fileId);
                            iccIoResult.sw1 = 0x90;
                            responseError = RadioError.NONE;
                        } else if (command == COMMAND_GET_RESPONSE) {
                            iccIoResult.simResponse =
                                    buildEfFileInfo(
                                            fileId, getEfData(simAppIdx, fileId).length() / 2);
                            iccIoResult.sw1 = 0x90;
                            responseError = RadioError.NONE;
                        } else {
                            Log.d(
                                    TAG,
                                    "Command("
                                            + command
                                            + ") not support for file id = 0x"
                                            + Integer.toHexString(fileId));
                            iccIoResult.sw1 = 0x6A;
                            iccIoResult.sw2 = 0x82;
                        }
                        break;
                    default:
                        Log.d(TAG, "Not find EF file id = 0x" + Integer.toHexString(fileId));
                        iccIoResult.sw1 = 0x6A;
                        iccIoResult.sw2 = 0x82;
                        break;
                }
            }
        }

        return responseError;
    }

    @Override
    public void iccIoForApp(int serial, android.hardware.radio.sim.IccIo iccIo) {
        Log.d(TAG, "iccIoForApp");
        int responseError = RadioError.NONE;
        android.hardware.radio.sim.IccIoResult iccIoResult =
                new android.hardware.radio.sim.IccIoResult();

        switch (iccIo.command) {
            case COMMAND_READ_BINARY:
            case COMMAND_GET_RESPONSE:
                responseError =
                        getIccIoResult(
                                iccIoResult,
                                iccIo.command,
                                iccIo.fileId,
                                iccIo.path,
                                iccIo.p1,
                                iccIo.p2,
                                iccIo.p3,
                                iccIo.aid);
                break;
            default:
                responseError = RadioError.REQUEST_NOT_SUPPORTED;
                break;
        }

        RadioResponseInfo rsp = mService.makeSolRsp(serial, responseError);
        try {
            mRadioSimResponse.iccIoForAppResponse(rsp, iccIoResult);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to iccIoForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void iccOpenLogicalChannel(int serial, String aid, int p2) {
        Log.d(TAG, "iccOpenLogicalChannel");
        int channelId = 0;
        byte[] selectResponse = new byte[0];

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.iccOpenLogicalChannelResponse(rsp, channelId, selectResponse);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to iccOpenLogicalChannel from AIDL. Exception" + ex);
        }
    }

    @Override
    public void iccTransmitApduBasicChannel(
            int serial, android.hardware.radio.sim.SimApdu message) {
        Log.d(TAG, "iccTransmitApduBasicChannel");
        android.hardware.radio.sim.IccIoResult iccIoResult =
                new android.hardware.radio.sim.IccIoResult();

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.iccTransmitApduBasicChannelResponse(rsp, iccIoResult);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to iccTransmitApduBasicChannel from AIDL. Exception" + ex);
        }
    }

    @Override
    public void iccTransmitApduLogicalChannel(
            int serial, android.hardware.radio.sim.SimApdu message) {
        Log.d(TAG, "iccTransmitApduLogicalChannel");
        android.hardware.radio.sim.IccIoResult iccIoResult =
                new android.hardware.radio.sim.IccIoResult();

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.iccTransmitApduLogicalChannelResponse(rsp, iccIoResult);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to iccTransmitApduLogicalChannel from AIDL. Exception" + ex);
        }
    }

    @Override
    public void reportStkServiceIsRunning(int serial) {
        Log.d(TAG, "reportStkServiceIsRunning");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.reportStkServiceIsRunningResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to reportStkServiceIsRunning from AIDL. Exception" + ex);
        }
    }

    @Override
    public void requestIccSimAuthentication(
            int serial, int authContext, String authData, String aid) {
        Log.d(TAG, "requestIccSimAuthentication");
        android.hardware.radio.sim.IccIoResult iccIoResult =
                new android.hardware.radio.sim.IccIoResult();

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.requestIccSimAuthenticationResponse(rsp, iccIoResult);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to requestIccSimAuthentication from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendEnvelope(int serial, String contents) {
        Log.d(TAG, "sendEnvelope");
        String commandResponse = "";

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.sendEnvelopeResponse(rsp, commandResponse);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendEnvelope from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendEnvelopeWithStatus(int serial, String contents) {
        Log.d(TAG, "sendEnvelopeWithStatus");
        android.hardware.radio.sim.IccIoResult iccIoResult =
                new android.hardware.radio.sim.IccIoResult();

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.sendEnvelopeWithStatusResponse(rsp, iccIoResult);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendEnvelopeWithStatus from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendTerminalResponseToSim(int serial, String contents) {
        Log.d(TAG, "sendTerminalResponseToSim");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.sendTerminalResponseToSimResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendTerminalResponseToSim from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setAllowedCarriers(
            int serial,
            android.hardware.radio.sim.CarrierRestrictions carriers,
            int multiSimPolicy) {
        Log.d(TAG, "setAllowedCarriers");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.setAllowedCarriersResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setAllowedCarriers from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setCarrierInfoForImsiEncryption(
            int serial, android.hardware.radio.sim.ImsiEncryptionInfo imsiEncryptionInfo) {
        Log.d(TAG, "setCarrierInfoForImsiEncryption");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.setCarrierInfoForImsiEncryptionResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setCarrierInfoForImsiEncryption from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setCdmaSubscriptionSource(int serial, int cdmaSub) {
        Log.d(TAG, "setCdmaSubscriptionSource");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.setCdmaSubscriptionSourceResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setCdmaSubscriptionSource from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setFacilityLockForApp(
            int serial,
            String facility,
            boolean lockState,
            String password,
            int serviceClass,
            String appId) {
        Log.d(TAG, "setFacilityLockForApp");
        int retry = 10;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.setFacilityLockForAppResponse(rsp, retry);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setFacilityLockForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setSimCardPower(int serial, int powerUp) {
        Log.d(TAG, "setSimCardPower");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.setSimCardPowerResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setSimCardPower from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setUiccSubscription(int serial, android.hardware.radio.sim.SelectUiccSub uiccSub) {
        Log.d(TAG, "setUiccSubscription");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.setUiccSubscriptionResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setUiccSubscription from AIDL. Exception" + ex);
        }
    }

    @Override
    public void supplyIccPin2ForApp(int serial, String pin2, String aid) {
        Log.d(TAG, "supplyIccPin2ForApp");
        int remainingRetries = 10;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.supplyIccPin2ForAppResponse(rsp, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to supplyIccPin2ForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void supplyIccPinForApp(int serial, String pin, String aid) {
        Log.d(TAG, "supplyIccPinForApp");
        int remainingRetries = 10;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.supplyIccPinForAppResponse(rsp, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to supplyIccPinForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void supplyIccPuk2ForApp(int serial, String puk2, String pin2, String aid) {
        Log.d(TAG, "supplyIccPuk2ForApp");
        int remainingRetries = 10;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.supplyIccPuk2ForAppResponse(rsp, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to supplyIccPuk2ForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void supplyIccPukForApp(int serial, String puk, String pin, String aid) {
        Log.d(TAG, "supplyIccPukForApp");
        int remainingRetries = 10;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.supplyIccPukForAppResponse(rsp, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to supplyIccPukForApp from AIDL. Exception" + ex);
        }
    }

    @Override
    public void supplySimDepersonalization(int serial, int persoType, String controlKey) {
        Log.d(TAG, "supplySimDepersonalization");
        int remainingRetries = 10;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.supplySimDepersonalizationResponse(
                    rsp, persoType, remainingRetries);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to supplySimDepersonalization from AIDL. Exception" + ex);
        }
    }

    @Override
    public void updateSimPhonebookRecords(
            int serial, android.hardware.radio.sim.PhonebookRecordInfo recordInfo) {
        Log.d(TAG, "updateSimPhonebookRecords");
        int updatedRecordIndex = 0;

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioSimResponse.updateSimPhonebookRecordsResponse(rsp, updatedRecordIndex);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to updateSimPhonebookRecords from AIDL. Exception" + ex);
        }
    }


    public void simRefresh(SimRefreshResult refreshResult) {
        Log.d(TAG, "simRefresh");

        if (mRadioSimIndication != null) {
            try {
                mRadioSimIndication.simRefresh(RadioIndicationType.UNSOLICITED, refreshResult);
            } catch (RemoteException | NullPointerException ex) {
                Log.e(TAG, "Failed to simRefresh from AIDL. Exception" + ex);
            }
        } else {
            Log.e(TAG, "null mRadioSimIndication");
        }
    }

    public void simStatusChanged() {
        Log.d(TAG, "simStatusChanged");

        if (mRadioSimIndication != null) {
            try {
                mRadioSimIndication.simStatusChanged(RadioIndicationType.UNSOLICITED);
            } catch (RemoteException | NullPointerException ex) {
                Log.e(TAG, "Failed to simStatusChanged from AIDL. Exception" + ex);
            }
        } else {
            Log.e(TAG, "null mRadioSimIndication");
        }
    }


    @Override
    public String getInterfaceHash() {
        return IRadioSim.HASH;
    }

    @Override
    public int getInterfaceVersion() {
        return IRadioSim.VERSION;
    }
}
