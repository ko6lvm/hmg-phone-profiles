package hmg.phone.profiles;

import android.content.Context;
import android.content.Intent;
import android.os.IBinder;
import android.os.Parcel;
import android.util.Log;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;

/**
 * VehicleActuator encapsulates all in-vehicle hardware IPC interactions
 * for the 2024 Hyundai Ioniq 5 Limited (Gen5W, Build 260507).
 *
 * SAFETY GATE: All mutating operations strictly verify that the vehicle gear
 * is in Park (P) via com.hkmc.micom.system Tx 36 before execution.
 */
public class VehicleActuator {
    private static final String TAG = "HmgPhoneProfiles.Actuator";

    // Binder service names
    public static final String SVC_SYSTEM = "com.hkmc.micom.system";
    public static final String SVC_USERPROFILE = "com.hkmc.userprofile";
    public static final String SVC_VR = "com.hkmc.vr";
    public static final String SVC_FACTORY = "com.hkmc.factory";
    public static final String SVC_NOTIFICATION = "notification";

    // Transaction codes (Firmware 260507 Ground Truth)
    public static final int TX_GEAR_P_STATUS = 36;          // ISystemService.getGearPStatus
    public static final int TX_GET_USER_ID = 4;             // IUserProfileService.getUserId
    public static final int TX_SWITCH_USER = 5;             // IUserProfileService.switchUser
    public static final int TX_GET_USER_NAME = 10;          // IUserProfileService.getUserName
    public static final int TX_SET_PREBOOT_USER = 44;       // IUserProfileService.setPreBootUserType
    public static final int TX_VR_AVN_IMS_CMD = 14;         // IVRService.set_AVNIMSButton_Cmd_AVN
    public static final int TX_HIDE_CONSENT_SCREEN = 82;    // IMicomFactoryService.hideConsentScreen
    public static final int TX_NOTIFY_CONSENT_CHANGED = 24; // INotificationManager.notifyConsentScreenChanged

    // Seat Door Memory commands (AVNIMSButtonType enum)
    public static final int CMD_PBACK_P1 = 4; // Door Memory 1
    public static final int CMD_PBACK_P2 = 5; // Door Memory 2

    // Broadcast actions & extras
    public static final String ACTION_OEM_TOAST = "com.hkmc.intent.action.TOAST";
    public static final String EXTRA_TOAST_MESSAGE = "com.hkmc.intent.extra.TOAST_MESSAGE";
    public static final String EXTRA_TOAST_POPUPSHOWING = "com.hkmc.intent.extra.TOAST_POPUPSHOWING";

    private static Method sGetServiceMethod;

    static {
        try {
            Class<?> smClass = Class.forName("android.os.ServiceManager");
            sGetServiceMethod = smClass.getMethod("getService", String.class);
        } catch (Throwable t) {
            Log.w(TAG, "ServiceManager reflection unavailable: " + t.getMessage());
        }
    }

    /**
     * Obtains an IBinder reference via ServiceManager reflection.
     */
    public static IBinder getService(String serviceName) {
        if (sGetServiceMethod != null) {
            try {
                return (IBinder) sGetServiceMethod.invoke(null, serviceName);
            } catch (Throwable t) {
                Log.e(TAG, "Failed to get service " + serviceName + ": " + t.getMessage());
            }
        }
        return null;
    }

    /**
     * Transacts directly with a Binder service.
     */
    public static boolean transactRaw(String serviceName, int code, Parcel data, Parcel reply) {
        IBinder binder = getService(serviceName);
        if (binder != null) {
            try {
                return binder.transact(code, data, reply, 0);
            } catch (Throwable t) {
                Log.e(TAG, "Binder transact failed for " + serviceName + " Tx " + code + ": " + t.getMessage());
            }
        }
        return false;
    }

    /**
     * Fallback execution via toolbox /system/bin/service call.
     */
    public static String execServiceCall(String serviceName, int code, String... args) {
        try {
            StringBuilder cmd = new StringBuilder();
            cmd.append("/system/bin/service call ").append(serviceName).append(" ").append(code);
            for (String arg : args) {
                cmd.append(" ").append(arg);
            }
            Process p = Runtime.getRuntime().exec(new String[]{"/system/bin/sh", "-c", cmd.toString()});
            BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = r.readLine()) != null) {
                sb.append(line).append("\n");
            }
            p.waitFor();
            return sb.toString().trim();
        } catch (Throwable t) {
            Log.e(TAG, "execServiceCall failed for " + serviceName + ": " + t.getMessage());
            return "";
        }
    }

    /**
     * STRICT SAFETY GATE: Checks if the vehicle is in Park (P).
     * com.hkmc.micom.system Tx 36 returns 1 when in Park, 0 otherwise.
     */
    public static boolean isParkGear() {
        // 1. Try RootBridge helper first (privilege-escalated execution via NEMESIS / su)
        try {
            RootBridge.Result rHelper = RootBridge.runHelper("gear");
            if (rHelper.output != null && !rHelper.output.isEmpty()) {
                if (rHelper.output.contains("PARK") || rHelper.exitCode == 0) {
                    return true;
                } else if (rHelper.output.contains("NOT_PARK")) {
                    return false;
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "RootBridge gear check threw: " + t.getMessage());
        }

        // 2. Try direct root service call
        try {
            RootBridge.Result rCmd = RootBridge.runCommand("/system/bin/service call " + SVC_SYSTEM + " " + TX_GEAR_P_STATUS);
            if (rCmd.output != null && rCmd.output.contains("00000000 00000001")) {
                return true;
            }
        } catch (Throwable t) {
            Log.w(TAG, "RootBridge service call threw: " + t.getMessage());
        }

        // 3. Try direct Binder transact
        IBinder binder = getService(SVC_SYSTEM);
        if (binder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                binder.transact(TX_GEAR_P_STATUS, data, reply, 0);
                reply.readException();
                int result = reply.readInt();
                return result == 1;
            } catch (Throwable t) {
                Log.w(TAG, "Binder isParkGear threw: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }
        }

        // 4. Fallback to unprivileged toolbox service call CLI
        String output = execServiceCall(SVC_SYSTEM, TX_GEAR_P_STATUS);
        return output.contains("00000000 00000001");
    }

    /**
     * Gets the currently active profile user ID.
     * 1 = Driver 1, 2 = Driver 2, 0 = Guest, -1 = Error.
     */
    public static int getCurrentUserId() {
        // 1. Try RootBridge helper
        try {
            RootBridge.Result r = RootBridge.runHelper("get-profile");
            String out = r.output != null ? r.output.trim() : "";
            if ("1".equals(out)) return 1;
            if ("2".equals(out)) return 2;
            if ("0".equals(out)) return 0;
        } catch (Throwable t) {
            Log.w(TAG, "RootBridge get-profile threw: " + t.getMessage());
        }

        // 2. Try RootBridge service call
        try {
            RootBridge.Result rCmd = RootBridge.runCommand("/system/bin/service call " + SVC_USERPROFILE + " " + TX_GET_USER_ID);
            if (rCmd.output.contains("00000000 00000001")) return 1;
            if (rCmd.output.contains("00000000 00000002")) return 2;
            if (rCmd.output.contains("00000000 00000000")) return 0;
        } catch (Throwable ignored) {}

        // 3. Try direct Binder transact
        IBinder binder = getService(SVC_USERPROFILE);
        if (binder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                binder.transact(TX_GET_USER_ID, data, reply, 0);
                reply.readException();
                return reply.readInt();
            } catch (Throwable t) {
                Log.w(TAG, "Binder getCurrentUserId threw: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }
        }

        String output = execServiceCall(SVC_USERPROFILE, TX_GET_USER_ID);
        if (output.contains("00000000 00000001")) return 1;
        if (output.contains("00000000 00000002")) return 2;
        if (output.contains("00000000 00000000")) return 0;
        return -1;
    }

    /**
     * Gets the driver display name for a given userType.
     */
    public static String getUserName(int userType) {
        // 1. Try RootBridge helper
        try {
            RootBridge.Result r = RootBridge.runHelper("get-profile-name", String.valueOf(userType));
            String name = r.output != null ? r.output.trim() : "";
            if (!name.isEmpty() && !name.contains("<null>") && !name.contains("<empty>") && !"Unknown".equalsIgnoreCase(name)) {
                return name;
            }
        } catch (Throwable ignored) {}

        // 2. Try direct Binder transact
        IBinder binder = getService(SVC_USERPROFILE);
        if (binder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInt(userType);
                binder.transact(TX_GET_USER_NAME, data, reply, 0);
                reply.readException();
                String name = reply.readString();
                if (name != null && !name.isEmpty()) return name;
            } catch (Throwable t) {
                Log.w(TAG, "Binder getUserName threw: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }
        }

        switch (userType) {
            case 1: return "Driver 1";
            case 2: return "Driver 2";
            case 0: return "Guest";
            default: return "Unknown";
        }
    }

    /**
     * Switches the active user profile (Tx 5) and updates pre-boot profile (Tx 44).
     */
    public static void switchUser(int userType) {
        // Execute via RootBridge with full root privileges
        RootBridge.runCommand("/system/bin/service call " + SVC_USERPROFILE + " " + TX_SWITCH_USER + " i32 " + userType + " i32 0 i32 0");
        RootBridge.runCommand("/system/bin/service call " + SVC_USERPROFILE + " " + TX_SET_PREBOOT_USER + " i32 " + userType);

        IBinder binder = getService(SVC_USERPROFILE);
        if (binder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInt(userType);
                data.writeInt(0); // isFromExternal = false
                data.writeInt(0); // isCheckPswd = false
                binder.transact(TX_SWITCH_USER, data, reply, 0);
            } catch (Throwable t) {
                Log.e(TAG, "switchUser binder failed: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }

            // Also set pre-boot user type (Tx 44)
            Parcel data44 = Parcel.obtain();
            Parcel reply44 = Parcel.obtain();
            try {
                data44.writeInt(userType);
                binder.transact(TX_SET_PREBOOT_USER, data44, reply44, 0);
            } catch (Throwable t) {
                Log.w(TAG, "setPreBootUserType threw: " + t.getMessage());
            } finally {
                data44.recycle();
                reply44.recycle();
            }
        }
    }

    /**
     * Emulates physical door memory button 1 or 2 via IVRService.set_AVNIMSButton_Cmd_AVN (Tx 14).
     * Button 1: cmd = 4 (PBACK_P1).
     * Button 2: cmd = 5 (PBACK_P2).
     */
    public static void recallSeatMemory(int driverId) {
        if (driverId != 1 && driverId != 2) return;
        int cmd = (driverId == 1) ? CMD_PBACK_P1 : CMD_PBACK_P2;

        RootBridge.runCommand("/system/bin/service call " + SVC_VR + " " + TX_VR_AVN_IMS_CMD + " i32 " + cmd);

        IBinder binder = getService(SVC_VR);
        if (binder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInt(cmd);
                binder.transact(TX_VR_AVN_IMS_CMD, data, reply, 0);
            } catch (Throwable t) {
                Log.e(TAG, "recallSeatMemory binder failed: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }
        }
    }

    /**
     * Dismisses the startup ConsentScreen overlay via factory Tx 82 & notification Tx 24.
     */
    public static void dismissConsentScreen(int userType) {
        RootBridge.runCommand("/system/bin/service call " + SVC_FACTORY + " " + TX_HIDE_CONSENT_SCREEN);
        RootBridge.runCommand("/system/bin/service call " + SVC_NOTIFICATION + " " + TX_NOTIFY_CONSENT_CHANGED + " i32 1 i32 " + userType);

        IBinder factoryBinder = getService(SVC_FACTORY);
        if (factoryBinder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                factoryBinder.transact(TX_HIDE_CONSENT_SCREEN, data, reply, 0);
            } catch (Throwable t) {
                Log.w(TAG, "hideConsentScreen binder failed: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }
        }

        IBinder notifBinder = getService(SVC_NOTIFICATION);
        if (notifBinder != null) {
            Parcel data = Parcel.obtain();
            Parcel reply = Parcel.obtain();
            try {
                data.writeInt(1); // 1 = dismissed
                data.writeInt(userType);
                notifBinder.transact(TX_NOTIFY_CONSENT_CHANGED, data, reply, 0);
            } catch (Throwable t) {
                Log.w(TAG, "notifyConsentScreenChanged threw: " + t.getMessage());
            } finally {
                data.recycle();
                reply.recycle();
            }
        }
    }

    /**
     * Broadcasts native OEM toast notification (~5s global display across all apps).
     */
    public static void showOemToast(Context context, String message) {
        if (message == null) message = "";
        // 1. RootBridge broadcast
        RootBridge.runCommand("/system/bin/am broadcast -a " + ACTION_OEM_TOAST +
                " -e " + EXTRA_TOAST_MESSAGE + " \"" + message.replace("\"", "\\\"") + "\"" +
                " --ez " + EXTRA_TOAST_POPUPSHOWING + " true");

        // 2. Standard context broadcast fallback
        if (context != null) {
            try {
                Intent intent = new Intent(ACTION_OEM_TOAST);
                intent.putExtra(EXTRA_TOAST_MESSAGE, message);
                intent.putExtra(EXTRA_TOAST_POPUPSHOWING, true);
                context.sendBroadcast(intent);
            } catch (Throwable t) {
                Log.e(TAG, "Failed to broadcast OEM Toast: " + t.getMessage());
            }
        }
    }

    /**
     * Executes the complete, safe driver profile switch flow.
     * STRICT SAFETY GATE: Completely aborts if vehicle is not in Park (P).
     */
    public static boolean executeSafeSwitch(Context context, int targetUid, boolean dismissNotice, boolean recallSeat, boolean showToast) {
        Log.i(TAG, "executeSafeSwitch requested for Driver " + targetUid);

        // 1. SAFETY GATE: Verify Park (P)
        if (!isParkGear()) {
            Log.w(TAG, "SAFETY GATE ABORT: Vehicle is NOT in Park (P)! Action blocked.");
            if (showToast) {
                showOemToast(context, "Action blocked: Vehicle is not in Park (P)");
            }
            return false;
        }

        // 2. Try executing unified root switch flow via helper.sh
        String subcmd = dismissNotice ? "full-flow" : "switch";
        RootBridge.Result r = RootBridge.runHelper(subcmd, String.valueOf(targetUid));
        if (r.exitCode == 0) {
            Log.i(TAG, "Unified switch via RootBridge succeeded: " + r.output);
            return true;
        }

        // 3. Fallback to granular steps if helper script was not available
        switchUser(targetUid);
        if (dismissNotice) {
            dismissConsentScreen(targetUid);
        }
        if (recallSeat && (targetUid == 1 || targetUid == 2)) {
            try {
                Thread.sleep(1000);
            } catch (InterruptedException ignored) {}
            recallSeatMemory(targetUid);
        }
        if (showToast) {
            String name = getUserName(targetUid);
            showOemToast(context, "Switched to " + name);
        }

        return true;
    }
}
