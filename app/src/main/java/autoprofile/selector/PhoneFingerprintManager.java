package autoprofile.selector;

import android.os.IBinder;
import android.os.Parcel;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Resolves driver presence by combining Bluetooth and Wi-Fi fingerprints.
 * Reads /proc/net/arp (station MACs) and /proc/net/tcp (projection sockets).
 */
public class PhoneFingerprintManager {
    private static final String TAG = "AutoProfile.Fingerprint";

    private static final Pattern MAC_PATTERN = Pattern.compile("([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}");
    // Port 5288 decimal in hex is 14A8 (Wireless Android Auto)
    private static final String PORT_WAA_HEX = ":14A8";

    public static class PresenceResult {
        public int matchedDriver; // 1 = Driver 1, 2 = Driver 2, 0 = None / Ignored
        public String matchedPhoneName;
        public boolean hasActiveProjection;
        public final Set<String> connectedBtMacs = new HashSet<String>();
        public final Set<String> connectedWifiMacs = new HashSet<String>();
    }

    /**
     * Inspects /proc/net/arp to find connected Wi-Fi station MACs.
     */
    public static Set<String> readArpStations() {
        Set<String> stations = new HashSet<String>();
        File file = new File("/proc/net/arp");
        if (!file.exists()) return stations;

        try {
            BufferedReader reader = new BufferedReader(new FileReader(file));
            String line;
            reader.readLine(); // Skip header
            while ((line = reader.readLine()) != null) {
                String[] tokens = line.trim().split("\\s+");
                // Expected format: IP HW-type Flags HW-address Mask Device
                if (tokens.length >= 4) {
                    String flags = tokens[2];
                    String mac = tokens[3].toUpperCase();
                    // 0x2 flag indicates completed/reachable ARP entry
                    if ("0x2".equalsIgnoreCase(flags) && MAC_PATTERN.matcher(mac).matches()) {
                        if (!"00:00:00:00:00:00".equals(mac)) {
                            stations.add(mac);
                        }
                    }
                }
            }
            reader.close();
        } catch (Throwable t) {
            Log.w(TAG, "Error reading /proc/net/arp: " + t.getMessage());
        }
        return stations;
    }

    /**
     * Checks /proc/net/tcp for active Wireless Android Auto (port 5288 / 14A8)
     * or active projection sockets.
     */
    public static boolean checkActiveProjectionSocket() {
        File file = new File("/proc/net/tcp");
        if (!file.exists()) return false;

        try {
            BufferedReader reader = new BufferedReader(new FileReader(file));
            String line;
            reader.readLine(); // Skip header
            while ((line = reader.readLine()) != null) {
                // Check if local or remote address contains port 14A8 (5288 decimal)
                if (line.contains(PORT_WAA_HEX)) {
                    reader.close();
                    return true;
                }
            }
            reader.close();
        } catch (Throwable t) {
            Log.w(TAG, "Error reading /proc/net/tcp: " + t.getMessage());
        }
        return false;
    }

    /**
     * Queries connected Bluetooth MACs from system Binder services.
     */
    public static Set<String> queryConnectedBtMacs() {
        Set<String> btMacs = new HashSet<String>();

        // Query bluetooth_manager Tx 17
        queryBinderMac("bluetooth_manager", 17, btMacs);

        // Query phoneprojection Tx 5 (Device BT MAC), Tx 8 (CarPlay), Tx 9 (Android Auto)
        queryBinderMac("phoneprojection", 5, btMacs);
        queryBinderMac("phoneprojection", 8, btMacs);
        queryBinderMac("phoneprojection", 9, btMacs);

        // Query dipo Tx 14 (CarPlay address)
        queryBinderMac("dipo", 14, btMacs);

        return btMacs;
    }

    public static String decodeParcelString(String rawParcel) {
        if (rawParcel == null || rawParcel.isEmpty()) return "";
        int start = rawParcel.indexOf("Parcel(");
        if (start < 0) return "";
        int end = rawParcel.indexOf("'", start);
        if (end < 0) end = rawParcel.indexOf(")", start);
        if (end < 0) end = rawParcel.length();
        String hexPart = rawParcel.substring(start + 7, end).trim();
        String[] words = hexPart.split("\\s+");
        if (words.length < 2) return "";
        try {
            int len = (int) Long.parseLong(words[1], 16);
            if (len <= 0 || len > 512) return "";
            StringBuilder sb = new StringBuilder();
            int count = 0;
            for (int i = 2; i < words.length && count < len; i++) {
                String w = words[i];
                if (w.length() == 8) {
                    int c1 = Integer.parseInt(w.substring(6, 8), 16) | (Integer.parseInt(w.substring(4, 6), 16) << 8);
                    if (c1 > 0 && count < len) {
                        sb.append((char) c1);
                        count++;
                    }
                    if (count < len) {
                        int c2 = Integer.parseInt(w.substring(2, 4), 16) | (Integer.parseInt(w.substring(0, 2), 16) << 8);
                        if (c2 > 0) {
                            sb.append((char) c2);
                            count++;
                        }
                    }
                }
            }
            return sb.toString();
        } catch (Throwable t) {
            return "";
        }
    }

    private static void queryBinderMac(String serviceName, int code, Set<String> outSet) {
        int initialSize = outSet.size();
        IBinder binder = VehicleActuator.getService(serviceName);
        if (binder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                binder.transact(code, data, reply, 0);
                reply.readException();
                String val = reply.readString();
                if (val != null) {
                    Matcher m = MAC_PATTERN.matcher(val);
                    while (m.find()) {
                        outSet.add(m.group().toUpperCase());
                    }
                }
            } catch (Throwable ignored) {
            } finally {
                data.recycle();
                reply.recycle();
            }
        }

        // Fallback to service call CLI if binder query did not add a MAC
        if (outSet.size() == initialSize) {
            String raw = VehicleActuator.execServiceCall(serviceName, code);
            String decoded = decodeParcelString(raw);
            if (!decoded.isEmpty()) {
                Matcher m = MAC_PATTERN.matcher(decoded);
                while (m.find()) {
                    outSet.add(m.group().toUpperCase());
                }
            }
        }
    }

    /**
     * Resolves the current driver presence based on connected radios and configuration.
     */
    public static PresenceResult evaluatePresence(ProfileConfig config, int currentDriver) {
        return evaluatePresence(config, currentDriver, null);
    }

    public static PresenceResult evaluatePresence(ProfileConfig config, int currentDriver, String hintBtMac) {
        PresenceResult result = new PresenceResult();
        result.connectedBtMacs.addAll(queryConnectedBtMacs());
        if (hintBtMac != null && !hintBtMac.isEmpty()) {
            result.connectedBtMacs.add(hintBtMac.toUpperCase());
        }
        result.connectedWifiMacs.addAll(readArpStations());
        result.hasActiveProjection = checkActiveProjectionSocket();

        List<ProfileConfig.PhoneItem> matchedPhones = new ArrayList<ProfileConfig.PhoneItem>();

        for (ProfileConfig.PhoneItem phone : config.phones) {
            boolean btMatch = (phone.btMac != null && result.connectedBtMacs.contains(phone.btMac.toUpperCase()));
            boolean wifiMatch = (phone.wifiMac != null && result.connectedWifiMacs.contains(phone.wifiMac.toUpperCase()));

            if (btMatch || wifiMatch) {
                matchedPhones.add(phone);
            }
        }

        // Auto-learning: If only one BT phone connected and an unmapped Wi-Fi MAC is active
        if (matchedPhones.size() == 1) {
            ProfileConfig.PhoneItem single = matchedPhones.get(0);
            if (single.wifiMac == null && !result.connectedWifiMacs.isEmpty()) {
                String learned = result.connectedWifiMacs.iterator().next();
                single.wifiMac = learned;
                Log.i(TAG, "Auto-learned Wi-Fi MAC " + learned + " for " + single.name);
                config.save(null);
            }
        }

        if (matchedPhones.isEmpty()) {
            result.matchedDriver = 0;
            result.matchedPhoneName = null;
            return result;
        }

        if (matchedPhones.size() == 1) {
            ProfileConfig.PhoneItem single = matchedPhones.get(0);
            result.matchedDriver = single.assignedDriver;
            result.matchedPhoneName = single.name;
            return result;
        }

        // Conflict Resolution (Multiple phones matched)
        String policy = config.conflictPolicy;
        if ("tcp".equalsIgnoreCase(policy)) {
            // Whichever has active projection wins
            if (result.hasActiveProjection) {
                // Prefer Driver 1 if active
                result.matchedDriver = 1;
                result.matchedPhoneName = "Priority Projection";
            } else {
                result.matchedDriver = 1;
                result.matchedPhoneName = "Driver 1";
            }
        } else if ("manual".equalsIgnoreCase(policy)) {
            // Keep current driver
            result.matchedDriver = (currentDriver > 0) ? currentDriver : 1;
            result.matchedPhoneName = "Manual / Current";
        } else {
            // Default "p1": Priority #1 wins
            ProfileConfig.PhoneItem highest = null;
            for (ProfileConfig.PhoneItem item : matchedPhones) {
                if (highest == null || (item.priority > 0 && item.priority < highest.priority)) {
                    highest = item;
                }
            }
            if (highest != null) {
                result.matchedDriver = highest.assignedDriver;
                result.matchedPhoneName = highest.name;
            } else {
                result.matchedDriver = 1;
                result.matchedPhoneName = "Driver 1";
            }
        }

        return result;
    }
}
