package com.x.overlay;
import android.app.Activity;
import android.content.Intent;
import android.media.projection.MediaProjectionManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
public class MainActivity extends Activity {
    static final int REQ_OVERLAY = 100, REQ_CAPTURE = 200; TextView status;
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b); LinearLayout ll = new LinearLayout(this); ll.setOrientation(LinearLayout.VERTICAL); ll.setPadding(60, 120, 60, 60);
        status = new TextView(this); status.setTextSize(16); status.setText("1. 授权悬浮窗\n2. 授权录屏\n3. 启动"); ll.addView(status);
        Button start = new Button(this); start.setText("开始"); start.setOnClickListener(v -> ensureOverlay()); ll.addView(start);
        setContentView(ll);
    }
    void ensureOverlay() {
        if (!Settings.canDrawOverlays(this)) { startActivityForResult(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getPackageName())), REQ_OVERLAY); }
        else { requestCapture(); }
    }
    void requestCapture() {
        MediaProjectionManager mpm = (MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE);
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE);
    }
    @Override protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_OVERLAY) { if (Settings.canDrawOverlays(this)) requestCapture(); }
        else if (req == REQ_CAPTURE && res == RESULT_OK && data != null) {
            Intent svc = new Intent(this, OverlayService.class); svc.putExtra("code", res); svc.putExtra("data", data);
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(svc); else startService(svc); finish();
        }
    }
}
