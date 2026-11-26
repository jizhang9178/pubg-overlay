#!/usr/bin/env bash
set -e

echo "[1/4] 建目录"
mkdir -p app/src/main/java/com/x/overlay/{model,detect,data,proj}
mkdir -p app/src/main/res/values
mkdir -p .github/workflows

echo "[2/4] 写 Gradle 配置"
cat > settings.gradle <<'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "PubgOverlay"
include ':app'
EOF

cat > build.gradle <<'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
}
EOF

cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2048m
android.useAndroidX=true
EOF

cat > app/build.gradle <<'EOF'
plugins { id 'com.android.application' }

android {
    namespace 'com.x.overlay'
    compileSdk 34
    defaultConfig {
        applicationId "com.x.overlay"
        minSdk 26
        targetSdk 34
        versionCode 1
        versionName "1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
}
dependencies { implementation 'androidx.core:core:1.12.0' }
EOF

cat > app/src/main/res/values/strings.xml <<'EOF'
<resources>
    <string name="app_name">SysService</string>
</resources>
EOF

cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <application
        android:label="@string/app_name"
        android:allowBackup="false"
        android:theme="@android:style/Theme.DeviceDefault">

        <service
            android:name=".OverlayService"
            android:exported="false"
            android:foregroundServiceType="mediaProjection"/>

        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

echo "[3/4] 写 Java 源码"
cat > app/src/main/java/com/x/overlay/model/Entity.java <<'EOF'
package com.x.overlay.model;

public class Entity {
    public float x, y, w, h;
    public int id;
    static int next = 0;

    public Entity(float x, float y, float w, float h) {
        this.x = x;
        this.y = y;
        this.w = w;
        this.h = h;
        this.id = next++;
    }
}
EOF

cat > app/src/main/java/com/x/overlay/model/Box.java <<'EOF'
package com.x.overlay.model;

public class Box {
    public float left, top, right, bottom;
    public float dist;
    public Box(float l, float t, float r, float b) {
        left = l; top = t; right = r; bottom = b;
    }
}
EOF

cat > app/src/main/java/com/x/overlay/detect/RedDetector.java <<'EOF'
package com.x.overlay.detect;

import android.graphics.Bitmap;
import com.x.overlay.model.Entity;

import java.util.ArrayList;
import java.util.List;

public class RedDetector {
    public static List<Entity> detect(Bitmap bmp, int w, int h) {
        int step = 3;
        int sw = w / step, sh = h / step;
        boolean[] mask = new boolean[sw * sh];
        int[] px = new int[w * h];
        bmp.getPixels(px, 0, w, 0, 0, w, h);

        for (int y = 0; y < sh; y++) {
            int yy = y * step;
            for (int x = 0; x < sw; x++) {
                int c = px[yy * w + x * step];
                int r = (c >> 16) & 0xFF;
                int g = (c >> 8) & 0xFF;
                int b = c & 0xFF;
                if (r > 170 && g < 95 && b < 95 && r - g > 70 && r - b > 70) {
                    mask[y * sw + x] = true;
                }
            }
        }

        List<Entity> out = new ArrayList<>();
        boolean[] visited = new boolean[sw * sh];
        int minArea = 12;
        int[] stack = new int[sw * sh];

        for (int i = 0; i < mask.length; i++) {
            if (!mask[i] || visited[i]) continue;
            int sp = 0;
            stack[sp++] = i;
            visited[i] = true;
            int minX = Integer.MAX_VALUE, maxX = 0, minY = Integer.MAX_VALUE, maxY = 0, cnt = 0;

            while (sp > 0) {
                int cur = stack[--sp];
                int cx = cur % sw, cy = cur / sw;
                if (cx < minX) minX = cx;
                if (cx > maxX) maxX = cx;
                if (cy < minY) minY = cy;
                if (cy > maxY) maxY = cy;
                cnt++;
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        int nx = cx + dx, ny = cy + dy;
                        if (nx < 0 || nx >= sw || ny < 0 || ny >= sh) continue;
                        int ni = ny * sw + nx;
                        if (mask[ni] && !visited[ni]) {
                            visited[ni] = true;
                            stack[sp++] = ni;
                        }
                    }
                }
            }

            if (cnt < minArea) continue;
            float boxW = (maxX - minX) * step;
            float boxH = (maxY - minY) * step;
            float ratio = boxW / Math.max(boxH, 1);
            if (ratio < 1.5f || ratio > 12f) continue;

            float cx = ((minX + maxX) * 0.5f) * step;
            float cy = ((minY + maxY) * 0.5f) * step;
            out.add(new Entity(cx, cy, boxW, boxH));
        }
        return out;
    }
}
EOF

cat > app/src/main/java/com/x/overlay/data/NoRootDataSource.java <<'EOF'
package com.x.overlay.data;

import android.content.Intent;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.util.DisplayMetrics;

import com.x.overlay.detect.RedDetector;
import com.x.overlay.model.Entity;

import java.nio.ByteBuffer;
import java.util.Collections;
import java.util.List;

public class NoRootDataSource {
    public final int capW, capH;
    MediaProjection mp;
    VirtualDisplay vd;
    ImageReader reader;
    volatile boolean alive = true;

    public NoRootDataSource(MediaProjectionManager mpm, int code, Intent data) {
        DisplayMetrics dm = Resources.getSystem().getDisplayMetrics();
        capW = dm.widthPixels;
        capH = dm.heightPixels;
        int dpi = dm.densityDpi;

        mp = mpm.getMediaProjection(code, data);
        mp.registerCallback(new MediaProjection.Callback() {}, null);

        reader = ImageReader.newInstance(capW, capH, PixelFormat.RGBA_8888, 3);
        vd = mp.createVirtualDisplay(
            "cap", capW, capH, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.getSurface(), null, null);
    }

    public List<Entity> poll() {
        if (!alive) return Collections.emptyList();
        Image img = reader.acquireLatestImage();
        if (img == null) return Collections.emptyList();
        try {
            Image.Plane p = img.getPlanes()[0];
            ByteBuffer buf = p.getBuffer();
            int rowStride = p.getRowStride();
            int pixelStride = p.getPixelStride();
            Bitmap bmp = Bitmap.createBitmap(capW + rowStride / pixelStride,
                capH, Bitmap.Config.ARGB_8888);
            bmp.copyPixelsFromBuffer(buf);
            Bitmap cropped = Bitmap.createBitmap(bmp, 0, 0, capW, capH);
            return RedDetector.detect(cropped, capW, capH);
        } finally {
            img.close();
        }
    }

    public void release() {
        alive = false;
        if (vd != null) vd.release();
        if (reader != null) reader.close();
        if (mp != null) mp.stop();
    }
}
EOF

cat > app/src/main/java/com/x/overlay/proj/ImageProjector.java <<'EOF'
package com.x.overlay.proj;

import com.x.overlay.data.NoRootDataSource;
import com.x.overlay.model.Box;
import com.x.overlay.model.Entity;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class ImageProjector {
    final float LATENCY_MS = 45f;
    final int capW, capH;
    final int viewW, viewH;
    Map<Integer, float[]> last = new HashMap<>();
    long lastT = 0;

    public ImageProjector(NoRootDataSource src, int viewW, int viewH) {
        this.capW = src.capW;
        this.capH = src.capH;
        this.viewW = viewW;
        this.viewH = viewH;
    }

    public List<Box> project(List<Entity> ents) {
        long now = System.nanoTime() / 1_000_000;
        long dt = now - lastT;
        float sx = viewW / (float) capW;
        float sy = viewH / (float) capH;
        List<Box> out = new ArrayList<>();

        for (Entity e : ents) {
            float px = e.x * sx;
            float py = e.y * sy;
            float pw = e.w * sx;

            float[] prev = last.get(e.id);
            if (prev != null && dt > 0 && dt < 200) {
                float vx = (px - prev[0]) / dt;
                float vy = (py - prev[1]) / dt;
                px += vx * LATENCY_MS;
                py += vy * LATENCY_MS;
            }
            last.put(e.id, new float[]{px, py});

            float boxW = Math.max(pw, 20f);
            float boxH = boxW * 4.5f;
            float left = px - boxW / 2;
            float right = px + boxW / 2;
            float top = py - boxH;
            float bottom = py + 4;

            Box b = new Box(left, top, right, bottom);
            b.dist = boxH / 10f;
            out.add(b);
        }
        lastT = now;
        return out;
    }
}
EOF

cat > app/src/main/java/com/x/overlay/MainActivity.java <<'EOF'
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
    static final int REQ_OVERLAY = 100;
    static final int REQ_CAPTURE = 200;
    TextView status;
    Button start;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        LinearLayout ll = new LinearLayout(this);
        ll.setOrientation(LinearLayout.VERTICAL);
        ll.setPadding(60, 120, 60, 60);

        status = new TextView(this);
        status.setTextSize(16);
        status.setText("1. 授权悬浮窗\n2. 授权录屏\n3. 启动");
        ll.addView(status);

        start = new Button(this);
        start.setText("开始");
        start.setOnClickListener(v -> ensureOverlay());
        ll.addView(start);

        setContentView(ll);
    }

    void ensureOverlay() {
        if (!Settings.canDrawOverlays(this)) {
            status.setText("请授权悬浮窗...");
            startActivityForResult(new Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + getPackageName())), REQ_OVERLAY);
        } else {
            requestCapture();
        }
    }

    void requestCapture() {
        status.setText("请授权录屏...");
        MediaProjectionManager mpm =
            (MediaProjectionManager) getSystemService(MEDIA_PROJECTION_SERVICE);
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE);
    }

    @Override protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == REQ_OVERLAY) {
            if (Settings.canDrawOverlays(this)) requestCapture();
            else status.setText("悬浮窗未授权");
        } else if (req == REQ_CAPTURE && res == RESULT_OK && data != null) {
            status.setText("启动中...");
            Intent svc = new Intent(this, OverlayService.class);
            svc.putExtra("code", res);
            svc.putExtra("data", data);
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(svc);
            else startService(svc);
            finish();
        }
    }
}
EOF

cat > app/src/main/java/com/x/overlay/OverlayService.java <<'EOF'
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

        while (running) {
            List<Entity> ents = source.poll();
            List<Box> boxes = projector.project(ents);
            Canvas c = sv.lockCanvas();
            if (c != null) {
                c.drawColor(Color.TRANSPARENT, android.graphics.PorterDuff.Mode.CLEAR);
                for (Box b : boxes) {
                    c.drawRect(b.left, b.top, b.right, b.bottom, boxPaint);
                    c.drawText(String.format("%.0fm", b.dist),
                        b.left, b.top - 6, textPaint);
                }
                sv.unlockCanvasAndPost(c);
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
EOF

cat > .github/workflows/build.yml <<'EOF'
name: Build APK
on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - uses: android-actions/setup-android@v3

      - name: Build debug APK
        run: |
          gradle wrapper --gradle-version 8.5
          chmod +x gradlew
          ./gradlew assembleDebug --no-daemon

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: app/build/outputs/apk/debug/app-debug.apk

      - name: Create Release
        uses: softprops/action-gh-release@v2
        if: github.ref == 'refs/heads/main'
        with:
          tag_name: v1.0.${{ github.run_number }}
          files: app/build/outputs/apk/debug/app-debug.apk
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF

echo "[4/4] 提交并推送"
git add -A
git commit -m "init overlay project"
git push

echo ""
echo "完成。去仓库 Actions 页看编译，绿了去 Releases 页下 APK。"
