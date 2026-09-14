// Shader packs: fullscreen post-processing of the scene color target.

struct PostUniforms {
    float4 params;   // x preset (0 off, 1 vibrant, 2 cinematic, 3 retro, 4 dreamy), y time, zw size in pixels
    float4 extra;    // x strength
};

struct PostOut {
    float4 position [[position]];
    float2 uv;
};

vertex PostOut post_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    PostOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

static float pp_luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

static float pp_hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

static float3 pp_blur(texture2d<float> t, sampler s, float2 uv, float2 px, float radius) {
    float3 acc = t.sample(s, uv).rgb * 0.2;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + 0.3;
        acc += t.sample(s, uv + float2(cos(a), sin(a)) * px * radius).rgb * 0.05;
        acc += t.sample(s, uv + float2(cos(a), sin(a)) * px * radius * 2.2).rgb * 0.05;
    }
    return acc;
}

static float3 pp_gamma(float3 c) { return pow(max(c, float3(0.0)), float3(1.0 / 2.2)); }

fragment float4 post_fragment(PostOut in [[stage_in]],
                              texture2d<float> scene [[texture(0)]],
                              sampler s [[sampler(0)]],
                              constant PostUniforms& u [[buffer(0)]]) {
    int preset = int(u.params.x + 0.5);
    float time = u.params.y;
    float2 size = max(u.params.zw, float2(1.0));
    float strength = clamp(u.extra.x, 0.0, 1.0);
    float2 uv = in.uv;
    float2 px = 1.0 / size;

    float3 base = scene.sample(s, uv).rgb;
    float3 g = pp_gamma(base);
    float2 q = uv - 0.5;
    float vignette = clamp(1.0 - dot(q, q) * 1.5, 0.0, 1.0);

    if (preset == 1) {
        // Vibrant
        float l = pp_luma(g);
        g = mix(float3(l), g, 1.4);
        g = (g - 0.5) * 1.1 + 0.5;
        g *= float3(1.03, 1.0, 0.97);
        g *= mix(1.0, vignette, 0.45);
    } else if (preset == 2) {
        // Cinematic
        float3 glow = pp_gamma(pp_blur(scene, s, uv, px, 7.0));
        g += max(glow - 0.62, float3(0.0)) * 1.6;
        float l = pp_luma(g);
        g += mix(float3(-0.02, 0.05, 0.09), float3(0.10, 0.04, -0.05), smoothstep(0.15, 0.85, l)) * 0.7;
        g = smoothstep(float3(-0.06), float3(1.06), g);
        g *= mix(1.0, vignette, 0.85);
        g += (pp_hash(floor(uv * size) + fract(time) * 91.0) - 0.5) * 0.04;
        float bar = 0.055;
        if (uv.y < bar || uv.y > 1.0 - bar) g = float3(0.0);
    } else if (preset == 3) {
        // Retro
        float cell = max(2.0, floor(size.y / 300.0));
        float2 puv = (floor(uv * size / cell) + 0.5) * cell / size;
        float3 r = scene.sample(s, puv + float2(px.x * cell * 0.5, 0.0)).rgb;
        float3 m = scene.sample(s, puv).rgb;
        float3 b = scene.sample(s, puv - float2(px.x * cell * 0.5, 0.0)).rgb;
        g = pp_gamma(float3(r.r, m.g, b.b));
        g = floor(g * 5.0 + 0.5) / 5.0;
        float scan = 0.82 + 0.18 * (0.5 + 0.5 * sin(uv.y * size.y / cell * 3.14159));
        g *= scan;
        g *= mix(1.0, vignette, 0.75);
    } else if (preset == 4) {
        // Dreamy
        float3 soft = pp_gamma(pp_blur(scene, s, uv, px, 5.0));
        g = mix(g, max(g, soft), 0.6);
        float l = pp_luma(g);
        g = mix(float3(l), g, 0.82);
        g = g * 0.88 + 0.09;
        g *= float3(1.05, 0.97, 1.07);
        g *= mix(1.0, vignette, 0.35);
    }

    float3 graded = pow(clamp(g, float3(0.0), float3(1.0)), float3(2.2));
    return float4(mix(base, graded, strength), 1.0);
}
