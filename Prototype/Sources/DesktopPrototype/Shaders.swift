/// Metal Shading Language source, compiled at runtime with `makeLibrary(source:options:)`.
///
/// Runtime compilation avoids needing the offline `metal` compiler, which ships with
/// full Xcode but not with the Command Line Tools. The production app (Phase 2) should
/// precompile a .metallib when built with Xcode.
///
/// This is a deliberately simple placeholder look: a slowly domain-warped three-colour
/// gradient with ordered dithering to prevent 8-bit banding. Phase 1 validates desktop
/// integration, not visuals.
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float  time;        // seconds, wrapped on the CPU (see Renderer)
        float2 resolution;  // drawable size in pixels
        float3 colorA;
        float3 colorB;
        float3 colorC;
    };

    struct VSOut { float4 position [[position]]; float2 uv; };

    // Full-screen triangle; no vertex buffer needed.
    vertex VSOut fullscreen_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VSOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    static float hash21(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    static float valueNoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        float a = hash21(i), b = hash21(i + float2(1, 0));
        float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    static float fbm(float2 p) {
        float v = 0.0, amp = 0.5;
        for (int i = 0; i < 4; i++) { v += amp * valueNoise(p); p = p * 2.03 + 17.1; amp *= 0.5; }
        return v;
    }

    // 4x4 Bayer matrix, used to dither before 8-bit quantisation.
    static float bayer4(uint2 p) {
        const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
        return m[(p.y & 3) * 4 + (p.x & 3)] / 16.0 - 0.5;
    }

    fragment float4 gradient_fragment(VSOut in [[stage_in]],
                                      constant Uniforms& u [[buffer(0)]]) {
        float aspect = u.resolution.x / max(u.resolution.y, 1.0);
        float2 p = float2(in.uv.x * aspect, in.uv.y) * 1.6;
        float t = u.time * 0.03;

        // Two levels of domain warping give slow, organic motion.
        float2 q = float2(fbm(p + float2(0.0, t)), fbm(p + float2(5.2, -t * 0.8)));
        float2 r = float2(fbm(p + 3.0 * q + float2(1.7, 9.2) + t * 0.5),
                          fbm(p + 3.0 * q + float2(8.3, 2.8) - t * 0.4));
        float n = fbm(p + 2.5 * r);

        float3 col = mix(u.colorA, u.colorB, smoothstep(0.2, 0.8, n));
        col = mix(col, u.colorC, smoothstep(0.35, 0.95, length(r) * 0.8));

        col += bayer4(uint2(in.position.xy)) / 255.0;
        return float4(col, 1.0);
    }
    """
}
