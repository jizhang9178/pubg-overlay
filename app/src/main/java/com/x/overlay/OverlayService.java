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
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.WindowManager;
import android.widget.TextView;

import com.x.overlay.data.NoRootDataSource;
import com.x.overlay.model.Box;
import com.x.overlay.model.Entity;
import com.x.overlay.proj.ImageProjector;

import java.util.List;

public class OverlayService extends Service {
    WindowManager wm;
    SurfaceView sv;
    TextView tip;
    NoRootDataSource source;
    ImageProjector projector;
    volatile boolean running = true;

    @Override public int onStartCommand(Intent it, int flags, int startId) {
        startForeground(1, buildNotification());

        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        DisplayMetrics dm = getResources().getDisplayMetrics();

        tip = new TextView(this);
        tip.setTextColor(Color.GREEN);
        tip.setTextSize(14);
        WindowManager.LayoutParams tlp = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            Build.VERSION.SDK_INT >= 26
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT);
        tlp.gravity = Gravity.TOP | Gravity.START;
        tlp.x = 20; tlp.y = 20;
        wm.addView(tip, tlp);

        sv = new SurfaceView(this);
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            Build.VERSION.SDK_INT >= 26
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        wm.addView(sv, lp);

        int code = it.getIntExtra("code", -1);
        Intent data = it.getParcelableExtra("data");
        if (code == -1 || data == null) { stopSelf(); return START_NOT_STICKY; }

        MediaProjectionManager mpm =
            (MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE);
        source = new NoRootDataSource(mpm, code, data);
        projector = new ImageProjector(source, dm.widthPixels, dm.heightPixels);

        new Thread(this::renderLoop, "overlay-render").start();
        return START_STICKY;
    }

    void renderLoop() {
        Paint boxPaint = new Paint();
        boxPaint.setStyle(Paint.Style.STROKE);
        boxPaint.setStrokeWidth(2f);
        boxPaint.setColor(Color.RED);
        boxPaint.setAntiAlias(true);

        Paint textPaint = new Paint();
        textPaint.setColor(Color.YELLOW);
        textPaint.setTextSize(26f);
        textPaint.setAntiAlias(true);

        SurfaceHolder holder = sv.getHolder();

        while (running) {
            List<Entity> ents = source.poll();
            List<Box> boxes = projector.project(ents);
            
            Canvas c = holder.lockCanvas();
            if (c != null) {
                c.drawColor(Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR);
                for (Box b : boxes) {
                    c.drawRect(b.left, b.top, b.right, b.bottom, boxPaint);
                    c.drawText(String.format("%.0fm", b.dist),
                        b.left, b.top - 6, textPaint);
                }
                holder.unlockCanvasAndPost(c);
            }
            tip.setText("ESP 运行中 | 目标 " + boxes.size());
            try { Thread.sleep(16); } catch (InterruptedException e) { break; }
        }
    }

    Notification buildNotification() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(
                "ov", "SysService", NotificationManager.IMPORTANCE_LOW);
            NotificationManager nm = getSystemService(NotificationManager.class);
            nm.createNotificationChannel(ch);
            return new Notification.Builder(this, "ov")
                .setContentTitle("SysService")
                .setSmallIcon(android.R.drawable.ic_menu_info_details)
                .build();
        }
        return new Notification.Builder(this)
            .setContentTitle("SysService")
            .setSmallIcon(android.R.drawable.ic_menu_info_details)
            .build();
    }

    @Override public void onDestroy() {
        running = false;
        if (source != null) source.release();
        if (sv != null && sv.getParent() != null) wm.removeView(sv);
        if (tip != null && tip.getParent() != null) wm.removeView(tip);
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent it) { return null; }
}
