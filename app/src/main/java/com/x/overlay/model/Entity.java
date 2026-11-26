package com.x.overlay.model;
public class Entity {
    public float x, y, w, h; public int id; static int next = 0;
    public Entity(float x, float y, float w, float h) { this.x=x; this.y=y; this.w=w; this.h=h; this.id=next++; }
}
