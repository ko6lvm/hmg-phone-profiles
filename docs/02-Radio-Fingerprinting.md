# 02 - Radio Fingerprinting & Presence Detection

Guide to Bluetooth, Wi-Fi, and Projection presence detection, MAC address auto-learning, and driver conflict arbitration.

---

## 1. Multi-Radio Architecture

Modern smartphones use randomized MAC addresses on Wi-Fi networks for privacy, while Bluetooth connections maintain a fixed device MAC for paired profiles (A2DP media and HFP hands-free). 

To ensure fast and reliable detection, `hmg-phone-profiles` employs a multi-radio cross-referencing strategy:

```
┌─────────────────────────────────────────────────────────────┐
│                      Radio Detection                        │
├──────────────────────────────┬──────────────────────────────┤
│       Bluetooth Layer        │         Wi-Fi Layer          │
│                              │                              │
│  - A2DP connected device     │  - Active stations in ARP    │
│  - HFP hands-free link       │    table (/proc/net/arp)     │
│  - Stable hardware MAC       │  - Wireless CarPlay / AA     │
│                              │    sockets (TCP port 5288)   │
└──────────────┬───────────────┴──────────────┬───────────────┘
               │                              │
               └──────────────┬───────────────┘
                              │
               ┌──────────────▼───────────────┐
               │    Presence Resolution       │
               │                              │
               │  1. Match configured phones  │
               │  2. Auto-learn Wi-Fi MAC     │
               │  3. Evaluate conflict policy │
               └──────────────────────────────┘
```

---

## 2. Bluetooth Querying via Binder IPC

The daemon queries the head unit's Bluetooth stack directly via `service call bluetooth_manager`:

- **A2DP Device Query**:
  ```bash
  service call bluetooth_manager 17
  ```
  Returns a UTF-16LE encoded parcel containing the hardware MAC address of the actively connected media phone.

- **Parcel UTF-16LE Decoding**:
  Raw `service call` output packs 16-bit characters into 32-bit hex words:
  ```
  Result: Parcel(00000000 00000011 00410041 0042003a ... '..A.A.:.B.B.:')
  ```
  The daemon parses and unrolls the UTF-16 hex values directly into standard ASCII MAC format (`AA:BB:CC:11:22:33`).

---

## 3. Wi-Fi & Wireless Projection Tracking

When a phone connects to the vehicle's wireless hotspot for Wireless CarPlay or Android Auto:

1. **Kernel ARP Table (`/proc/net/arp`)**:
   Active stations connected to the `wlan0` interface are tracked in the kernel ARP table. Entries with complete hardware flags (`0x2`) represent connected client devices.

2. **Projection TCP Sockets (`/proc/net/tcp`)**:
   Wireless CarPlay and Android Auto establish high-bandwidth projection streaming over port `5288` (hex `14A8`). Inspecting `/proc/net/tcp` confirms active streaming sessions.

---

## 4. Automatic Wi-Fi MAC Learning

Because iOS and Android randomize their Wi-Fi MAC address per SSID by default, users do not need to manually discover or enter Wi-Fi MACs:

1. When a known phone connects via Bluetooth (identified by its stable Bluetooth MAC), the daemon simultaneously inspects newly associated Wi-Fi stations on the vehicle hotspot.
2. If an unmapped station is detected while only one phone connects, the daemon pairs the randomized Wi-Fi MAC to the active phone configuration in `config.json`.
3. Subsequent vehicle starts can now detect driver approach through either Wi-Fi or Bluetooth, ensuring the profile is switched even before Bluetooth audio handshake finishes.

---

## 5. Conflict Resolution Policies

When both Driver 1 and Driver 2 enter the vehicle simultaneously with their phones, the daemon resolves the conflict according to the `conflict_policy` setting in `config.json`:

| Policy | Setting | Behavior |
|---|---|---|
| **Priority #1 Wins** | `"p1"` *(Default)* | If Driver 1's phone is detected, Driver 1 is selected regardless of other phones. |
| **Priority #2 Wins** | `"p2"` | Driver 2 takes precedence if detected. |
| **Manual (Keep Current)** | `"manual"` | When both phones are detected, the daemon leaves the currently active profile unchanged to avoid unwanted seat movement. |
