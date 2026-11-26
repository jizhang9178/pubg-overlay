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
    public final int capW, capH; MediaProjection mp; VirtualDisplay vd; ImageReader reader; volatile boolean alive = true;
    public NoRootDataSource(MediaProjectionManager mpm, int code, Intent data) {
        DisplayMetrics dm = Resources.getSystem().getDisplayMetrics();
        capW = dm.widthPixels; capH = dm.heightPixels;
        mp = mpm.getMediaProjection(code, data); mp.registerCallback(new MediaProjection.Callback() {}, null);
        reader = ImageReader.newInstance(capW, capH, PixelFormat.RGBA_8888, 3);
        vd = mp.createVirtualDisplay("cap", capW, capH, dm.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.getSurface(), null, null);
    }
    public List<Entity> poll() {
        if (!alive) return Collections.emptyList();
        Image img = reader.acquireLatestImage(); if (img == null) return Collections.emptyList();
        try {
            Image.Plane p = img.getPlanes()[0]; ByteBuffer buf = p.getBuffer();
            Bitmap bmp = Bitmap.createBitmap(capW + p.getRowStride() / p.getPixelStride(), capH, Bitmap.Config.ARGB_8888);
            bmp.copyPixelsFromBuffer(buf);
            return RedDetector.detect(Bitmap.createBitmap(bmp, 0, 0, capW, capH), capW, capH);
        } finally { img.close(); }
    }
    public void release() { alive = false; if (vd != null) vd.release(); if (reader != null) reader.close(); if (mp != null) mp.stop(); }
}
