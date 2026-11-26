package com.x.overlay.detect;
import android.graphics.Bitmap;
import com.x.overlay.model.Entity;
import java.util.ArrayList;
import java.util.List;
public class RedDetector {
    public static List<Entity> detect(Bitmap bmp, int w, int h) {
        int step = 3; int sw = w / step, sh = h / step;
        boolean[] mask = new boolean[sw * sh];
        int[] px = new int[w * h]; bmp.getPixels(px, 0, w, 0, 0, w, h);
        for (int y = 0; y < sh; y++) {
            int yy = y * step;
            for (int x = 0; x < sw; x++) {
                int c = px[yy * w + x * step]; int r = (c >> 16) & 0xFF, g = (c >> 8) & 0xFF, b = c & 0xFF;
                if (r > 170 && g < 95 && b < 95 && r - g > 70 && r - b > 70) mask[y * sw + x] = true;
            }
        }
        List<Entity> out = new ArrayList<>();
        boolean[] visited = new boolean[sw * sh]; int minArea = 12; int[] stack = new int[sw * sh];
        for (int i = 0; i < mask.length; i++) {
            if (!mask[i] || visited[i]) continue;
            int sp = 0; stack[sp++] = i; visited[i] = true;
            int minX = Integer.MAX_VALUE, maxX = 0, minY = Integer.MAX_VALUE, maxY = 0, cnt = 0;
            while (sp > 0) {
                int cur = stack[--sp]; int cx = cur % sw, cy = cur / sw;
                if (cx < minX) minX = cx; if (cx > maxX) maxX = cx; if (cy < minY) minY = cy; if (cy > maxY) maxY = cy; cnt++;
                for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
                    int nx = cx + dx, ny = cy + dy;
                    if (nx >= 0 && nx < sw && ny >= 0 && ny < sh) {
                        int ni = ny * sw + nx;
                        if (mask[ni] && !visited[ni]) { visited[ni] = true; stack[sp++] = ni; }
                    }
                }
            }
            if (cnt < minArea) continue;
            float boxW = (maxX - minX) * step, boxH = (maxY - minY) * step;
            float ratio = boxW / Math.max(boxH, 1); if (ratio < 1.5f || ratio > 12f) continue;
            out.add(new Entity(((minX + maxX) * 0.5f) * step, ((minY + maxY) * 0.5f) * step, boxW, boxH));
        }
        return out;
    }
}
