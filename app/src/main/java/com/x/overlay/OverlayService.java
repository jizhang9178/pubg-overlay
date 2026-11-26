package com.x.overlay;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.IBinder;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.SurfaceView;
import android.view.WindowManager;
import android.widget.TextView;
import com.x.overlay.data.NoRootDataSource;
import com.x.overlay.model.Box;
import com.x.overlay.model.Entity;
import com.x.overlay.proj.ImageProjector;
import java.util.List;
public class OverlayService extends Service {
    WindowManager wm; SurfaceView sv; TextView tip; NoRootDataSource source; ImageProjector projector; volatile boolean running = true;
    @Override public int onStartCommand(Intent it, int flags, int startId) {
        startForeground(1, buildNotification()); wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        DisplayMetrics dm = getResources().getDisplayMetrics();
        tip = new TextView(this); tip.setTextColor(Color.GREEN); tip.setTextSize(14);
        WindowManager.LayoutParams tlp = new WindowManager.LayoutParams(-2, -2, Build.VERSION.SDK_INT >= 26 ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE, PixelFormat.TRANSLUCENT);
        tlp.gravity = Gravity.TOP | Gravity.START; tlp.x = 20; tlp.y = 20; wm.addView(tip, tlp);
        sv = new SurfaceView(this);
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(-1, -1, Build.VERSION.SDK_INT >= 26 ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE, WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT);
        wm.addView(sv, lp);
        int code = it.getIntExtra("code", -1); Intent data = it.getParcelableExtra("data");
        if (code == -1 || data == null) { stopSelf(); return START_NOT_STICKY; }
        source = new NoRootDataSource((MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE), code, data);
        projector = new ImageProjector(source, dm.widthPixels, dm.heightPixels);
        new Thread(this::renderLoop, "overlay-render").start(); return START_STICKY;
    }
    void renderLoop() {
        Paint boxPaint = new Paint(); boxPaint.setStyle(Paint.Style.STROKE); boxPaint.setStrokeWidth(2f); boxPaint.setColor(Color.RED); boxPaint.setAntiAlias(true);
        Paint textPaint = new Paint(); textPaint.setColor(Color.YELLOW); textPaint.setTextSize(26f); textPaint.setAntiAlias(true);
        while (running) {
            List<Box> boxes = projector.project(source.poll()); Canvas c = sv.lockCanvas();
            if (c != null) {
                c.drawColor(Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR);
                for (Box b : boxes) { c.drawRect(b.left, b.top, b.right, b.bottom, boxPaint); c.drawText(String.format("%.0fm", b.dist), b.left, b.top - 6, textPaint); }
                sv.unlockCanvasAndPost(c);
            }
            tip.setText("ESP 运行中 | 目标 " + boxes.size());
            try { Thread.sleep(16); } catch (InterruptedException e) { break; }
        }
    }
    Notification buildNotification() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationManager nm = getSystemService(NotificationManager.class); nm.createNotificationChannel(new NotificationChannel("ov", "SysService", NotificationManager.IMPORTANCE_LOW));
            return new Notification.Builder(this, "ov").setContentTitle("SysService").setSmallIcon(android.R.drawable.ic_menu_info_details).build();
        }
        return new Notification.Builder(this).setContentTitle("SysService").setSmallIcon(android.R.drawable.ic_menu_info_details).build();
    }
    @Override public void onDestroy() { running = false; if (source != null) source.release(); if (sv != null) wm.removeView(sv); if (tip != null) wm.removeView(tip); super.onDestroy(); }
    @Override public IBinder onBind(Intent it) { return null; }
}
