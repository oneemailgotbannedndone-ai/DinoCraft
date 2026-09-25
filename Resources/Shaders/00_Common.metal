#include <metal_stdlib>
using namespace metal;

// Shared between Swift (`FrameUniforms` in Renderer.swift) and all shaders.
// Only float4x4 / float4 members so the layout is identical on both sides.
struct FrameUniforms {
    float4x4 viewProj;        // camera-relative (no translation)
    float4x4 invViewProj;
    float4 cameraPosTime;     // xyz camera world position, w time (s)
    float4 sunDirDaylight;    // xyz sun direction, w daylight 0..1
    float4 fogColorStart;     // rgb fog colour, w fog start (blocks)
    float4 fogParams;         // x fog end, y underwater, z brightness 0..1, w cloud coverage
    float4 skyZenith;         // rgb zenith, w star visibility
    float4 skyHorizon;        // rgb horizon, w sunset glow
    float4 skyLight;          // rgb sky light tint, w cloud toggle
    float4 viewport;          // xy size (px), zw 1/size
    float4 dimension;         // x ambient light, y cloud height, z sky visible, w winter snow on leaves and grass
    float4 season;            // rgb leaf/grass colour (times brightness), w how far to blend toward it
};

struct ChunkUniforms {
    float4 origin;            // xyz chunk origin relative to camera, w fade-in 0..1
    float4 worldOrigin;       // xyz wrapped world origin (for animation phase)
};

// Hash / noise helpers (procedural sky, clouds, sparkles)
static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0)), c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm2(float2 p) {
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        s += valueNoise(p) * a;
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return s;
}

static inline float lightCurve(float l) {
    return pow(0.82, (1.0 - l) * 15.0);
}
