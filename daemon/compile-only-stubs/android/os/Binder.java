/*
 * Copyright (C) 2006 The Android Open Source Project
 * SPDX-License-Identifier: Apache-2.0
 */
package android.os;

/** Compile-only view of Binder including the hidden VINTF stability method. */
public class Binder implements IBinder {
    public Binder() {}
    public Binder(String descriptor) {}
    public void attachInterface(IInterface owner, String descriptor) {}
    public static native long clearCallingIdentity();
    public static native long clearCallingWorkSource();
    protected void dump(java.io.FileDescriptor fd, java.io.PrintWriter out, String[] args) {}
    public void dump(java.io.FileDescriptor fd, String[] args) {}
    public void dumpAsync(java.io.FileDescriptor fd, String[] args) {}
    public static native void flushPendingCommands();
    public static native int getCallingPid();
    public static native int getCallingUid();
    public static int getCallingUidOrThrow() { return 0; }
    public static UserHandle getCallingUserHandle() { return null; }
    public static native int getCallingWorkSourceUid();
    public String getInterfaceDescriptor() { return null; }
    public boolean isBinderAlive() { return false; }
    public static void joinThreadPool() {}
    public void linkToDeath(IBinder.DeathRecipient recipient, int flags) {}
    protected final void markVintfStability() {}
    protected boolean onTransact(int code, Parcel data, Parcel reply, int flags)
            throws RemoteException { return false; }
    public boolean pingBinder() { return false; }
    public IInterface queryLocalInterface(String descriptor) { return null; }
    public static native void restoreCallingIdentity(long token);
    public static native void restoreCallingWorkSource(long token);
    public static native long setCallingWorkSourceUid(int workSource);
    public void shellCommand(
            java.io.FileDescriptor in,
            java.io.FileDescriptor out,
            java.io.FileDescriptor err,
            String[] args,
            ShellCallback callback,
            ResultReceiver resultReceiver) throws RemoteException {}
    public final boolean transact(int code, Parcel data, Parcel reply, int flags)
            throws RemoteException { return false; }
    public boolean unlinkToDeath(IBinder.DeathRecipient recipient, int flags) { return false; }
}
