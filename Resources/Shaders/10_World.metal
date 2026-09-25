// ---------------------------------------------------------------------------
// Voxel terrain
// ---------------------------------------------------------------------------

struct ChunkVertexIn {
    ushort3 pos    [[attribute(0)]];
    ushort  layer  [[attribute(1)]];
    ushort2 uv     [[attribute(2)]];
    uchar   normal [[attribute(3)]];
    uchar   ao     [[attribute(4)]];
    float   sky    [[attribute(5)]];
    float   light  [[attribute(6)]];
    uchar   flags  [[attribute(7)]];
};

struct ChunkVertexOut {
    float4 position [[position]];
    float2 uv;
    uint   layer [[flat]];
    uint   flags [[flat]];
    float  shade;
    float  sky;
    float  light;
    float3 viewPos;
    float  normalY;
};

constant float kFaceShade[7] = { 0.66, 0.66, 1.0, 0.52, 0.82, 0.82, 0.88 };

vertex ChunkVertexOut chunk_vertex(ChunkVertexIn in [[stage_in]],
                                   constant FrameUniforms &f [[buffer(1)]],
                                   constant ChunkUniforms &c [[buffer(2)]]) {
    ChunkVertexOut o;
    float3 local = float3(in.pos) / 16.0;
    float3 p = local + c.origin.xyz;
    float3 wp = local + c.worldOrigin.xyz;
    float t = f.cameraPosTime.w;
    uint flags = in.flags;

    if (flags & 1u) {           // swaying leaves
        float ph = wp.x * 0.7 + wp.z * 0.5 + wp.y * 0.3;
        p.x += sin(t * 1.6 + ph) * 0.03;
        p.y += sin(t * 1.9 + ph * 1.3) * 0.015;
        p.z += cos(t * 1.4 + ph) * 0.03;
    }
    if (flags & 8u) {           // plant tops
        float ph = wp.x * 0.9 + wp.z * 0.7;
        p.x += sin(t * 2.1 + ph) * 0.08 + sin(t * 0.7 + ph * 0.2) * 0.04;
        p.z += cos(t * 1.7 + ph) * 0.06;
    }
    if ((flags & 2u) && in.normal == 2) {   // water surface swell
        p.y += (sin(t * 1.3 + wp.x * 0.8) * cos(t * 1.1 + wp.z * 0.7)) * 0.03 - 0.03;
    }

    // Gentle rise-in for freshly loaded chunks
    p.y -= (1.0 - c.origin.w) * 6.0;

    o.position = f.viewProj * float4(p, 1.0);

    float2 uv = float2(in.uv) / 16.0;
    if ((flags & 4u) == 0u) {
        uint n = in.normal;
        if (n == 0 || n == 1 || n == 4 || n == 5) uv.y = -uv.y;
        if (n == 0 || n == 5) uv.x = -uv.x;
    }
    if (flags & 2u) uv += float2(t * 0.04, t * 0.025);
    o.uv = uv;
    o.layer = in.layer;
    o.flags = flags;
    o.shade = kFaceShade[min(uint(in.normal), 6u)] * mix(0.40, 1.0, float(in.ao) / 3.0);
    o.sky = in.sky;
    o.light = in.light;
    o.viewPos = p;
    o.normalY = in.normal == 2 ? 1.0 : (in.normal == 3 ? -1.0 : 0.0);
    return o;
}

static float3 terrainLighting(float sky, float blockLight, float shade, uint flags, constant FrameUniforms &f) {
    if (flags & 16u) return float3(1.0);
    float daylight = f.sunDirDaylight.w;
    float s = lightCurve(sky) * daylight;
    float flicker = 0.96 + 0.04 * sin(f.cameraPosTime.w * 7.3 + blockLight * 13.0);
    float b = lightCurve(blockLight) * flicker;
    float3 skyC = f.skyLight.rgb * s;
    float3 blockC = float3(1.0, 0.78, 0.52) * b * 1.05;
    float3 l = max(skyC, blockC) + skyC * blockC * 0.15;
    float brightness = f.fogParams.z;
    float ambient = mix(0.012, 0.07, brightness);
    float3 dimensionAmbient = f.skyLight.rgb * f.dimension.x;
    l = l * shade + ambient + dimensionAmbient * shade;
    return pow(l, float3(mix(1.15, 0.72, brightness)));
}

static float3 applyFog(float3 color, float3 viewPos, constant FrameUniforms &f) {
    float d = length(viewPos);
    if (f.fogParams.y > 0.5) {
        float k = 1.0 - exp(-d * 0.06);
        return mix(color, float3(0.03, 0.14, 0.26) * max(0.25, f.sunDirDaylight.w), k);
    }
    float fogT = smoothstep(f.fogColorStart.w, f.fogParams.x, d);
    fogT = fogT * fogT;
    return mix(color, f.fogColorStart.rgb, fogT);
}

fragment float4 chunk_fragment_opaque(ChunkVertexOut in [[stage_in]],
                                      texture2d_array<float> tex [[texture(0)]],
                                      sampler s [[sampler(0)]],
                                      constant FrameUniforms &f [[buffer(1)]]) {
    float3 albedo = tex.sample(s, in.uv, in.layer).rgb;
    float3 lit = albedo * terrainLighting(in.sky, in.light, in.shade, in.flags, f);
    return float4(applyFog(lit, in.viewPos, f), 1.0);
}

fragment float4 chunk_fragment_cutout(ChunkVertexOut in [[stage_in]],
                                      texture2d_array<float> tex [[texture(0)]],
                                      sampler s [[sampler(0)]],
                                      constant FrameUniforms &f [[buffer(1)]]) {
    float4 c = tex.sample(s, in.uv, in.layer);
    if (c.a < 0.5) discard_fragment();
    float3 albedo = c.rgb / max(c.a, 0.001);
    float3 lit = albedo * terrainLighting(in.sky, in.light, in.shade, in.flags, f);
    return float4(applyFog(lit, in.viewPos, f), 1.0);
}

fragment float4 chunk_fragment_translucent(ChunkVertexOut in [[stage_in]],
                                           texture2d_array<float> tex [[texture(0)]],
                                           sampler s [[sampler(0)]],
                                           constant FrameUniforms &f [[buffer(1)]]) {
    float4 c = tex.sample(s, in.uv, in.layer);
    float a = c.a;
    if (a < 0.01) discard_fragment();
    float3 albedo = c.rgb / max(a, 0.001);
    float3 lit = albedo * terrainLighting(in.sky, in.light, in.shade, in.flags, f);

    if ((in.flags & 2u) && in.normalY > 0.5 && (in.flags & 16u) == 0u) {
        // Water: fresnel toward sky colour + sun glint
        float3 v = normalize(-in.viewPos);
        float fres = pow(1.0 - saturate(v.y), 4.0);
        lit = mix(lit, f.skyHorizon.rgb * max(0.2, f.sunDirDaylight.w), fres * 0.55);
        float3 h = normalize(v + f.sunDirDaylight.xyz);
        float spec = pow(saturate(h.y), 220.0) * f.sunDirDaylight.w * saturate(in.sky * 1.2);
        lit += float3(1.0, 0.95, 0.8) * spec * 1.4;
        a = mix(a, 1.0, fres * 0.5);
    }
    float3 fogged = applyFog(lit, in.viewPos, f);
    return float4(fogged * a, a);
}

// ---------------------------------------------------------------------------
// Sky: gradient, sun & moon, stars, procedural clouds
// ---------------------------------------------------------------------------

struct SkyOut {
    float4 position [[position]];
    float2 ndc;
};

vertex SkyOut sky_vertex(uint vid [[vertex_id]]) {
    const float2 pts[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    SkyOut o;
    o.position = float4(pts[vid], 0.0, 1.0);
    o.ndc = pts[vid];
    return o;
}

fragment float4 sky_fragment(SkyOut in [[stage_in]], constant FrameUniforms &f [[buffer(1)]]) {
    float4 wp = f.invViewProj * float4(in.ndc, 1.0, 1.0);
    float3 dir = normalize(wp.xyz / wp.w);
    if (f.dimension.z < 0.5) return float4(f.fogColorStart.rgb, 1.0);
    float3 sun = f.sunDirDaylight.xyz;
    float y = dir.y;

    float3 horizon = f.skyHorizon.rgb;
    float3 zenith = f.skyZenith.rgb;
    float3 col = mix(horizon, zenith, pow(saturate(y), 0.5));
    if (y < 0.0) col = mix(horizon, horizon * 0.55, saturate(-y * 4.0));

    float sd = dot(dir, sun);
    // Sunset glow concentrated around the sun near the horizon
    float glow = f.skyHorizon.w;
    col += float3(1.0, 0.45, 0.18) * pow(saturate(sd * 0.5 + 0.5), 6.0) * glow * (1.0 - saturate(y * 2.0)) * 0.9;
    // Sun disc + halo
    col += float3(1.0, 0.93, 0.78) * smoothstep(0.99925, 0.9996, sd) * 2.2;
    col += float3(1.0, 0.8, 0.55) * (pow(saturate(sd), 900.0) * 0.45 + pow(saturate(sd), 24.0) * 0.12);
    // Moon
    float md = dot(dir, -sun);
    col += float3(0.85, 0.9, 1.0) * smoothstep(0.99955, 0.9997, md) * 1.1;
    col += float3(0.5, 0.6, 0.9) * pow(saturate(md), 400.0) * 0.25;

    // Stars
    float stars = f.skyZenith.w;
    if (stars > 0.01 && y > 0.0) {
        float3 d = dir * 220.0;
        float2 cell = floor(float2(atan2(d.z, d.x) * 90.0, d.y * 1.6));
        float h = hash21(cell);
        float twinkle = 0.6 + 0.4 * sin(f.cameraPosTime.w * (2.0 + h * 3.0) + h * 40.0);
        col += float3(0.9, 0.95, 1.0) * step(0.985, h) * stars * twinkle * saturate(y * 3.0);
    }

    // Clouds on a plane 200 blocks up
    if (f.skyLight.w > 0.5 && abs(y) > 0.015) {
        float camY = f.cameraPosTime.y;
        float dist = (f.dimension.y - camY) / y;
        if (dist > 0.0) {
            float2 p = f.cameraPosTime.xz + dir.xz * dist;
            p = p * 0.0045 + float2(f.cameraPosTime.w * 0.004, f.cameraPosTime.w * 0.0015);
            float n = fbm2(p);
            float coverage = f.fogParams.w;
            float c = smoothstep(1.0 - coverage, 1.0 - coverage + 0.25, n);
            float fade = saturate(1.0 - dist / 3500.0);
            float3 cloudCol = mix(float3(0.95, 0.96, 1.0), horizon, 0.25) * (0.35 + 0.65 * f.sunDirDaylight.w);
            cloudCol += float3(1.0, 0.55, 0.3) * glow * 0.35;
            col = mix(col, cloudCol, c * fade * 0.85);
        }
    }
    return float4(col, 1.0);
}
