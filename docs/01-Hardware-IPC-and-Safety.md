# 01 - Hardware IPC & Safety Architecture

Technical specification for low-level Android Binder IPC transactions, MICOM safety gating, and vehicle bus actuator commands on Hyundai and Kia Gen5W platforms.

> [!NOTE]
> **Testing Status**: The transaction codes and bus payloads documented here were reverse-engineered, tested, and 100% verified on a **2024 Hyundai Ioniq 5 Limited running firmware 250607**. While theoretically shared across standard Gen5W Android (`S5W_M`) architectures, other vehicle models or firmware revisions remain physically unverified.

---

## 1. Safety Gate: Park (P) Gear Enforcement

Motorized seat adjustments while driving present a significant safety hazard. Therefore, all actuator logic in `hmg-phone-profiles` is strictly gated behind vehicle transmission state verification.

```
                         ┌─────────────────────────────┐
                         │   Incoming Profile Trigger  │
                         └──────────────┬──────────────┘
                                        │
                                        ▼
                         ┌─────────────────────────────┐
                         │   com.hkmc.micom.system     │
                         │    Transaction 36 (P Gear)  │
                         └──────────────┬──────────────┘
                                        │
                         ┌──────────────┴──────────────┐
                         ▼                             ▼
                  [Result == 0]                  [Result == 1]
                 Vehicle in Gear                Vehicle in Park
                         │                             │
                         ▼                             ▼
                ┌──────────────────┐          ┌──────────────────┐
                │ ABORT ACTUATION  │          │ PROCEED WITH     │
                │ Log warning      │          │ PROFILE & SEATS  │
                └──────────────────┘          └──────────────────┘
```

### IPC Call
```bash
service call com.hkmc.micom.system 36
```
- **Service**: `com.hkmc.micom.system`
- **Transaction Code**: `36` (`getGearPStatus`)
- **Return Parcel**:
  - `Result: Parcel(00000000 00000001 ...)` &rarr; **Park (1)**: Safe to actuate.
  - `Result: Parcel(00000000 00000000 ...)` &rarr; **Not in Park (0)**: Actuation is strictly aborted.

---

## 2. Driver Profile Switching

Infotainment settings, navigation destinations, and radio presets are tied to the platform's multi-user subsystem managed by `com.hkmc.userprofile`.

### Reading Active Profile
```bash
service call com.hkmc.userprofile 4
```
- **Transaction Code**: `4` (`getUserId`)
- **Return Parcel**: Returns integer user ID (`1` for Driver 1, `2` for Driver 2, `0` for Guest).

### Switching Driver Profile
```bash
# Switch active session
service call com.hkmc.userprofile 5 i32 <target_id>

# Persist target user for subsequent vehicle boot cycles
service call com.hkmc.userprofile 44 i32 <target_id>
```
- **Transaction Code 5** (`switchUser`): Triggers internal profile transition across head unit applications.
- **Transaction Code 44** (`setPreBootUserType`): Writes the profile selection to non-volatile storage so that the head unit starts directly into the chosen profile upon next vehicle start.

---

## 3. Physical Door Seat Memory Button Emulation

### The OEM Stock Behavior Limitation
Calling `switchUser` (Tx 5) instructs the head unit to load user settings, but seat position restoration is handled by the Unified Seat Module (USM). In stock firmware, the USM often restores coordinate drift or fails to match the physical door memory preset button saved by the driver.

### The Solution: CAN Bus Button Emulation
On Gen5W platforms, the Voice Recognition service (`com.hkmc.vr`) exposes an interface for sending raw button commands across the Controller Area Network (CAN) bus.

```bash
# Driver 1 Door Preset
service call com.hkmc.vr 14 i32 4

# Driver 2 Door Preset
service call com.hkmc.vr 14 i32 5
```

- **Service**: `com.hkmc.vr`
- **Transaction Code**: `14` (`sendVRCommand` / `C_AVNIMSButtonCmd`)
- **Payload**:
  - `4`: Driver 1 physical door memory recall
  - `5`: Driver 2 physical door memory recall
- **Bus Effect**: Broadcasts `CAN IL | TE_TX_IL_VC : 04` or `05`.
- **Vehicle Confirmation**:
  1. High-frequency instrument cluster chime sounds.
  2. Integrated Memory System (IMS) on-screen overlay appears on the head unit and cluster.
  3. Power seat and mirrors physically glide to the calibrated door preset positions.

### Actuation Sequence & Timing
To prevent race conditions between the USM software profile recall and the physical door button CAN command, a 1.0-second delay is inserted between the commands:

```
[Time 0.0s] Switch Profile (com.hkmc.userprofile 5 i32 1)
     │
     ▼ (Wait 1.0s for USM bus arbitration to settle)
     │
[Time 1.0s] Emulate Door Button (com.hkmc.vr 14 i32 4)
```

---

## 4. Consent Screen Auto-Dismissal

Upon startup, the head unit displays a regulatory driving disclaimer screen requiring the user to press "Confirm". This can be programmatically acknowledged once the driver profile is applied:

```bash
# Acknowledge legal agreement
service call factory 82 i32 1

# Dismiss notification / disclaimer overlay
service call notification 24
```

---

## 5. Native OEM Toast Notifications

Status updates and profile switch confirmations are broadcast using the vehicle's native toast receiver:

```bash
am broadcast -a com.hkmc.intent.action.TOAST \
    --es message "AutoProfile: Welcome Driver 1" \
    --ei duration 1 \
    --ei display_type 0
```
This renders a sleek banner across the top of the infotainment screen matching the vehicle's native UI theme.
