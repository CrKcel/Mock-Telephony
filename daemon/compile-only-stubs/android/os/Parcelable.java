/*
 * Copyright (C) 2006 The Android Open Source Project
 * SPDX-License-Identifier: Apache-2.0
 */
package android.os;

/** Compile-only view of Parcelable including hidden stable-AIDL members. */
public interface Parcelable {
    int CONTENTS_FILE_DESCRIPTOR = 1;
    int PARCELABLE_WRITE_RETURN_VALUE = 1;
    int PARCELABLE_STABILITY_VINTF = 1;

    int describeContents();
    void writeToParcel(Parcel dest, int flags);
    default int getStability() { return 0; }

    interface ClassLoaderCreator<T> extends Creator<T> {
        T createFromParcel(Parcel source, ClassLoader loader);
    }

    interface Creator<T> {
        T createFromParcel(Parcel source);
        T[] newArray(int size);
    }
}
