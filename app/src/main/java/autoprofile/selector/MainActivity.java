package autoprofile.selector;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.util.Log;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.Spinner;
import android.widget.TextView;

import java.io.File;

/**
 * MainActivity matching verified Stage 0 UI preview layout (1920x720 / 1280x720)
 * with Holo Dark styling and Hyundai Sans / Kia Cube typography.
 */
public class MainActivity extends Activity {
    private static final String TAG = "AutoProfile.Main";

    private ProfileConfig mConfig;
    private Handler mHandler;

    // Status pills
    private TextView mPillDaemon;
    private TextView mPillGear;
    private TextView mPillProfile;

    // Checkboxes
    private CheckBox mChkAutoSelect;
    private CheckBox mChkDismiss;
    private CheckBox mChkBanner;

    // Spinners
    private Spinner mSpinnerConflict;
    private Spinner mSpinnerWindow;

    // Phone rows
    private View mRowPhone1;
    private View mRowPhone2;
    private View mRowPhone3;
    private TextView mTagPhone1;
    private TextView mTagPhone2;
    private TextView mTagPhone3;

    // Overlays
    private View mModalWarning;
    private View mModalAssign;
    private View mToastBanner;
    private TextView mToastText;

    // Assign Dialog state
    private int mSelectedPhoneId = 1;
    private TextView mAssignDialogTitle;
    private TextView mAssignDialogMeta;

    private Typeface mHyundaiSans;
    private Typeface mKiaCube;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        mHandler = new Handler();
        mConfig = ProfileConfig.getInstance(this);

        initFonts();
        initViews();
        setupListeners();
        applyConfigToUi();
        refreshStatusAsync();
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatusAsync();
    }

    private void initFonts() {
        try {
            mHyundaiSans = Typeface.createFromAsset(getAssets(), "fonts/HyundaiSans-Regular.ttf");
            mKiaCube = Typeface.createFromAsset(getAssets(), "fonts/KiaCube-Regular.ttf");
        } catch (Throwable t) {
            Log.w(TAG, "Custom fonts loading fallback: " + t.getMessage());
        }
    }

    private void applyTypeface(View v, Typeface tf) {
        if (v instanceof TextView && tf != null) {
            ((TextView) v).setTypeface(tf);
        }
    }

    private void initViews() {
        mPillDaemon = (TextView) findViewById(R.id.pill_daemon);
        mPillGear = (TextView) findViewById(R.id.pill_gear);
        mPillProfile = (TextView) findViewById(R.id.pill_profile);

        mChkAutoSelect = (CheckBox) findViewById(R.id.chk_autoselect);
        mChkDismiss = (CheckBox) findViewById(R.id.chk_dismiss);
        mChkBanner = (CheckBox) findViewById(R.id.chk_banner);

        mSpinnerConflict = (Spinner) findViewById(R.id.spinner_conflict);
        mSpinnerWindow = (Spinner) findViewById(R.id.spinner_window);

        mRowPhone1 = findViewById(R.id.row_phone_1);
        mRowPhone2 = findViewById(R.id.row_phone_2);
        mRowPhone3 = findViewById(R.id.row_phone_3);
        mTagPhone1 = (TextView) findViewById(R.id.tag_phone_1);
        mTagPhone2 = (TextView) findViewById(R.id.tag_phone_2);
        mTagPhone3 = (TextView) findViewById(R.id.tag_phone_3);

        mModalWarning = findViewById(R.id.modal_warning_container);
        mModalAssign = findViewById(R.id.modal_assign_container);
        mToastBanner = findViewById(R.id.toast_banner_overlay);
        mToastText = (TextView) findViewById(R.id.toast_message);

        mAssignDialogTitle = (TextView) findViewById(R.id.assign_dialog_title);
        mAssignDialogMeta = (TextView) findViewById(R.id.assign_dialog_meta);

        // Populate conflict spinner
        String[] conflictOptions = new String[]{
            "Priority #1 Wins (Fast)",
            "Active Projection Wins (TCP)",
            "Keep Current / Manual"
        };
        ArrayAdapter<String> conflictAdapter = new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, conflictOptions);
        mSpinnerConflict.setAdapter(conflictAdapter);

        // Populate detection window spinner
        String[] windowOptions = new String[]{
            "10 seconds (Recommended)",
            "5 seconds",
            "15 seconds"
        };
        ArrayAdapter<String> windowAdapter = new ArrayAdapter<String>(this, android.R.layout.simple_spinner_dropdown_item, windowOptions);
        mSpinnerWindow.setAdapter(windowAdapter);

        // Apply custom typography if available
        if (mHyundaiSans != null) {
            applyTypeface(findViewById(R.id.txt_app_title), mHyundaiSans);
            applyTypeface(mPillDaemon, mHyundaiSans);
            applyTypeface(mPillGear, mHyundaiSans);
            applyTypeface(mPillProfile, mHyundaiSans);
        }
    }

    private void setupListeners() {
        // Close button
        findViewById(R.id.btn_close).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showToastBanner("Package closed. Background daemon stays active.");
                mHandler.postDelayed(new Runnable() {
                    @Override
                    public void run() {
                        finish();
                    }
                }, 800);
            }
        });

        // Phone row clicks -> Open Assign modal
        mRowPhone1.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openAssignDialog(1);
            }
        });
        mRowPhone2.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openAssignDialog(2);
            }
        });
        mRowPhone3.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openAssignDialog(3);
            }
        });

        // Checkbox: Auto-select
        mChkAutoSelect.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(CompoundButton buttonView, boolean isChecked) {
                mConfig.autoSelect = isChecked;
                mConfig.save(MainActivity.this);
            }
        });

        // Checkbox: Dismiss Notice (Requires confirmation opt-in dialog)
        mChkDismiss.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                boolean target = mChkDismiss.isChecked();
                if (target) {
                    // Revert visual state until confirmed in modal
                    mChkDismiss.setChecked(false);
                    mModalWarning.setVisibility(View.VISIBLE);
                } else {
                    mConfig.dismissNotice = false;
                    mConfig.save(MainActivity.this);
                }
            }
        });

        // Checkbox: Show banner
        mChkBanner.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(CompoundButton buttonView, boolean isChecked) {
                mConfig.showBanner = isChecked;
                mConfig.save(MainActivity.this);
            }
        });

        // Spinner: Conflict policy
        mSpinnerConflict.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                switch (position) {
                    case 0: mConfig.conflictPolicy = "p1"; break;
                    case 1: mConfig.conflictPolicy = "tcp"; break;
                    case 2: mConfig.conflictPolicy = "manual"; break;
                }
                mConfig.save(MainActivity.this);
            }
            @Override
            public void onNothingSelected(AdapterView<?> parent) {}
        });

        // Spinner: Detection window
        mSpinnerWindow.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                switch (position) {
                    case 0: mConfig.detectionWindowSec = 10; break;
                    case 1: mConfig.detectionWindowSec = 5; break;
                    case 2: mConfig.detectionWindowSec = 15; break;
                }
                mConfig.save(MainActivity.this);
            }
            @Override
            public void onNothingSelected(AdapterView<?> parent) {}
        });

        // Warning Dialog buttons
        findViewById(R.id.btn_warning_confirm).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                mModalWarning.setVisibility(View.GONE);
                mChkDismiss.setChecked(true);
                mConfig.dismissNotice = true;
                mConfig.save(MainActivity.this);
                showToastBanner("Dismiss startup notice opt-in enabled.");
            }
        });
        findViewById(R.id.btn_warning_cancel).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                mModalWarning.setVisibility(View.GONE);
            }
        });
        findViewById(R.id.btn_warning_dialog_close).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                mModalWarning.setVisibility(View.GONE);
            }
        });

        // Assign Dialog buttons
        findViewById(R.id.opt_assign_driver1).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                applyPhoneAssignment(mSelectedPhoneId, 1);
            }
        });
        findViewById(R.id.opt_assign_driver2).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                applyPhoneAssignment(mSelectedPhoneId, 2);
            }
        });
        findViewById(R.id.opt_assign_ignore).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                applyPhoneAssignment(mSelectedPhoneId, 0);
            }
        });
        findViewById(R.id.btn_assign_close_action).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                mModalAssign.setVisibility(View.GONE);
            }
        });
        findViewById(R.id.btn_assign_dialog_close).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                mModalAssign.setVisibility(View.GONE);
            }
        });

        // Bottom Bar Action Buttons
        findViewById(R.id.btn_refresh_phones).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                refreshStatusAsync();
                showToastBanner("Refreshed phone presence and vehicle telemetry.");
            }
        });

        findViewById(R.id.btn_test_driver1).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                triggerTestSwitch(1);
            }
        });

        findViewById(R.id.btn_test_driver2).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                triggerTestSwitch(2);
            }
        });
    }

    private void applyConfigToUi() {
        mChkAutoSelect.setChecked(mConfig.autoSelect);
        mChkDismiss.setChecked(mConfig.dismissNotice);
        mChkBanner.setChecked(mConfig.showBanner);

        if ("tcp".equalsIgnoreCase(mConfig.conflictPolicy)) {
            mSpinnerConflict.setSelection(1);
        } else if ("manual".equalsIgnoreCase(mConfig.conflictPolicy)) {
            mSpinnerConflict.setSelection(2);
        } else {
            mSpinnerConflict.setSelection(0);
        }

        if (mConfig.detectionWindowSec == 5) {
            mSpinnerWindow.setSelection(1);
        } else if (mConfig.detectionWindowSec == 15) {
            mSpinnerWindow.setSelection(2);
        } else {
            mSpinnerWindow.setSelection(0);
        }

        updatePhoneTags();
    }

    private void updatePhoneTags() {
        for (ProfileConfig.PhoneItem item : mConfig.phones) {
            TextView tagView = null;
            if (item.id == 1) tagView = mTagPhone1;
            else if (item.id == 2) tagView = mTagPhone2;
            else if (item.id == 3) tagView = mTagPhone3;

            if (tagView != null) {
                if (item.assignedDriver == 1) {
                    tagView.setText("Driver 1");
                    tagView.setBackgroundResource(R.drawable.tag_driver1);
                } else if (item.assignedDriver == 2) {
                    tagView.setText("Driver 2");
                    tagView.setBackgroundResource(R.drawable.tag_driver2);
                } else {
                    tagView.setText("Ignored");
                    tagView.setBackgroundResource(R.drawable.tag_ignored);
                }
            }
        }
    }

    private void openAssignDialog(int phoneId) {
        mSelectedPhoneId = phoneId;
        ProfileConfig.PhoneItem phone = mConfig.findPhoneById(phoneId);
        if (phone != null) {
            mAssignDialogTitle.setText("Assign: " + phone.name);
            String wifiStr = phone.wifiMac != null ? phone.wifiMac : "Unmapped";
            mAssignDialogMeta.setText("BT: " + phone.btMac + " · Wi-Fi: " + wifiStr);
        }
        mModalAssign.setVisibility(View.VISIBLE);
    }

    private void applyPhoneAssignment(int phoneId, int driverId) {
        ProfileConfig.PhoneItem phone = mConfig.findPhoneById(phoneId);
        if (phone != null) {
            phone.assignedDriver = driverId;
            phone.priority = driverId;
            mConfig.save(this);
            updatePhoneTags();
            String name = (driverId == 1) ? "Driver 1" : (driverId == 2 ? "Driver 2" : "Ignored");
            showToastBanner(phone.name + " assigned to " + name);
        }
        mModalAssign.setVisibility(View.GONE);
    }

    private void triggerTestSwitch(final int targetDriver) {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final boolean success = VehicleActuator.executeSafeSwitch(
                    MainActivity.this,
                    targetDriver,
                    mConfig.dismissNotice,
                    true,
                    mConfig.showBanner
                );
                mHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        if (success) {
                            showToastBanner("Profile switched to Driver " + targetDriver + " in Park (P)");
                        } else {
                            showToastBanner("Switch blocked: Vehicle is NOT in Park (P)!");
                        }
                        refreshStatusAsync();
                    }
                });
            }
        }).start();
    }

    private void refreshStatusAsync() {
        new Thread(new Runnable() {
            @Override
            public void run() {
                final boolean inPark = VehicleActuator.isParkGear();
                final int currentUid = VehicleActuator.getCurrentUserId();

                // Check daemon PID and heartbeat in state file
                File pidFile = new File("/data/nemesis/apps/autoprofile.selector/data/helper.pid");
                if (!pidFile.exists()) {
                    pidFile = new File("/data/local/tmp/autoprofile_helper.pid");
                }
                File stateFile = new File("/data/nemesis/apps/autoprofile.selector/data/state.json");
                if (!stateFile.exists()) {
                    stateFile = new File("/data/local/tmp/autoprofile_state.json");
                }
                long now = System.currentTimeMillis() / 1000;
                long stateModified = stateFile.exists() ? (stateFile.lastModified() / 1000) : 0;
                final boolean daemonRunning = pidFile.exists() || (stateFile.exists() && (now - stateModified < 15));

                mHandler.post(new Runnable() {
                    @Override
                    public void run() {
                        // Daemon pill
                        if (daemonRunning) {
                            mPillDaemon.setText(R.string.daemon_running);
                            mPillDaemon.setBackgroundResource(R.drawable.bg_pill_daemon);
                        } else {
                            mPillDaemon.setText(R.string.daemon_stopped);
                            mPillDaemon.setBackgroundResource(R.drawable.bg_pill_profile);
                        }

                        // Gear pill
                        if (inPark) {
                            mPillGear.setText(R.string.gear_park);
                            mPillGear.setBackgroundResource(R.drawable.bg_pill_gear);
                        } else {
                            mPillGear.setText(R.string.gear_drive);
                            mPillGear.setBackgroundResource(R.drawable.bg_pill_profile);
                        }

                        // Active profile pill
                        if (currentUid == 1) {
                            mPillProfile.setText(R.string.active_driver_1);
                        } else if (currentUid == 2) {
                            mPillProfile.setText(R.string.active_driver_2);
                        } else if (currentUid == 0) {
                            mPillProfile.setText(R.string.active_guest);
                        } else {
                            mPillProfile.setText(R.string.active_driver_1); // Preview default
                        }
                    }
                });
            }
        }).start();
    }

    public void showToastBanner(String message) {
        if (mToastBanner == null || mToastText == null) return;
        mToastText.setText(message);
        mToastBanner.setVisibility(View.VISIBLE);
        mHandler.removeCallbacks(mHideToastRunnable);
        mHandler.postDelayed(mHideToastRunnable, 3500);
    }

    private final Runnable mHideToastRunnable = new Runnable() {
        @Override
        public void run() {
            if (mToastBanner != null) {
                mToastBanner.setVisibility(View.GONE);
            }
        }
    };
}
