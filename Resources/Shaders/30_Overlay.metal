// ---------------------------------------------------------------------------
// World-space overlays: block selection outline and break cracks
// ---------------------------------------------------------------------------

struct OverlayVertexIn {
    float3 pos    [[attribute(0)]];
    float2 uv     [[attribute(1)]];
    float4 color  [[attribute(2)]];
    float2 params [[attribute(3)]];   // x mode (0 solid, 1 crack texture), y layer
};

struct OverlayVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float mode [[flat]];
    float layer [[flat]];
};

vertex OverlayVertexOut overlay_vertex(OverlayVertexIn in [[stage_in]], constant FrameUniforms &f [[buffer(1)]]) {
    OverlayVertexOut o;
    o.position = f.viewProj * float4(in.pos, 1.0);
    o.uv = in.uv;
    o.color = in.color;
    o.mode = in.params.x;
    o.layer = in.params.y;
    return o;
}

fragment float4 overlay_fragment(OverlayVertexOut in [[stage_in]],
                                 texture2d_array<float> cracks [[texture(0)]],
                                 sampler s [[sampler(0)]]) {
    if (in.mode < 0.5) {
        return float4(in.color.rgb * in.color.a, in.color.a);
    }
    float4 t = cracks.sample(s, in.uv, uint(in.layer));
    return t * in.color.a;
}
