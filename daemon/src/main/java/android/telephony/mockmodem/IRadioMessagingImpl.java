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

import android.hardware.radio.RadioError;
import android.hardware.radio.RadioIndicationType;
import android.hardware.radio.RadioResponseInfo;
import android.hardware.radio.messaging.IRadioMessaging;
import android.hardware.radio.messaging.IRadioMessagingIndication;
import android.hardware.radio.messaging.IRadioMessagingResponse;
import android.os.RemoteException;
import android.util.Log;

public class IRadioMessagingImpl extends IRadioMessaging.Stub {
    private static final String TAG = "MRMSG";

    private final MockModemService mService;
    private volatile IRadioMessagingResponse mRadioMessagingResponse;
    private volatile IRadioMessagingIndication mRadioMessagingIndication;

    public IRadioMessagingImpl(MockModemService service) {
        Log.d(TAG, "Instantiated");

        this.mService = service;
    }

    // Implementation of IRadioMessaging functions
    @Override
    public void setResponseFunctions(
            IRadioMessagingResponse radioMessagingResponse,
            IRadioMessagingIndication radioMessagingIndication) {
        Log.d(TAG, "setResponseFunctions");
        mRadioMessagingResponse = radioMessagingResponse;
        mRadioMessagingIndication = radioMessagingIndication;
        mService.registerRadioInterface(
                MockModemService.RADIO_INTERFACE_MESSAGING,
                radioMessagingResponse.asBinder());
    }

    @Override
    public void acknowledgeIncomingGsmSmsWithPdu(int serial, boolean success, String ackPdu) {
        Log.d(TAG, "acknowledgeIncomingGsmSmsWithPdu");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.acknowledgeIncomingGsmSmsWithPduResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to acknowledgeIncomingGsmSmsWithPdu from AIDL. Exception" + ex);
        }
    }

    @Override
    public void acknowledgeLastIncomingCdmaSms(
            int serial, android.hardware.radio.messaging.CdmaSmsAck smsAck) {
        Log.d(TAG, "acknowledgeLastIncomingCdmaSms");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.acknowledgeLastIncomingCdmaSmsResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to acknowledgeLastIncomingCdmaSms from AIDL. Exception" + ex);
        }
    }

    @Override
    public void acknowledgeLastIncomingGsmSms(int serial, boolean success, int cause) {
        Log.d(TAG, "acknowledgeLastIncomingGsmSms");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.acknowledgeLastIncomingGsmSmsResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to acknowledgeLastIncomingGsmSms from AIDL. Exception" + ex);
        }
    }

    @Override
    public void deleteSmsOnRuim(int serial, int index) {
        Log.d(TAG, "deleteSmsOnRuim");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.deleteSmsOnRuimResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to deleteSmsOnRuim from AIDL. Exception" + ex);
        }
    }

    @Override
    public void deleteSmsOnSim(int serial, int index) {
        Log.d(TAG, "deleteSmsOnSim");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.deleteSmsOnSimResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to deleteSmsOnSim from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getCdmaBroadcastConfig(int serial) {
        Log.d(TAG, "getCdmaBroadcastConfig");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.getCdmaBroadcastConfigResponse(
                    rsp, new android.hardware.radio.messaging.CdmaBroadcastSmsConfigInfo[0]);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getCdmaBroadcastConfig from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getGsmBroadcastConfig(int serial) {
        Log.d(TAG, "getGsmBroadcastConfig");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.getGsmBroadcastConfigResponse(
                    rsp, new android.hardware.radio.messaging.GsmBroadcastSmsConfigInfo[0]);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getGsmBroadcastConfig from AIDL. Exception" + ex);
        }
    }

    @Override
    public void getSmscAddress(int serial) {
        Log.d(TAG, "getSmscAddress");

        String smsc = "";
        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.getSmscAddressResponse(rsp, smsc);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to getSmscAddress from AIDL. Exception" + ex);
        }
    }

    @Override
    public void reportSmsMemoryStatus(int serial, boolean available) {
        Log.d(TAG, "reportSmsMemoryStatus");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.reportSmsMemoryStatusResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to reportSmsMemoryStatus from AIDL. Exception" + ex);
        }
    }

    @Override
    public void responseAcknowledgement() {
        Log.d(TAG, "responseAcknowledgement");
        // Acknowledged; the module's responses are oneway and need no follow-up.
    }

    @Override
    public void sendCdmaSms(int serial, android.hardware.radio.messaging.CdmaSmsMessage sms) {
        Log.d(TAG, "sendCdmaSms");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.sendCdmaSmsResponse(rsp, makeFailedSmsResult());
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendCdmaSms from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendCdmaSmsExpectMore(
            int serial, android.hardware.radio.messaging.CdmaSmsMessage sms) {
        Log.d(TAG, "sendCdmaSmsExpectMore");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.sendCdmaSmsExpectMoreResponse(rsp, makeFailedSmsResult());
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendCdmaSmsExpectMore from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendImsSms(int serial, android.hardware.radio.messaging.ImsSmsMessage message) {
        Log.d(TAG, "sendImsSms");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.sendImsSmsResponse(rsp, makeFailedSmsResult());
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendImsSms from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendSms(int serial, android.hardware.radio.messaging.GsmSmsMessage message) {
        Log.d(TAG, "sendSms");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.sendSmsResponse(rsp, makeFailedSmsResult());
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendSms from AIDL. Exception" + ex);
        }
    }

    @Override
    public void sendSmsExpectMore(
            int serial, android.hardware.radio.messaging.GsmSmsMessage message) {
        Log.d(TAG, "sendSmsExpectMore");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.sendSmsExpectMoreResponse(rsp, makeFailedSmsResult());
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to sendSmsExpectMore from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setCdmaBroadcastActivation(int serial, boolean activate) {
        Log.d(TAG, "setCdmaBroadcastActivation");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.setCdmaBroadcastActivationResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setCdmaBroadcastActivation from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setCdmaBroadcastConfig(
            int serial, android.hardware.radio.messaging.CdmaBroadcastSmsConfigInfo[] configInfo) {
        Log.d(TAG, "setCdmaBroadcastConfig");

        // CB configuration is not supported by the static bootstrap: fail
        // deterministically instead of acking a config that is never applied.
        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.setCdmaBroadcastConfigResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setCdmaBroadcastConfig from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setGsmBroadcastActivation(int serial, boolean activate) {
        Log.d(TAG, "setGsmBroadcastActivation");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.setGsmBroadcastActivationResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setGsmBroadcastActivation from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setGsmBroadcastConfig(
            int serial, android.hardware.radio.messaging.GsmBroadcastSmsConfigInfo[] configInfo) {
        Log.d(TAG, "setGsmBroadcastConfig");

        // CB configuration is not supported by the static bootstrap: fail
        // deterministically instead of acking a config that is never applied.
        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.setGsmBroadcastConfigResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setGsmBroadcastConfig from AIDL. Exception" + ex);
        }
    }

    @Override
    public void setSmscAddress(int serial, String smsc) {
        Log.d(TAG, "setSmscAddress");

        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.setSmscAddressResponse(rsp);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to setSmscAddress from AIDL. Exception" + ex);
        }
    }

    @Override
    public void writeSmsToRuim(
            int serial, android.hardware.radio.messaging.CdmaSmsWriteArgs cdmaSms) {
        Log.d(TAG, "writeSmsToRuim");

        int index = 0;
        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.writeSmsToRuimResponse(rsp, index);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to writeSmsToRuim from AIDL. Exception" + ex);
        }
    }

    @Override
    public void writeSmsToSim(
            int serial, android.hardware.radio.messaging.SmsWriteArgs smsWriteArgs) {
        Log.d(TAG, "writeSmsToSim");

        int index = 0;
        RadioResponseInfo rsp = mService.makeSolRsp(serial, RadioError.REQUEST_NOT_SUPPORTED);
        try {
            mRadioMessagingResponse.writeSmsToSimResponse(rsp, index);
        } catch (RemoteException | NullPointerException ex) {
            Log.e(TAG, "Failed to writeSmsToSim from AIDL. Exception" + ex);
        }
    }


    @Override
    public String getInterfaceHash() {
        return IRadioMessaging.HASH;
    }

    @Override
    public int getInterfaceVersion() {
        return IRadioMessaging.VERSION;
    }

    private static android.hardware.radio.messaging.SendSmsResult makeFailedSmsResult() {
        android.hardware.radio.messaging.SendSmsResult result =
                new android.hardware.radio.messaging.SendSmsResult();
        result.messageRef = 0;
        result.ackPDU = "";
        result.errorCode = 0;
        return result;
    }

}
