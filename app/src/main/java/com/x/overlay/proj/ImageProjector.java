package com.x.overlay.proj;
import com.x.overlay.data.NoRootDataSource;
import com.x.overlay.model.Box;
import com.x.overlay.model.Entity;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
public class ImageProjector {
    final float LATENCY_MS = 45f; final int capW, capH, viewW, viewH;
    Map<Integer, float[]> last = new HashMap<>(); long lastT = 0;
    public ImageProjector(NoRootDataSource src, int viewW, int viewH) { this.capW = src.capW; this.capH = src.capH; this.viewW = viewW; this.viewH = viewH; }
    public List<Box> project(List<Entity> ents) {
        long now = System.nanoTime() / 1_000_000; long dt = now - lastT;
        float sx = viewW / (float) capW, sy = viewH / (float) capH;
        List<Box> out = new ArrayList<>();
        for (Entity e : ents) {
            float px = e.x * sx, py = e.y * sy, pw = e.w * sx;
            float[] prev = last.get(e.id);
            if (prev != null && dt > 0 && dt < 200) {
                float vx = (px - prev[0]) / dt, vy = (py - prev[1]) / dt;
                px += vx * LATENCY_MS; py += vy * LATENCY_MS;
            }
            last.put(e.id, new float[]{px, py});
            float boxW = Math.max(pw, 20f), boxH = boxW * 4.5f;
            Box b = new Box(px - boxW/2, py - boxH, px + boxW/2, py + 4);
            b.dist = boxH / 10f; out.add(b);
        }
        lastT = now; return out;
    }
}
