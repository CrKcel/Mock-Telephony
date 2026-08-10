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

import android.content.Context;
import android.hardware.radio.RadioError;
import android.hardware.radio.RadioResponseInfo;
import android.hardware.radio.RadioResponseType;
import android.os.IBinder;
import android.os.RemoteException;
import android.telephony.TelephonyManager;
import android.util.Log;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

public class MockModemService {
    public interface ReadinessListener {
        void onReadinessChanged(boolean ready);
    }

    private static final String TAG = "MockModemService";
    private static final String RESOURCE_PACKAGE_NAME = "android";

    public static final int TEST_TIMEOUT_MS = 30000;
    public static final String IRADIOCONFIG_INTERFACE = "android.telephony.mockmodem.iradioconfig";
    public static final String IRADIOMODEM_INTERFACE = "android.telephony.mockmodem.iradiomodem";
    public static final String IRADIOSIM_INTERFACE = "android.telephony.mockmodem.iradiosim";
    public static final String IRADIONETWORK_INTERFACE =
            "android.telephony.mockmodem.iradionetwork";
    public static final String IRADIODATA_INTERFACE = "android.telephony.mockmodem.iradiodata";
    public static final String IRADIOMESSAGING_INTERFACE =
            "android.telephony.mockmodem.iradiomessaging";
    public static final String IRADIOVOICE_INTERFACE = "android.telephony.mockmodem.iradiovoice";
    public static final String PHONE_ID = "phone_id";

    private static Context sContext;
    private static MockModemConfigInterface[] sMockModemConfigInterfaces;
    private static IRadioConfigImpl sIRadioConfigImpl;
    private static IRadioModemImpl sIRadioModemImpl;
    private static IRadioSimImpl sIRadioSimImpl;
    private static IRadioNetworkImpl sIRadioNetworkImpl;
    private static IRadioDataImpl sIRadioDataImpl;
    private static IRadioMessagingImpl sIRadioMessagingImpl;
    private static IRadioVoiceImpl sIRadioVoiceImpl;

    public static final byte PHONE_ID_0 = 0x00;
    public static final byte PHONE_ID_1 = 0x01;

    public static final int RADIO_INTERFACE_CONFIG = 0;
    public static final int RADIO_INTERFACE_MODEM = 1;
    public static final int RADIO_INTERFACE_SIM = 2;
    public static final int RADIO_INTERFACE_NETWORK = 3;
    public static final int RADIO_INTERFACE_DATA = 4;
    public static final int RADIO_INTERFACE_MESSAGING = 5;
    public static final int RADIO_INTERFACE_VOICE = 6;
    private static final int STANDALONE_RADIO_INTERFACE_COUNT = 7;

    private TelephonyManager mTelephonyManager;
    private int mNumOfSim;
    private int mNumOfPhone;
    private static final int DEFAULT_SUB_ID = 0;

    private final Object mInterfaceLock = new Object();
    private final Map<Integer, IBinder> mInterfaceBinders = new HashMap<>();
    private final Map<Integer, IBinder.DeathRecipient> mDeathRecipients = new HashMap<>();
    private int mConnectionGeneration = 1;
    private boolean mAllInterfacesReady;
    private volatile boolean mInitialized;
    private volatile ReadinessListener mReadinessListener;
    private int mRadioInterfaceCount = STANDALONE_RADIO_INTERFACE_COUNT;
    /**
     * Standalone initialization for the root app_process daemon.  There is
     * no Android application context; SIM profiles are read from disk and
     * the modem/phone counts are fixed at one.
     */
    public void init() {
        initInternal(null);
    }

    /** Create binders for an Android application Service without global registration. */
    public void initForApplication(Context context) {
        initInternal(context);
    }

    private void initInternal(Context context) {
        Log.d(TAG, "Mock Modem Service Created");

        sContext = context;
        mTelephonyManager = context == null ? null : context.getSystemService(TelephonyManager.class);
        mNumOfSim = 1;
        mNumOfPhone = 1;
        mRadioInterfaceCount = STANDALONE_RADIO_INTERFACE_COUNT;
        Log.d(TAG, "Support number of phone = " + mNumOfPhone + ", number of SIM = " + mNumOfSim);

        sMockModemConfigInterfaces = new MockModemConfigBase[mNumOfPhone];
        for (int i = 0; i < mNumOfPhone; i++) {
            sMockModemConfigInterfaces[i] =
                    new MockModemConfigBase(sContext, i, mNumOfSim, mNumOfPhone);
        }

        sIRadioConfigImpl = new IRadioConfigImpl(this, sMockModemConfigInterfaces, DEFAULT_SUB_ID);
        // DSDS is intentionally out of scope: the standalone bootstrap exposes
        // exactly one phone and one logical SIM.
        sIRadioModemImpl = new IRadioModemImpl(this, sMockModemConfigInterfaces, DEFAULT_SUB_ID);
        sIRadioSimImpl = new IRadioSimImpl(this, sMockModemConfigInterfaces, DEFAULT_SUB_ID);
        sIRadioNetworkImpl =
                new IRadioNetworkImpl(this, sMockModemConfigInterfaces, DEFAULT_SUB_ID);
        sIRadioDataImpl = new IRadioDataImpl(this);
        sIRadioMessagingImpl = new IRadioMessagingImpl(this);
        sIRadioVoiceImpl = new IRadioVoiceImpl(this);
    }

    /** Add an optional interface to the current readiness generation when it is bound. */
    public void requireRadioInterface(int interfaceId) {
        boolean becameNotReady = false;
        synchronized (mInterfaceLock) {
            int requiredCount = interfaceId + 1;
            if (requiredCount <= mRadioInterfaceCount) {
                return;
            }
            mRadioInterfaceCount = requiredCount;
            if (mAllInterfacesReady && mInterfaceBinders.size() < mRadioInterfaceCount) {
                mAllInterfacesReady = false;
                mConnectionGeneration++;
                becameNotReady = true;
            }
        }
        if (becameNotReady) {
            notifyReadiness(false);
        }
    }

    public void setReadinessListener(ReadinessListener listener) {
        mReadinessListener = listener;
    }

    public void registerRadioInterface(int interfaceId, IBinder responseBinder) {
        if (responseBinder == null) {
            Log.e(TAG, "Ignoring null response binder for interface " + interfaceId);
            return;
        }

        boolean publishState = false;
        synchronized (mInterfaceLock) {
            IBinder oldBinder = mInterfaceBinders.get(interfaceId);
            if (oldBinder == responseBinder) {
                return;
            }

            if (oldBinder != null) {
                IBinder.DeathRecipient oldRecipient = mDeathRecipients.remove(interfaceId);
                if (oldRecipient != null) {
                    oldBinder.unlinkToDeath(oldRecipient, 0);
                }
                mInterfaceBinders.remove(interfaceId);
                if (mAllInterfacesReady) {
                    mAllInterfacesReady = false;
                    mConnectionGeneration++;
                }
            }

            IBinder.DeathRecipient recipient =
                    () -> handleInterfaceDeath(interfaceId, responseBinder);
            try {
                responseBinder.linkToDeath(recipient, 0);
            } catch (RemoteException e) {
                Log.w(TAG, "Response binder already dead for interface " + interfaceId);
                return;
            }

            mInterfaceBinders.put(interfaceId, responseBinder);
            mDeathRecipients.put(interfaceId, recipient);
            if (mInterfaceBinders.size() == mRadioInterfaceCount) {
                mAllInterfacesReady = true;
                Log.i(TAG, "All radio callbacks ready, generation " + mConnectionGeneration);
                mInterfaceLock.notifyAll();
                publishState = mInitialized;
            }
        }

        if (publishState) {
            publishCurrentState();
            notifyReadiness(true);
        }
    }

    /** Invoked when a registered callback Binder dies; also used by the callback fixture. */
    public void handleInterfaceDeath(int interfaceId, IBinder deadBinder) {
        boolean becameNotReady = false;
        synchronized (mInterfaceLock) {
            if (mInterfaceBinders.get(interfaceId) != deadBinder) {
                return;
            }
            mInterfaceBinders.remove(interfaceId);
            mDeathRecipients.remove(interfaceId);
            if (mAllInterfacesReady) {
                mAllInterfacesReady = false;
                mConnectionGeneration++;
                becameNotReady = true;
            }
            Log.w(TAG, "Radio callback died for interface " + interfaceId
                    + ", generation " + mConnectionGeneration);
        }
        if (becameNotReady) {
            notifyReadiness(false);
        }
    }

    private void notifyReadiness(boolean ready) {
        ReadinessListener listener = mReadinessListener;
        if (listener != null) {
            listener.onReadinessChanged(ready);
        }
    }

    public boolean waitForRadioInterfaces(long waitMs) {
        long deadlineNanos = System.nanoTime() + waitMs * 1_000_000L;
        synchronized (mInterfaceLock) {
            while (!mAllInterfacesReady) {
                long remainingNanos = deadlineNanos - System.nanoTime();
                if (remainingNanos <= 0) {
                    return false;
                }
                try {
                    long remainingMs = Math.max(1L, remainingNanos / 1_000_000L);
                    mInterfaceLock.wait(remainingMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    return false;
                }
            }
            return true;
        }
    }

    public String getMissingRadioInterfaces() {
        synchronized (mInterfaceLock) {
            Set<Integer> missing = new HashSet<>();
            for (int i = 0; i < mRadioInterfaceCount; i++) {
                if (!mInterfaceBinders.containsKey(i)) {
                    missing.add(i);
                }
            }
            return missing.toString();
        }
    }

    public int getNumPhysicalSlots() {
        int numPhysicalSlots = MockSimService.MOCK_SIM_SLOT_MIN;
        if (sContext != null) {
            int resourceId =
                    sContext.getResources()
                            .getIdentifier(
                                    "config_num_physical_slots", "integer", RESOURCE_PACKAGE_NAME);

            if (resourceId > 0) {
                numPhysicalSlots = sContext.getResources().getInteger(resourceId);
            } else {
                Log.d(TAG, "Fail to get the resource Id, using default: " + numPhysicalSlots);
            }
        } else {
            Log.d(TAG, "No context, using default slot count: " + numPhysicalSlots);
        }

        if (numPhysicalSlots > MockSimService.MOCK_SIM_SLOT_MAX) {
            Log.d(
                    TAG,
                    "Number of physical Slot ("
                            + numPhysicalSlots
                            + ") > mock sim slot support. Reset to max number supported ("
                            + MockSimService.MOCK_SIM_SLOT_MAX
                            + ").");
            numPhysicalSlots = MockSimService.MOCK_SIM_SLOT_MAX;
        } else if (numPhysicalSlots <= MockSimService.MOCK_SIM_SLOT_MIN) {
            Log.d(
                    TAG,
                    "Number of physical Slot ("
                            + numPhysicalSlots
                            + ") < mock sim slot support. Reset to min number supported ("
                            + MockSimService.MOCK_SIM_SLOT_MIN
                            + ").");
            numPhysicalSlots = MockSimService.MOCK_SIM_SLOT_MIN;
        }

        return numPhysicalSlots;
    }

    public RadioResponseInfo makeSolRsp(int serial) {
        RadioResponseInfo rspInfo = new RadioResponseInfo();
        rspInfo.type = RadioResponseType.SOLICITED;
        rspInfo.serial = serial;
        rspInfo.error = RadioError.NONE;

        return rspInfo;
    }

    public RadioResponseInfo makeSolRsp(int serial, int error) {
        RadioResponseInfo rspInfo = new RadioResponseInfo();
        rspInfo.type = RadioResponseType.SOLICITED;
        rspInfo.serial = serial;
        rspInfo.error = error;

        return rspInfo;
    }

    public boolean initialize(int simprofile) {
        Log.d(TAG, "initialize simprofile = " + simprofile);

        for (int i = 0; i < mNumOfPhone; i++) {
            if (!sMockModemConfigInterfaces[i].loadSimProfile(simprofile, TAG)) {
                Log.e(TAG, "Failed to load SIM profile " + simprofile + " for phone " + i);
                return false;
            }
        }

        mInitialized = true;
        publishCurrentState();
        return true;
    }

    public boolean isReady() {
        synchronized (mInterfaceLock) {
            return mInitialized && mAllInterfacesReady;
        }
    }

    private void publishCurrentState() {
        for (int i = 0; i < mNumOfPhone; i++) {
            sMockModemConfigInterfaces[i].notifyAllRegistrantNotifications();
        }
        sIRadioModemImpl.rilConnected();
    }

    public MockModemConfigInterface[] getMockModemConfigInterfaces() {
        return sMockModemConfigInterfaces;
    }

    public IRadioConfigImpl getIRadioConfig() {
        return sIRadioConfigImpl;
    }

    public IRadioModemImpl getIRadioModem() {
        return sIRadioModemImpl;
    }

    public IRadioSimImpl getIRadioSim() {
        return sIRadioSimImpl;
    }

    public IRadioNetworkImpl getIRadioNetwork() {
        return sIRadioNetworkImpl;
    }

    public IRadioVoiceImpl getIRadioVoice() {
        return sIRadioVoiceImpl;
    }

    public IRadioMessagingImpl getIRadioMessaging() {
        return sIRadioMessagingImpl;
    }

    public IRadioDataImpl getIRadioData() {
        return sIRadioDataImpl;
    }
}
