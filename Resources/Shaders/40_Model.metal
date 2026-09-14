// ---------------------------------------------------------------------------
// Models: dropped items, the held item / hand, creatures
// ---------------------------------------------------------------------------

struct ModelVertexIn {
    float3 pos    [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv     [[attribute(2)]];
    float4 color  [[attribute(3)]];
    float4 params [[attribute(4)]];   // x layer, y set (0 blocks, 1 items, 2 vertex colour), z cutout, w emissive
};

struct ModelUniforms {
    float4x4 mvp;
    float4x4 model;       // object → world-oriented space (for normals)
    float4 light;         // x sky 0..1, y block 0..1, z 1 = first-person (no fog), w unused
    float4 tint;          // rgb additive tint, w strength (hurt flash)
    float4 viewPos;       // camera-relative position (for fog)
};

struct ModelVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float3 normal;
    float layer [[flat]];
    float set [[flat]];
    float cutout [[flat]];
    float emissive [[flat]];
};

vertex ModelVertexOut model_vertex(ModelVertexIn in [[stage_in]], constant ModelUniforms &u [[buffer(2)]]) {
    ModelVertexOut o;
    o.position = u.mvp * float4(in.pos, 1.0);
    o.normal = normalize((u.model * float4(in.normal, 0.0)).xyz);
    o.uv = in.uv;
    o.color = in.color;
    o.layer = in.params.x;
    o.set = in.params.y;
    o.cutout = in.params.z;
    o.emissive = in.params.w;
    return o;
}

fragment float4 model_fragment(ModelVertexOut in [[stage_in]],
                               constant FrameUniforms &f [[buffer(1)]],
                               constant ModelUniforms &u [[buffer(2)]],
                               texture2d_array<float> blocks [[texture(0)]],
                               texture2d_array<float> items [[texture(1)]],
                               sampler s [[sampler(0)]]) {
    float4 c;
    if (in.set < 0.5) {
        c = blocks.sample(s, in.uv, uint(in.layer));
    } else if (in.set < 1.5) {
        c = items.sample(s, in.uv, uint(in.layer));
    } else {
        c = float4(1.0);
    }
    if (in.cutout > 0.5 && c.a < 0.5) discard_fragment();
    float3 albedo = (in.set < 1.5 ? c.rgb / max(c.a, 0.001) : c.rgb) * in.color.rgb;

    float3 n = in.normal;
    float side = mix(0.82, 0.66, abs(n.x) / max(0.001, abs(n.x) + abs(n.z)));
    float shade = mix(side, n.y > 0.0 ? 1.0 : 0.52, abs(n.y));
    uint flags = in.emissive > 0.5 ? 16u : 0u;
    float3 lit = albedo * terrainLighting(u.light.x, u.light.y, shade, flags, f);
    lit = mix(lit, u.tint.rgb, u.tint.w);
    if (u.light.z < 0.5) lit = applyFog(lit, u.viewPos.xyz, f);
    return float4(lit, 1.0);
}
