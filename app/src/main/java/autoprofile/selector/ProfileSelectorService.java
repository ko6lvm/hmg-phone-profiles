package autoprofile.selector;

import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.IBinder;
import android.util.Log;

/**
 * Background service for autoprofile.selector.
 * Monitors vehicle start and radio state events, gating actions strictly on Park (P).
 */
public class ProfileSelectorService extends Service {
    private static final String TAG = "AutoProfile.Service";

    public static final String ACTION_CHECK_SWITCH = "autoprofile.selector.CHECK_SWITCH";
    public static final String ACTION_TRIGGER_SWITCH = "autoprofile.selector.TRIGGER_SWITCH";
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
        if (mConfig == null) mConfig = ProfileConfig.getInstance(this);
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

                    int currentDriver = VehicleActuator.getCurrentUserId();
                    PhoneFingerprintManager.PresenceResult presence =
                        PhoneFingerprintManager.evaluatePresence(mConfig, currentDriver, hintMac);

                    int matched = presence.matchedDriver;
                    if (matched > 0 && matched != currentDriver) {
                        Log.i(TAG, "Presence matched Driver " + matched + " (" + presence.matchedPhoneName + ")");
                        VehicleActuator.executeSafeSwitch(
                            getApplicationContext(),
                            matched,
                            mConfig.dismissNotice,
                            true, // recall seat memory
                            mConfig.showBanner
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
                VehicleActuator.executeSafeSwitch(
                    getApplicationContext(),
                    targetDriver,
                    mConfig.dismissNotice,
                    true,
                    mConfig.showBanner
                );
            }
        }).start();
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
