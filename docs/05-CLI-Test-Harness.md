# 05 - CLI Test Harness (`test_profile_ipc.sh`)

Reference for inspecting, testing, and debugging vehicle IPC transactions on live Gen5W hardware over ADB.

---

## 1. Overview

`test_profile_ipc.sh` is an interactive command-line harness designed to run from your workstation against an Android head unit connected via ADB. 

It provides diagnostic subcommands to query vehicle bus state, inspect connected radios, emulate seat memory buttons, and switch profiles without touching the touchscreen.

> [!IMPORTANT]
> **Safety Gating**: Every mutating subcommand (`change-profile`, `change-seats`, etc.) queries `com.hkmc.micom.system` Tx 36 (`getGearPStatus`) and will immediately abort if the vehicle is not in **Park (`P`)**.

---

## 2. Command Reference

### Vehicle State & Gear Status
```bash
# Query gear state (verifies Park gear safety gate)
./test_profile_ipc.sh gear-status

# Display full vehicle status summary (gear, active profile, IMS state, boot screen)
./test_profile_ipc.sh status
```

### Driver Profiles
```bash
# Query active user ID and configured driver names
./test_profile_ipc.sh get-profile

# Switch active profile to Driver 1, Driver 2, or Guest (0)
./test_profile_ipc.sh change-profile 1
./test_profile_ipc.sh change-profile 2
```

### Seat Memory (IMS Door Buttons)
```bash
# Query IMS support options and current seat moving state
./test_profile_ipc.sh get-seats

# Emulate physical door memory button 1 or 2 via VR CAN command
./test_profile_ipc.sh change-seats 1 vr
./test_profile_ipc.sh change-seats 2 vr
```

### Radio Fingerprinting
```bash
# Query connected Bluetooth devices, head unit MAC, and media phone MAC
./test_profile_ipc.sh bt-fingerprint

# Inspect kernel ARP table (/proc/net/arp) and wireless projection sockets
./test_profile_ipc.sh wifi-fingerprint
```

### On-Screen Notifications
```bash
# Broadcast a native OEM toast banner overlay on the head unit display
./test_profile_ipc.sh show-message "Profile switched to Driver 1"
```

### Consent Screen
```bash
# Query or dismiss the startup disclaimer screen
./test_profile_ipc.sh consent get
./test_profile_ipc.sh consent dismiss
```
