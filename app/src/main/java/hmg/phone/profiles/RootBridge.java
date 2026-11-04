package hmg.phone.profiles;

import android.util.Log;

import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;

/**
 * RootBridge executes privileged vehicle commands via NEMESIS root channel,
 * su, or direct fallback shell.
 *
 * On Gen5W systems with NEMESIS installed, `/system/xbin/nemesis root -c "<cmd>"`
 * connects to the privileged watchdog daemon socket, allowing applications to
 * run root commands (uid=0) with full Binder access.
 */
public class RootBridge {
    private static final String TAG = "HmgPhoneProfiles.RootBridge";

    public static final String NEMESIS_BIN = "/system/xbin/nemesis";
    public static final String HELPER_PATH = "/data/nemesis/apps/hmg-phone-profiles/svc/helper.sh";
    public static final String LEGACY_HELPER_PATH = "/data/nemesis/apps/autoprofile.selector/svc/helper.sh";
    public static final String FALLBACK_HELPER_PATH = "/data/local/tmp/helper.sh";

    public static class Result {
        public final int exitCode;
        public final String output;

        public Result(int exitCode, String output) {
            this.exitCode = exitCode;
            this.output = output != null ? output : "";
        }

        public boolean isSuccess() {
            return exitCode == 0;
        }

        @Override
        public String toString() {
            return "Result{rc=" + exitCode + ", out='" + output.trim() + "'}";
        }
    }

    /**
     * Executes a command with root privileges.
     * Tries NEMESIS root bridge first, then su, then /system/bin/sh.
     */
    public static Result runCommand(String shellCmd) {
        if (shellCmd == null || shellCmd.trim().isEmpty()) {
            return new Result(-1, "Empty command");
        }

        // 1. Primary: NEMESIS root bridge (/system/xbin/nemesis root -c "<cmd>")
        File nemFile = new File(NEMESIS_BIN);
        if (nemFile.exists()) {
            Result res = execProcess(new String[]{NEMESIS_BIN, "root", "-c", shellCmd});
            if (res.exitCode == 0 || !res.output.isEmpty()) {
                return res;
            }
        }

        // 2. Secondary: Standard su -c "<cmd>"
        Result suRes = execProcess(new String[]{"su", "-c", shellCmd});
        if (suRes.exitCode == 0 || !suRes.output.isEmpty()) {
            return suRes;
        }

        // 3. Fallback: Direct shell execution
        return execProcess(new String[]{"/system/bin/sh", "-c", shellCmd});
    }

    /**
     * Executes a helper.sh subcommand through the root bridge.
     */
    public static Result runHelper(String subcmd, String... args) {
        String helper = getHelperExecutable();
        StringBuilder sb = new StringBuilder();
        sb.append(helper).append(" ").append(subcmd);
        if (args != null) {
            for (String arg : args) {
                sb.append(" ").append(arg);
            }
        }
        return runCommand(sb.toString());
    }

    /**
     * Discovers the location of helper.sh on the device.
     */
    public static String getHelperExecutable() {
        if (new File(HELPER_PATH).exists()) {
            return HELPER_PATH;
        }
        if (new File(LEGACY_HELPER_PATH).exists()) {
            return LEGACY_HELPER_PATH;
        }
        if (new File(FALLBACK_HELPER_PATH).exists()) {
            return FALLBACK_HELPER_PATH;
        }
        return HELPER_PATH;
    }

    private static Result execProcess(String[] cmd) {
        Process p = null;
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            p = pb.start();

            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            InputStream in = p.getInputStream();
            byte[] buf = new byte[2048];
            int n;
            while ((n = in.read(buf)) > 0) {
                bos.write(buf, 0, n);
            }
            in.close();

            int rc = p.waitFor();
            String out = bos.toString("UTF-8");
            return new Result(rc, out);
        } catch (Throwable t) {
            Log.w(TAG, "execProcess failed for " + (cmd.length > 0 ? cmd[0] : "") + ": " + t.getMessage());
            return new Result(-1, "ERR: " + t.getMessage());
        } finally {
            if (p != null) {
                try {
                    p.destroy();
                } catch (Throwable ignored) {}
            }
        }
    }
}
