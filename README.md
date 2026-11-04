# hmg-phone-profiles

Automatic driver profile selection and physical door seat memory recall via phone presence for Hyundai and Kia Gen5W systems.

Browse and download packages in the [NEMESIS Package Store](https://xwtk.cloud/services/nemesis#package-store).

---

## **Warning**

You bear complete responsibility for any procedure with your vehicle and its components. It is important to understand that modifying vehicle behavior carries inherent risk.

To ensure safety, **all profile switches and seat actuator movements in this software are strictly gated behind hardware transmission checks**: the system will only trigger actions when the vehicle transmission is verified to be in **Park (`P`)**. Never attempt to bypass gear safety checks.

---

## Features

- **Zero-Touch Driver Selection**: Automatically switches head unit profiles (Driver 1 or Driver 2) upon entering the vehicle based on connected Bluetooth and Wi-Fi phone presence.
- **Physical Door Memory Emulation**: Emulates authentic door memory button presses over the vehicle CAN bus (`com.hkmc.vr` Tx 14), triggering the instrument cluster chime, head unit overlay, and exact seat/mirror adjustments.
- **Hardware Park (P) Safety Gate**: Queries `com.hkmc.micom.system` Tx 36 (`getGearPStatus`) before any profile or seat actuation.
- **Auto-Learning Wi-Fi MACs**: Transparently pairs randomized Wi-Fi station addresses with established Bluetooth devices, ensuring reliable detection without manual MAC configuration.
- **Boot Disclaimer Dismissal**: Automatically acknowledges the startup regulatory disclaimer screen once the driver profile is applied.
- **Native OEM Companion App**: Includes an Android KitKat companion application styled with genuine `Hyundai Sans` and `Kia Cube` typography for in-vehicle touchscreen configuration.

---

## Compatibility Check

For your vehicle to be compatible with `hmg-phone-profiles`, it must:

1. Have an **Android-based Gen5W Head Unit** (software version containing `S5W_M` in **General Settings &gt; SW Info**).
2. Have the **NEMESIS** environment installed (version 1.16+ recommended).

> [!NOTE]
> **Hardware Testing Notice**: While the underlying `com.hkmc.*` Binder architecture and NEMESIS environment are common across Gen5W Android (`S5W_M`) head units, **this software has only been physically tested and verified on a 2024 Hyundai Ioniq 5 Limited running firmware 250607**. Other vehicles and trims theoretically share the same IPC interfaces and should work, but remain unverified on hardware.

### Vehicle Compatibility Matrix

| Platform / Model | Hardware & Firmware | Status | Notes |
|---|---|---|---|
| **Hyundai Ioniq 5 Limited (2024)** | Gen5W Android (`S5W_M`)<br>Firmware 250607 | **Tested & Verified** | 100% verified on live vehicle: profile switching, door IMS seat button recall, chime, and radio detection. |
| **Other Gen5W Android (`S5W_M`) Vehicles**<br>*(e.g. Kia EV6, Genesis GV60, Tucson, Santa Fe)* | Gen5W Android (`S5W_M`) | **Untested (Theoretically Compatible)** | Shares standard `com.hkmc.*` Binder APIs and NEMESIS runtime; theoretically should work, but unverified on hardware. |
| **Gen5W Linux (`S5W_L`)** | Non-Android Linux units | **Not Supported** | Fundamentally different software architecture; does not run Android. |
| **ccNC (Connected Car Navigation Cockpit)** | Hyundai Ioniq 6, Kona (SX2), Kia EV9 | **Not Supported** | Next-generation hardware running a distinct Android subsystem. |

---

## Quick Installation Guidance

| Step | Action | Description |
|:---:|---|---|
| **1** | **Download Package** | Obtain `autoprofile.selector-usb.zip` from releases or build it from source. |
| **2** | **Prepare USB Drive** | Format a blank USB flash drive to **FAT32** or **exFAT**. |
| **3** | **Copy Files** | Extract the contents of `autoprofile.selector-usb.zip` directly to the **root** of the USB drive.<br>The root must contain `NEMESIS.data` and the `packages/` directory. |
| **4** | **Install on Car** | Insert the USB drive into the vehicle's multimedia USB port while Android is running.<br>Tap **Install** when prompted by the native NEMESIS dialog. |

```
USB Root Structure:
├── NEMESIS.data                              (Trigger descriptor: type=install)
└── packages/
    └── autoprofile.selector.zip              (Application & daemon payload)
```

---

## Updating & Uninstallation

- **Updating**: Copy updated `NEMESIS.data` and `packages/autoprofile.selector.zip` to your USB drive and insert into the vehicle. Select **Update** when prompted.
- **Uninstallation**: Uninstall via NEMESIS Manager on the head unit (**My Packages &gt; Auto Profile Selector &gt; Uninstall**). The package uninstaller cleanly stops the background daemon, removes startup hooks, and uninstalls the companion APK.

---

## Documentation

Comprehensive documentation for developers, integrators, and curious owners:

| Document | Description |
|---|---|
| [**01 - Hardware IPC & Safety Architecture**](docs/01-Hardware-IPC-and-Safety.md) | Deep dive into Android Binder transactions, Park gear MICOM gating, and CAN door memory button recall. |
| [**02 - Radio Fingerprinting & Presence Detection**](docs/02-Radio-Fingerprinting.md) | Multi-radio presence detection, Bluetooth/Wi-Fi tracking, randomized MAC auto-learning, and conflict arbitration. |
| [**03 - Configuration Reference**](docs/03-Configuration.md) | JSON schema and parameter reference for `/data/nemesis/data/autoprofile.selector/config.json`. |
| [**04 - Building & Verification Guide**](docs/04-Building-and-Testing.md) | Compiling from source, Android SDK toolchain requirements, APK signing, and running the 5-stage verification suite. |
| [**05 - CLI Test Harness**](docs/05-CLI-Test-Harness.md) | Reference for using `test_profile_ipc.sh` to test vehicle IPC calls live over ADB. |

---

## Disclaimer

This project is an independent community development and is not affiliated with, sponsored by, or endorsed by Hyundai Motor Company, Kia Corporation, or their affiliates.
