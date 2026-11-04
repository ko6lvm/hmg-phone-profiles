package hmg.phone.profiles;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.IBinder;
import android.util.Log;

/**
 * Background service for hmg-phone-profiles.
 * Monitors vehicle start and radio state events, gating actions strictly on Park (P).
 */
public class ProfileSelectorService extends Service {
    private static final String TAG = "HmgPhoneProfiles.Service";

    public static final String ACTION_CHECK_SWITCH = "hmg.phone.profiles.CHECK_SWITCH";
    public static final String ACTION_TRIGGER_SWITCH = "hmg.phone.profiles.TRIGGER_SWITCH";
    public static final String EXTRA_TARGET_DRIVER = "extra_target_driver";

    private ProfileConfig mConfig;
    private BroadcastReceiver mRadioReceiver;

    @Override
    public void onCreate() {
        super.onCreate();
        Log.i(TAG, "ProfileSelectorService created.");
        mConfig = ProfileConfig.getInstance(this);

        mRadioReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String action = intent != null ? intent.getAction() : null;
                Log.d(TAG, "Received broadcast action: " + action);
                String hintMac = extractDeviceMac(intent);
                processPresenceCheck(hintMac);
            }
        };

        IntentFilter filter = new IntentFilter();
        filter.addAction("android.bluetooth.device.action.ACL_CONNECTED");
        filter.addAction("android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED");
        filter.addAction("com.broadcom.bt.hfdevice.hfbtcm.action.BTCM_CONNECTED");
        filter.addAction(ACTION_CHECK_SWITCH);
        registerReceiver(mRadioReceiver, filter);
    }

    private String extractDeviceMac(Intent intent) {
        if (intent == null) return null;
        try {
            android.bluetooth.BluetoothDevice dev = intent.getParcelableExtra("android.bluetooth.device.extra.DEVICE");
            if (dev == null) {
                dev = intent.getParcelableExtra("device");
            }
            if (dev != null && dev.getAddress() != null) {
                return dev.getAddress();
            }
            if (intent.hasExtra("address")) {
                return intent.getStringExtra("address");
            }
        } catch (Throwable ignored) {}
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_TRIGGER_SWITCH.equals(intent.getAction())) {
            int target = intent.getIntExtra(EXTRA_TARGET_DRIVER, 1);
            executeManualSwitch(target);
        } else {
            String hintMac = extractDeviceMac(intent);
            processPresenceCheck(hintMac);
        }
        return START_STICKY;
    }

    private void processPresenceCheck(final String hintMac) {
        if (mConfig == null) {
            mConfig = ProfileConfig.getInstance(this);
        } else {
            mConfig.load(this);
        }

        if (!mConfig.autoSelect) {
            Log.d(TAG, "Auto-select disabled in settings. Skipping.");
            return;
        }

        new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    // Small delay to allow radio handshake settling
                    Thread.sleep(1500);

                    // Check manual switch cooldown (suppress switch within 60s of manual override)
                    if (isCooldownActive()) {
                        Log.i(TAG, "Manual switch cooldown active (<60s). Suppressing presence switch.");
                        return;
                    }

                    int currentDriver = VehicleActuator.getCurrentUserId();
                    PhoneFingerprintManager.PresenceResult presence =
                        PhoneFingerprintManager.evaluatePresence(mConfig, currentDriver, hintMac);

                    int matched = presence.matchedDriver;
                    if (matched > 0 && matched != currentDriver) {
                        String trigger = (presence.matchedPhoneName != null && !presence.matchedPhoneName.isEmpty())
                                ? presence.matchedPhoneName : "Phone";
                        Log.i(TAG, "Presence matched Driver " + matched + " (" + trigger + ")");
                        VehicleActuator.executeSafeSwitch(
                            getApplicationContext(),
                            matched,
                            mConfig.dismissNotice,
                            mConfig.recallDoorSeat,
                            mConfig.showBanner,
                            trigger
                        );
                    }
                } catch (Throwable t) {
                    Log.e(TAG, "Error in processPresenceCheck: " + t.getMessage());
                }
            }
        }).start();
    }

    private void executeManualSwitch(final int targetDriver) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                if (mConfig == null) {
                    mConfig = ProfileConfig.getInstance(ProfileSelectorService.this);
                } else {
                    mConfig.load(ProfileSelectorService.this);
                }
                VehicleActuator.executeSafeSwitch(
                    getApplicationContext(),
                    targetDriver,
                    mConfig.dismissNotice,
                    mConfig.recallDoorSeat,
                    mConfig.showBanner,
                    "Manual"
                );
            }
        }).start();
    }

    private boolean isCooldownActive() {
        java.io.File[] tsFiles = new java.io.File[] {
            new java.io.File("/data/nemesis/apps/hmg-phone-profiles/data/last_switched_ts"),
            new java.io.File("/data/local/tmp/hmg_phone_profiles_last_switched_ts"),
            new java.io.File("/data/local/tmp/last_switched_ts")
        };
        long now = System.currentTimeMillis() / 1000;
        for (java.io.File f : tsFiles) {
            if (f.exists()) {
                try {
                    java.io.BufferedReader br = new java.io.BufferedReader(new java.io.FileReader(f));
                    String line = br.readLine();
                    br.close();
                    if (line != null && !line.trim().isEmpty()) {
                        long ts = Long.parseLong(line.trim());
                        if (now - ts >= 0 && now - ts < 60) {
                            return true;
                        }
                    }
                } catch (Throwable ignored) {}
            }
        }
        return false;
    }

    @Override
    public void onDestroy() {
        if (mRadioReceiver != null) {
            try {
                unregisterReceiver(mRadioReceiver);
            } catch (Throwable ignored) {}
        }
        super.onDestroy();
        Log.i(TAG, "ProfileSelectorService destroyed.");
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
