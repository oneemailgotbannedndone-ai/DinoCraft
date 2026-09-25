/// GLSL 3.30 ports of DinoCraft's Metal shaders (Resources/Shaders/10_World.metal).
enum Shaders {
    static let chunkVertex = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in float aLayer;
    layout(location = 2) in vec2 aUV;
    layout(location = 3) in float aNormal;
    layout(location = 4) in float aAO;
    layout(location = 5) in float aSky;
    layout(location = 6) in float aLight;
    layout(location = 7) in uint aFlags;

    uniform mat4 uViewProj;
    uniform vec4 uOrigin;
    uniform vec3 uWorldOrigin;
    uniform float uTime;

    out vec2 vUV;
    flat out float vLayer;
    flat out uint vFlags;
    out float vShade;
    out float vSky;
    out float vLight;
    out vec3 vViewPos;
    out float vNormalY;

    const float kFaceShade[7] = float[7](0.66, 0.66, 1.0, 0.52, 0.82, 0.82, 0.88);

    void main() {
        vec3 local = aPos / 16.0;
        vec3 p = local + uOrigin.xyz;
        vec3 wp = local + uWorldOrigin;
        uint flags = aFlags;
        int n = int(aNormal + 0.5);
        if ((flags & 1u) != 0u) {
            float ph = wp.x * 0.7 + wp.z * 0.5 + wp.y * 0.3;
            p.x += sin(uTime * 1.6 + ph) * 0.03;
            p.y += sin(uTime * 1.9 + ph * 1.3) * 0.015;
            p.z += cos(uTime * 1.4 + ph) * 0.03;
        }
        if ((flags & 8u) != 0u) {
            float ph = wp.x * 0.9 + wp.z * 0.7;
            p.x += sin(uTime * 2.1 + ph) * 0.08 + sin(uTime * 0.7 + ph * 0.2) * 0.04;
            p.z += cos(uTime * 1.7 + ph) * 0.06;
        }
        if ((flags & 2u) != 0u && n == 2) {
            p.y += (sin(uTime * 1.3 + wp.x * 0.8) * cos(uTime * 1.1 + wp.z * 0.7)) * 0.03 - 0.03;
        }
        p.y -= (1.0 - uOrigin.w) * 6.0;
        gl_Position = uViewProj * vec4(p, 1.0);

        vec2 uv = aUV / 16.0;
        if ((flags & 4u) == 0u) {
            if (n == 0 || n == 1 || n == 4 || n == 5) uv.y = -uv.y;
            if (n == 0 || n == 5) uv.x = -uv.x;
        }
        if ((flags & 2u) != 0u) uv += vec2(uTime * 0.04, uTime * 0.025);
        vUV = uv;
        vLayer = aLayer;
        vFlags = flags;
        vShade = kFaceShade[min(n, 6)] * mix(0.40, 1.0, aAO / 3.0);
        vSky = aSky;
        vLight = aLight;
        vViewPos = p;
        vNormalY = n == 2 ? 1.0 : (n == 3 ? -1.0 : 0.0);
    }
    """

    /// `pass` is "OPAQUE", "CUTOUT" or "TRANSLUCENT".
    static func chunkFragment(pass: String) -> String {
        """
        #version 330 core
        #define PASS_\(pass)
        in vec2 vUV;
        flat in float vLayer;
        flat in uint vFlags;
        in float vShade;
        in float vSky;
        in float vLight;
        in vec3 vViewPos;
        in float vNormalY;

        uniform sampler2DArray uBlocks;
        uniform vec4 uSunDaylight;
        uniform vec3 uSkyLight;
        uniform vec4 uFogColorStart;
        uniform vec2 uFogParams;
        uniform vec3 uSkyHorizon;
        uniform float uTime;
        uniform float uBrightness;

        out vec4 fragColor;

        float lightCurve(float l) { return pow(0.82, (1.0 - l) * 15.0); }

        vec3 terrainLighting(float sky, float blockLight, float shade, uint flags) {
            if ((flags & 16u) != 0u) return vec3(1.0);
            float s = lightCurve(sky) * uSunDaylight.w;
            float flicker = 0.96 + 0.04 * sin(uTime * 7.3 + blockLight * 13.0);
            float b = lightCurve(blockLight) * flicker;
            vec3 skyC = uSkyLight * s;
            vec3 blockC = vec3(1.0, 0.78, 0.52) * b * 1.05;
            vec3 l = max(skyC, blockC) + skyC * blockC * 0.15;
            float ambient = mix(0.012, 0.07, uBrightness);
            l = l * shade + ambient;
            return pow(l, vec3(mix(1.15, 0.72, uBrightness)));
        }

        vec3 applyFog(vec3 color, vec3 viewPos) {
            float d = length(viewPos);
            if (uFogParams.y > 0.5) {
                float k = 1.0 - exp(-d * 0.06);
                return mix(color, vec3(0.03, 0.14, 0.26) * max(0.25, uSunDaylight.w), k);
            }
            float t = smoothstep(uFogColorStart.w, uFogParams.x, d);
            t = t * t;
            return mix(color, uFogColorStart.rgb, t);
        }

        void main() {
            vec4 c = texture(uBlocks, vec3(vUV, vLayer));
        #if defined(PASS_OPAQUE)
            vec3 lit = c.rgb * terrainLighting(vSky, vLight, vShade, vFlags);
            fragColor = vec4(applyFog(lit, vViewPos), 1.0);
        #elif defined(PASS_CUTOUT)
            if (c.a < 0.5) discard;
            vec3 albedo = c.rgb / max(c.a, 0.001);
            vec3 lit = albedo * terrainLighting(vSky, vLight, vShade, vFlags);
            fragColor = vec4(applyFog(lit, vViewPos), 1.0);
        #else
            float a = c.a;
            if (a < 0.01) discard;
            vec3 albedo = c.rgb / max(a, 0.001);
            vec3 lit = albedo * terrainLighting(vSky, vLight, vShade, vFlags);
            if ((vFlags & 2u) != 0u && vNormalY > 0.5 && (vFlags & 16u) == 0u) {
                vec3 v = normalize(-vViewPos);
                float fres = pow(1.0 - clamp(v.y, 0.0, 1.0), 4.0);
                lit = mix(lit, uSkyHorizon * max(0.2, uSunDaylight.w), fres * 0.55);
                vec3 h = normalize(v + uSunDaylight.xyz);
                float spec = pow(clamp(h.y, 0.0, 1.0), 220.0) * uSunDaylight.w * clamp(vSky * 1.2, 0.0, 1.0);
                lit += vec3(1.0, 0.95, 0.8) * spec * 1.4;
                a = mix(a, 1.0, fres * 0.5);
            }
            fragColor = vec4(applyFog(lit, vViewPos) * a, a);
        #endif
        }
        """
    }

    static let skyVertex = """
    #version 330 core
    out vec2 vNDC;
    void main() {
        vec2 pts[3] = vec2[3](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));
        vNDC = pts[gl_VertexID];
        gl_Position = vec4(vNDC, 0.0, 1.0);
    }
    """

    static let skyFragment = """
    #version 330 core
    in vec2 vNDC;
    uniform vec3 uCamForward;
    uniform vec3 uCamRight;
    uniform vec3 uCamUp;
    uniform vec2 uTanHalfFov;
    uniform vec4 uSunDaylight;
    uniform vec4 uZenithStars;
    uniform vec4 uHorizonGlow;
    uniform vec3 uCamPos;
    uniform float uTime;
    out vec4 fragColor;

    float hash21(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }
    float valueNoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        float a = hash21(i), b = hash21(i + vec2(1.0, 0.0)), c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
        vec2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }
    float fbm2(vec2 p) {
        float s = 0.0, a = 0.5;
        for (int i = 0; i < 5; i++) {
            s += valueNoise(p) * a;
            p = p * 2.03 + vec2(17.1, 9.2);
            a *= 0.5;
        }
        return s;
    }

    void main() {
        vec3 dir = normalize(uCamForward + vNDC.x * uTanHalfFov.x * uCamRight + vNDC.y * uTanHalfFov.y * uCamUp);
        vec3 sun = uSunDaylight.xyz;
        float y = dir.y;
        vec3 horizon = uHorizonGlow.rgb;
        vec3 zenith = uZenithStars.rgb;
        vec3 col = mix(horizon, zenith, pow(clamp(y, 0.0, 1.0), 0.5));
        if (y < 0.0) col = mix(horizon, horizon * 0.55, clamp(-y * 4.0, 0.0, 1.0));

        float sd = dot(dir, sun);
        float glow = uHorizonGlow.w;
        col += vec3(1.0, 0.45, 0.18) * pow(clamp(sd * 0.5 + 0.5, 0.0, 1.0), 6.0) * glow * (1.0 - clamp(y * 2.0, 0.0, 1.0)) * 0.9;
        col += vec3(1.0, 0.93, 0.78) * smoothstep(0.99925, 0.9996, sd) * 2.2;
        col += vec3(1.0, 0.8, 0.55) * (pow(clamp(sd, 0.0, 1.0), 900.0) * 0.45 + pow(clamp(sd, 0.0, 1.0), 24.0) * 0.12);
        float md = dot(dir, -sun);
        col += vec3(0.85, 0.9, 1.0) * smoothstep(0.99955, 0.9997, md) * 1.1;
        col += vec3(0.5, 0.6, 0.9) * pow(clamp(md, 0.0, 1.0), 400.0) * 0.25;

        float stars = uZenithStars.w;
        if (stars > 0.01 && y > 0.0) {
            vec3 d = dir * 220.0;
            vec2 cell = floor(vec2(atan(d.z, d.x) * 90.0, d.y * 1.6));
            float h = hash21(cell);
            float twinkle = 0.6 + 0.4 * sin(uTime * (2.0 + h * 3.0) + h * 40.0);
            col += vec3(0.9, 0.95, 1.0) * step(0.985, h) * stars * twinkle * clamp(y * 3.0, 0.0, 1.0);
        }

        if (abs(y) > 0.015) {
            float dist = (270.0 - uCamPos.y) / y;
            if (dist > 0.0) {
                vec2 p = uCamPos.xz + dir.xz * dist;
                p = p * 0.0045 + vec2(uTime * 0.004, uTime * 0.0015);
                float n = fbm2(p);
                float coverage = 0.42;
                float c = smoothstep(1.0 - coverage, 1.0 - coverage + 0.25, n);
                float fade = clamp(1.0 - dist / 3500.0, 0.0, 1.0);
                vec3 cloudCol = mix(vec3(0.95, 0.96, 1.0), horizon, 0.25) * (0.35 + 0.65 * uSunDaylight.w);
                cloudCol += vec3(1.0, 0.55, 0.3) * glow * 0.35;
                col = mix(col, cloudCol, c * fade * 0.85);
            }
        }
        fragColor = vec4(col, 1.0);
    }
    """

    static let boxVertex = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec3 aColor;
    layout(location = 2) in float aGlow;
    uniform mat4 uViewProj;
    out vec3 vColor;
    out vec3 vViewPos;
    out float vGlow;
    void main() {
        gl_Position = uViewProj * vec4(aPos, 1.0);
        vColor = aColor;
        vViewPos = aPos;
        vGlow = aGlow;
    }
    """

    static let boxFragment = """
    #version 330 core
    in vec3 vColor;
    in vec3 vViewPos;
    in float vGlow;
    uniform vec4 uFogColorStart;
    uniform float uFogEnd;
    uniform float uDaylight;
    out vec4 fragColor;
    void main() {
        vec3 lit = mix(vColor * mix(0.22, 1.0, uDaylight), vColor, vGlow);
        float t = smoothstep(uFogColorStart.w, uFogEnd, length(vViewPos));
        t = t * t;
        fragColor = vec4(mix(lit, uFogColorStart.rgb, t), 1.0);
    }
    """

    /// Textured or plain camera-relative quads: dropped items, the held item, particles, rain and snow.
    /// Layer < 0 is a plain colour, 0… a block texture, 10000… an item texture.
    static let effectVertex = """
    #version 330 core
    layout(location = 0) in vec3 aPos;
    layout(location = 1) in vec2 aUV;
    layout(location = 2) in float aLayer;
    layout(location = 3) in vec4 aColor;
    layout(location = 4) in float aGlow;
    uniform mat4 uViewProj;
    out vec2 vUV;
    out float vLayer;
    out vec4 vColor;
    out float vGlow;
    out vec3 vViewPos;
    void main() {
        gl_Position = uViewProj * vec4(aPos, 1.0);
        vUV = aUV;
        vLayer = aLayer;
        vColor = aColor;
        vGlow = aGlow;
        vViewPos = aPos;
    }
    """

    static let effectFragment = """
    #version 330 core
    in vec2 vUV;
    in float vLayer;
    in vec4 vColor;
    in float vGlow;
    in vec3 vViewPos;
    uniform sampler2DArray uBlocks;
    uniform sampler2DArray uItems;
    uniform vec4 uFogColorStart;
    uniform float uFogEnd;
    uniform float uDaylight;
    out vec4 fragColor;
    void main() {
        vec4 c = vColor;
        if (vLayer >= 9999.5) {
            vec4 t = texture(uItems, vec3(vUV, vLayer - 10000.0));
            if (t.a < 0.3) discard;
            c *= vec4(t.rgb / max(t.a, 0.001), 1.0);
        } else if (vLayer >= -0.5) {
            vec4 t = texture(uBlocks, vec3(vUV, vLayer));
            if (t.a < 0.3) discard;
            c *= vec4(t.rgb / max(t.a, 0.001), 1.0);
        }
        vec3 lit = mix(c.rgb * mix(0.22, 1.0, uDaylight), c.rgb, vGlow);
        float t = smoothstep(uFogColorStart.w, uFogEnd, length(vViewPos));
        t = t * t;
        vec3 rgb = mix(lit, uFogColorStart.rgb, t);
        fragColor = vec4(rgb * c.a, c.a);
    }
    """

    /// Shader packs: a fullscreen pass over the scene (ported from Resources/Shaders/50_Post.metal).
    static let postVertex = """
    #version 330 core
    out vec2 vUV;
    void main() {
        vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
        vUV = p;
    }
    """

    static let postFragment = """
    #version 330 core
    in vec2 vUV;
    uniform sampler2D uScene;
    uniform vec4 uParams;   // x preset (1 vibrant, 2 cinematic, 3 retro, 4 dreamy), y time, zw size in pixels
    uniform float uStrength;
    uniform float uMono;    // 1 = black-and-white (not used by any dimension now)
    out vec4 fragColor;
    float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
    float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
    vec3 toGamma(vec3 c) { return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2)); }
    vec3 blur(vec2 uv, vec2 px, float radius) {
        vec3 acc = texture(uScene, uv).rgb * 0.2;
        for (int i = 0; i < 8; i++) {
            float a = float(i) * 0.785398 + 0.3;
            acc += texture(uScene, uv + vec2(cos(a), sin(a)) * px * radius).rgb * 0.05;
            acc += texture(uScene, uv + vec2(cos(a), sin(a)) * px * radius * 2.2).rgb * 0.05;
        }
        return acc;
    }
    void main() {
        int preset = int(uParams.x + 0.5);
        float time = uParams.y;
        vec2 size = max(uParams.zw, vec2(1.0));
        vec2 uv = vUV;
        vec2 px = 1.0 / size;
        vec3 base = texture(uScene, uv).rgb;
        vec3 g = toGamma(base);
        vec2 q = uv - 0.5;
        float vignette = clamp(1.0 - dot(q, q) * 1.5, 0.0, 1.0);
        if (preset == 1) {
            float l = luma(g);
            g = mix(vec3(l), g, 1.4);
            g = (g - 0.5) * 1.1 + 0.5;
            g *= vec3(1.03, 1.0, 0.97);
            g *= mix(1.0, vignette, 0.45);
        } else if (preset == 2) {
            vec3 glow = toGamma(blur(uv, px, 7.0));
            g += max(glow - 0.62, vec3(0.0)) * 1.6;
            float l = luma(g);
            g += mix(vec3(-0.02, 0.05, 0.09), vec3(0.10, 0.04, -0.05), smoothstep(0.15, 0.85, l)) * 0.7;
            g = smoothstep(vec3(-0.06), vec3(1.06), g);
            g *= mix(1.0, vignette, 0.85);
            g += (hash(floor(uv * size) + fract(time) * 91.0) - 0.5) * 0.04;
            float bar = 0.055;
            if (uv.y < bar || uv.y > 1.0 - bar) g = vec3(0.0);
        } else if (preset == 3) {
            float cell = max(2.0, floor(size.y / 300.0));
            vec2 puv = (floor(uv * size / cell) + 0.5) * cell / size;
            vec3 r = texture(uScene, puv + vec2(px.x * cell * 0.5, 0.0)).rgb;
            vec3 m = texture(uScene, puv).rgb;
            vec3 b = texture(uScene, puv - vec2(px.x * cell * 0.5, 0.0)).rgb;
            g = toGamma(vec3(r.r, m.g, b.b));
            g = floor(g * 5.0 + 0.5) / 5.0;
            float scan = 0.82 + 0.18 * (0.5 + 0.5 * sin(uv.y * size.y / cell * 3.14159));
            g *= scan;
            g *= mix(1.0, vignette, 0.75);
        } else if (preset == 4) {
            vec3 soft = toGamma(blur(uv, px, 5.0));
            g = mix(g, max(g, soft), 0.6);
            float l = luma(g);
            g = mix(vec3(l), g, 0.82);
            g = g * 0.88 + 0.09;
            g *= vec3(1.05, 0.97, 1.07);
            g *= mix(1.0, vignette, 0.35);
        }
        vec3 graded = pow(clamp(g, vec3(0.0), vec3(1.0)), vec3(2.2));
        vec3 outc = preset > 0 ? mix(base, graded, clamp(uStrength, 0.0, 1.0)) : base;
        if (uMono > 0.0) {
            float l = luma(toGamma(outc));
            l = smoothstep(0.03, 0.97, l);
            l += (hash(floor(uv * size / 2.0) + fract(time * 12.0) * 57.0) - 0.5) * 0.05;
            l *= mix(1.0, vignette, 0.55);
            outc = mix(outc, vec3(pow(clamp(l, 0.0, 1.0), 2.2)), clamp(uMono, 0.0, 1.0));
        }
        fragColor = vec4(outc, 1.0);
    }
    """

    static let overlayVertex = """
    #version 330 core
    layout(location = 0) in vec2 aPos;
    layout(location = 1) in vec2 aUV;
    layout(location = 2) in float aLayer;
    layout(location = 3) in vec4 aColor;
    uniform vec2 uScreen;
    out vec2 vUV;
    flat out float vLayer;
    out vec4 vColor;
    void main() {
        gl_Position = vec4(aPos.x / uScreen.x * 2.0 - 1.0, 1.0 - aPos.y / uScreen.y * 2.0, 0.0, 1.0);
        vUV = aUV;
        vLayer = aLayer;
        vColor = aColor;
    }
    """

    static let overlayFragment = """
    #version 330 core
    in vec2 vUV;
    flat in float vLayer;
    in vec4 vColor;
    uniform sampler2DArray uBlocks;
    uniform sampler2DArray uItems;
    out vec4 fragColor;
    void main() {
        if (vLayer < 0.0) {
            fragColor = vec4(vColor.rgb * vColor.a, vColor.a);
        } else if (vLayer >= 9999.5) {
            fragColor = texture(uItems, vec3(vUV, vLayer - 10000.0)) * vColor.a;
        } else {
            fragColor = texture(uBlocks, vec3(vUV, vLayer)) * vColor.a;
        }
    }
    """
}
