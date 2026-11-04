package hmg.phone.profiles;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.List;

/**
 * Manages configuration and phone profile associations.
 * Syncs with NEMESIS config.json and fallback SharedPreferences.
 */
public class ProfileConfig {
    private static final String TAG = "HmgPhoneProfiles.Config";

    public static final String PRIMARY_CONFIG_PATH = "/data/nemesis/apps/hmg-phone-profiles/config.json";
    public static final String LEGACY_CONFIG_PATH = "/data/nemesis/apps/autoprofile.selector/config.json";
    public static final String FALLBACK_CONFIG_PATH = "/data/local/tmp/hmg_phone_profiles_config.json";
    public static final String LEGACY_FALLBACK_CONFIG_PATH = "/data/local/tmp/autoprofile_config.json";
    private static final String PREF_NAME = "hmg_phone_profiles_prefs";

    public static class PhoneItem {
        public int id;
        public String name;
        public String btMac;
        public String wifiMac;
        public int assignedDriver; // 1 = Driver 1, 2 = Driver 2, 0 = Ignored
        public int priority;

        public PhoneItem(int id, String name, String btMac, String wifiMac, int assignedDriver, int priority) {
            this.id = id;
            this.name = name;
            this.btMac = btMac;
            this.wifiMac = wifiMac;
            this.assignedDriver = assignedDriver;
            this.priority = priority;
        }
    }

    public boolean autoSelect = true;
    public boolean dismissNotice = false;
    public boolean showBanner = true;
    public boolean recallDoorSeat = false;
    public String conflictPolicy = "p1"; // p1 = Priority #1, tcp = Active Projection TCP, manual = Keep Current
    public int detectionWindowSec = 10;
    public final List<PhoneItem> phones = new ArrayList<PhoneItem>();

    private static ProfileConfig sInstance;

    public static synchronized ProfileConfig getInstance(Context context) {
        if (sInstance == null) {
            sInstance = new ProfileConfig();
            sInstance.load(context);
        }
        return sInstance;
    }

    public ProfileConfig() {
        initDefaults();
    }

    private void initDefaults() {
        autoSelect = true;
        dismissNotice = false;
        showBanner = true;
        recallDoorSeat = false;
        conflictPolicy = "p1";
        detectionWindowSec = 10;
        phones.clear();
        // Default sanitized entries matching UI preview and documentation
        phones.add(new PhoneItem(1, "Pixel 11 Pro XL", "AA:BB:CC:11:22:33", "02:00:00:11:22:33", 1, 1));
        phones.add(new PhoneItem(2, "iPhone Duo", "DD:EE:FF:44:55:66", "02:00:00:44:55:66", 2, 2));
        phones.add(new PhoneItem(3, "Samsung S26 Ultra", "11:22:33:AA:BB:CC", null, 0, 0));
    }

    public void load(Context context) {
        File primary = new File(PRIMARY_CONFIG_PATH);
        File fallback = new File(FALLBACK_CONFIG_PATH);
        File legacy = new File(LEGACY_CONFIG_PATH);
        File legacyFallback = new File(LEGACY_FALLBACK_CONFIG_PATH);
        File file = null;

        if (primary.exists()) {
            file = primary;
        } else if (fallback.exists()) {
            file = fallback;
        } else if (legacy.exists()) {
            file = legacy;
        } else if (legacyFallback.exists()) {
            file = legacyFallback;
        }

        if (file != null && file.exists()) {
            try {
                BufferedReader reader = new BufferedReader(new FileReader(file));
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    sb.append(line);
                }
                reader.close();
                parseJson(sb.toString());
                return;
            } catch (Throwable t) {
                Log.w(TAG, "Failed reading config file: " + t.getMessage());
            }
        }

        // Fallback: SharedPreferences
        if (context != null) {
            SharedPreferences sp = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
            autoSelect = sp.getBoolean("auto_select", true);
            dismissNotice = sp.getBoolean("dismiss_notice", false);
            showBanner = sp.getBoolean("show_banner", true);
            recallDoorSeat = sp.getBoolean("recall_door_seat", false);
            conflictPolicy = sp.getString("conflict_policy", "p1");
            detectionWindowSec = sp.getInt("detection_window_sec", 10);
        }
    }

    private void parseJson(String jsonStr) {
        try {
            JSONObject root = new JSONObject(jsonStr);
            if (root.has("settings")) {
                JSONObject s = root.getJSONObject("settings");
                autoSelect = s.optBoolean("auto_select", true);
                dismissNotice = s.optBoolean("dismiss_notice", false);
                showBanner = s.optBoolean("show_banner", true);
                recallDoorSeat = s.optBoolean("recall_door_seat", false);
                conflictPolicy = s.optString("conflict_policy", "p1");
                detectionWindowSec = s.optInt("detection_window_sec", 10);
            }
            if (root.has("phones")) {
                JSONArray arr = root.getJSONArray("phones");
                phones.clear();
                for (int i = 0; i < arr.length(); i++) {
                    JSONObject p = arr.getJSONObject(i);
                    int id = p.optInt("id", i + 1);
                    String name = p.optString("name", "Phone " + id);
                    String bt = p.optString("bt_mac", "");
                    String wifi = p.has("wifi_mac") && !p.isNull("wifi_mac") ? p.getString("wifi_mac") : null;
                    if (wifi != null && (wifi.trim().isEmpty() || "null".equalsIgnoreCase(wifi.trim()))) {
                        wifi = null;
                    }
                    int driver = p.optInt("assigned_driver", 0);
                    int prio = p.optInt("priority", 0);
                    phones.add(new PhoneItem(id, name, bt, wifi, driver, prio));
                }
            }
        } catch (Throwable t) {
            Log.e(TAG, "Error parsing config JSON: " + t.getMessage());
        }
    }

    public void save(Context context) {
        // Update SharedPreferences
        if (context != null) {
            SharedPreferences sp = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE);
            sp.edit()
                .putBoolean("auto_select", autoSelect)
                .putBoolean("dismiss_notice", dismissNotice)
                .putBoolean("show_banner", showBanner)
                .putBoolean("recall_door_seat", recallDoorSeat)
                .putString("conflict_policy", conflictPolicy)
                .putInt("detection_window_sec", detectionWindowSec)
                .apply();
        }

        // Build JSON representation
        try {
            JSONObject root = new JSONObject();
            root.put("version", 1);

            JSONObject s = new JSONObject();
            s.put("auto_select", autoSelect);
            s.put("dismiss_notice", dismissNotice);
            s.put("show_banner", showBanner);
            s.put("recall_door_seat", recallDoorSeat);
            s.put("conflict_policy", conflictPolicy);
            s.put("detection_window_sec", detectionWindowSec);
            root.put("settings", s);

            JSONArray arr = new JSONArray();
            for (PhoneItem item : phones) {
                JSONObject p = new JSONObject();
                p.put("id", item.id);
                p.put("name", item.name);
                p.put("bt_mac", item.btMac);
                p.put("wifi_mac", item.wifiMac != null ? item.wifiMac : JSONObject.NULL);
                p.put("assigned_driver", item.assignedDriver);
                p.put("priority", item.priority);
                arr.put(p);
            }
            root.put("phones", arr);

            String out = root.toString(2);
            writeText(new File(PRIMARY_CONFIG_PATH), out);
            writeText(new File(FALLBACK_CONFIG_PATH), out);
        } catch (Throwable t) {
            Log.e(TAG, "Failed writing config file: " + t.getMessage());
        }
    }

    private void writeText(File file, String text) {
        try {
            File parent = file.getParentFile();
            if (parent != null && !parent.exists()) {
                parent.mkdirs();
            }
            FileWriter fw = new FileWriter(file);
            fw.write(text);
            fw.close();
        } catch (Throwable ignored) {}
    }

    public PhoneItem findPhoneById(int id) {
        for (PhoneItem item : phones) {
            if (item.id == id) return item;
        }
        return null;
    }

    public PhoneItem findPhoneByBtMac(String mac) {
        if (mac == null || mac.trim().isEmpty()) return null;
        for (PhoneItem item : phones) {
            if (item.btMac != null && item.btMac.equalsIgnoreCase(mac.trim())) {
                return item;
            }
        }
        return null;
    }
}
