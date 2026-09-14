// ---------------------------------------------------------------------------
// 2D interface: SDF rounded rectangles & strokes, SDF text, images, icons
// ---------------------------------------------------------------------------

struct UIVertexIn {
    float2 pos    [[attribute(0)]];
    float2 uv     [[attribute(1)]];
    float4 color  [[attribute(2)]];   // linear, straight alpha
    float4 rect   [[attribute(3)]];   // xy local offset from rect centre (pt), zw half size
    float4 params [[attribute(4)]];   // x radius / sdf softness, y border or blur, z mode, w texture layer
};

struct UIVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float4 rect;
    float4 params;
};

struct UIUniforms {
    float4 size;   // xy viewport in points, zw pixels per point
};

vertex UIVertexOut ui_vertex(UIVertexIn in [[stage_in]], constant UIUniforms &u [[buffer(1)]]) {
    UIVertexOut o;
    o.position = float4(in.pos.x / u.size.x * 2.0 - 1.0, 1.0 - in.pos.y / u.size.y * 2.0, 0.0, 1.0);
    o.uv = in.uv;
    o.color = in.color;
    o.rect = in.rect;
    o.params = in.params;
    return o;
}

static float roundedBoxSDF(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

fragment float4 ui_fragment(UIVertexOut in [[stage_in]],
                            constant UIUniforms &u [[buffer(1)]],
                            texture2d<float> font [[texture(0)]],
                            texture2d<float> image [[texture(1)]],
                            texture2d_array<float> blocks [[texture(2)]],
                            texture2d_array<float> items [[texture(3)]],
                            sampler linearSampler [[sampler(0)]],
                            sampler nearestSampler [[sampler(1)]]) {
    int mode = int(in.params.z + 0.5);
    float4 c = in.color;
    float px = 1.0 / max(u.size.z, 1.0);   // one physical pixel in points

    if (mode == 0) {            // filled rounded rect (optionally blurred for shadows)
        float d = roundedBoxSDF(in.rect.xy, in.rect.zw, in.params.x);
        float soft = max(in.params.y, px * 0.75);
        float a = 1.0 - smoothstep(-soft, soft, d);
        return float4(c.rgb * c.a * a, c.a * a);
    }
    if (mode == 1) {            // stroked rounded rect
        float d = roundedBoxSDF(in.rect.xy, in.rect.zw, in.params.x);
        float w = in.params.y;
        float outer = 1.0 - smoothstep(-px, px, d);
        float inner = smoothstep(-px, px, d + w);
        float a = outer * inner;
        return float4(c.rgb * c.a * a, c.a * a);
    }
    if (mode == 2) {            // SDF glyph; params.x = extra softness (shadow/glow), params.y = dilation
        float s = font.sample(linearSampler, in.uv).r;
        float w = max(fwidth(s) * 0.75, 0.001) + in.params.x;
        float edge = 0.5 - in.params.y;
        float a = smoothstep(edge - w, edge + w, s);
        return float4(c.rgb * c.a * a, c.a * a);
    }
    if (mode == 3) {            // premultiplied RGBA image
        float4 t = image.sample(linearSampler, in.uv);
        return float4(t.rgb * c.rgb, t.a) * c.a;
    }
    if (mode == 4) {            // block texture (isometric icon faces), tinted for shading
        float4 t = blocks.sample(nearestSampler, in.uv, uint(in.params.w));
        if (t.a < 0.5 && in.params.x > 0.5) discard_fragment();
        return float4(t.rgb * c.rgb, t.a) * c.a;
    }
    if (mode == 5) {            // item sprite
        float4 t = items.sample(nearestSampler, in.uv, uint(in.params.w));
        return float4(t.rgb * c.rgb, t.a) * c.a;
    }
    if (mode == 6) {            // filled circle / ring (params.y = ring thickness, 0 = filled)
        float d = length(in.rect.xy) - in.rect.z;
        float a = 1.0 - smoothstep(-px, px, d);
        if (in.params.y > 0.0) a *= smoothstep(-px, px, d + in.params.y);
        return float4(c.rgb * c.a * a, c.a * a);
    }
    return c;
}
