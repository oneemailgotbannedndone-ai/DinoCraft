// Particles, rain streaks and snowflakes: camera-facing quads built on the CPU.

struct ParticleIn {
    float3 pos    [[attribute(0)]];   // camera-relative
    float2 uv     [[attribute(1)]];
    float4 color  [[attribute(2)]];
    float4 params [[attribute(3)]];   // x layer (>= 0 block texture, -1 soft dot, -2 square), y sky light, z block light, w emissive
};

struct ParticleOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float3 viewPos;
    float layer [[flat]];
    float sky [[flat]];
    float blockLight [[flat]];
    float emissive [[flat]];
};

vertex ParticleOut particle_vertex(ParticleIn in [[stage_in]], constant FrameUniforms &f [[buffer(1)]]) {
    ParticleOut o;
    o.position = f.viewProj * float4(in.pos, 1.0);
    o.uv = in.uv;
    o.color = in.color;
    o.viewPos = in.pos;
    o.layer = in.params.x;
    o.sky = in.params.y;
    o.blockLight = in.params.z;
    o.emissive = in.params.w;
    return o;
}

fragment float4 particle_fragment(ParticleOut in [[stage_in]],
                                  texture2d_array<float> blocks [[texture(0)]],
                                  sampler s [[sampler(0)]],
                                  constant FrameUniforms &f [[buffer(1)]]) {
    float4 c = in.color;
    if (in.layer >= 0.0) {
        float4 t = blocks.sample(s, in.uv, uint(in.layer));
        if (t.a < 0.5) discard_fragment();
        c.rgb *= t.rgb / max(t.a, 0.001);
    } else if (in.layer > -1.5) {
        float d = length(in.uv - 0.5) * 2.0;
        c.a *= saturate(1.0 - d * d);
    }
    if (c.a < 0.01) discard_fragment();
    float3 lit = in.emissive > 0.5 ? c.rgb : c.rgb * terrainLighting(in.sky, in.blockLight, 1.0, 0u, f);
    if (in.emissive < 0.5) lit = applyFog(lit, in.viewPos, f);
    return float4(lit * c.a, c.a);
}
