package autoprofile.selector;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Starts ProfileSelectorService on boot or radio connectivity event.
 */
public class BootReceiver extends BroadcastReceiver {
    private static final String TAG = "AutoProfile.Boot";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (context == null || intent == null) return;
        String action = intent.getAction();
        Log.i(TAG, "BootReceiver triggered by action: " + action);

        ProfileConfig config = ProfileConfig.getInstance(context);
        if (config.autoSelect) {
            Intent svcIntent = new Intent(context, ProfileSelectorService.class);
            svcIntent.setAction(action);
            if (intent.getExtras() != null) {
                svcIntent.putExtras(intent.getExtras());
            }
            context.startService(svcIntent);
        }
    }
}
