/// Metal Shading Language source for the wallpaper, compiled at runtime with
/// `MTLDevice.makeLibrary(source:options:)`.
///
/// Runtime compilation means the project builds with the Command Line Tools alone (the
/// offline `metal` compiler ships only with full Xcode). Compilation takes a few
/// milliseconds at launch and `ShaderTests` compiles it in CI so syntax errors surface early.
///
/// Two passes:
/// 1. `field_fragment` renders the gradient at reduced resolution into an rgba16Float
///    texture (linear sRGB). Domain-warped, periodic gradient noise; colours come from two
///    OKLab palette ramps mixed by the transition value.
/// 2. `composite_fragment` upsamples that texture to output resolution with a cubic
///    B-spline (4 bilinear taps), applies brightness/saturation, encodes to sRGB, then adds
///    grain and TPDF dither at output resolution (grain must not be upscaled, and dithering
///    after encoding is what prevents 8-bit banding).
///
/// Periodicity rules (see AnimationClock): every noise lookup must be exactly periodic in
/// the lattice period. Lattice coordinates are masked before hashing, octave frequencies are
/// integer powers of two, and only integer constant offsets are added.
enum WallpaperShaders {
    static var source: String {
        let periodMask = AnimationClock.period - 1
        return """
        #include <metal_stdlib>
        using namespace metal;

        constant int kPeriodMask = \(periodMask);

        struct FieldUniforms {
            float4 offsets[3];
            float2 resolution;
            float  aspect;
            float  complexity;
            float  warp;
            float  transition;
            float  blend;
            float  scale;
        };

        struct CompositeUniforms {
            float2 sourceSize;
            float2 outputSize;
            float  brightness;
            float  saturation;
            float  grain;
            uint   seed;
        };

        struct VSOut { float4 position [[position]]; float2 uv; };

        // Full-screen triangle, no vertex buffer.
        vertex VSOut fullscreen_vertex(uint vid [[vertex_id]]) {
            float2 p = float2((vid << 1) & 2, vid & 2);
            VSOut o;
            o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
            o.uv = float2(p.x, 1.0 - p.y);
            return o;
        }

        // ---------------------------------------------------------------- noise

        static inline uint hashLattice(int2 c) {
            uint2 v = uint2(c & kPeriodMask);          // periodic: wrap BEFORE hashing
            uint h = (v.x * 0x8da6b343u) ^ (v.y * 0xd8163841u);
            h ^= h >> 16; h *= 0x7feb352du;
            h ^= h >> 15; h *= 0x846ca68bu;
            h ^= h >> 16;
            return h;
        }

        // 16 unit gradients at (k + 0.5) × 22.5°: none axis-aligned, which avoids the
        // horizontal/vertical "staircase" bias of 4- or 8-direction gradient noise.
        constant float2 kGradients[16] = {
            float2( 0.98078528,  0.19509032), float2( 0.83146961,  0.55557023),
            float2( 0.55557023,  0.83146961), float2( 0.19509032,  0.98078528),
            float2(-0.19509032,  0.98078528), float2(-0.55557023,  0.83146961),
            float2(-0.83146961,  0.55557023), float2(-0.98078528,  0.19509032),
            float2(-0.98078528, -0.19509032), float2(-0.83146961, -0.55557023),
            float2(-0.55557023, -0.83146961), float2(-0.19509032, -0.98078528),
            float2( 0.19509032, -0.98078528), float2( 0.55557023, -0.83146961),
            float2( 0.83146961, -0.55557023), float2( 0.98078528, -0.19509032)
        };

        // Fixed rotations applied to the *spatial* coordinate only (never to the time
        // offsets), so each layer's lattice is oriented differently and periodicity holds.
        static inline float2 rot(float2 p, float c, float s) { return float2(c * p.x - s * p.y, s * p.x + c * p.y); }

        // 2-D gradient noise, periodic with period kPeriodMask+1. Range about [-0.7, 0.7].
        static inline float gradientNoise(float2 p) {
            float2 i = floor(p);
            float2 f = p - i;
            int2 c = int2(i);
            float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
            float a = dot(kGradients[hashLattice(c)               & 15], f);
            float b = dot(kGradients[hashLattice(c + int2(1, 0)) & 15], f - float2(1, 0));
            float d = dot(kGradients[hashLattice(c + int2(0, 1)) & 15], f - float2(0, 1));
            float e = dot(kGradients[hashLattice(c + int2(1, 1)) & 15], f - float2(1, 1));
            return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
        }

        // Fractional octave count fades the last octave in smoothly.
        static inline float fbm(float2 p, float octaves) {
            float sum = 0.0, norm = 0.0, amp = 0.5, freq = 1.0;
            for (int k = 0; k < 6; k++) {
                float w = clamp(octaves - float(k), 0.0, 1.0);
                if (w <= 0.0) { break; }
                sum  += w * amp * gradientNoise(p * freq + float2(k * 37, k * 91));
                norm += w * amp;
                amp *= 0.5;
                freq *= 2.0;
            }
            return sum / max(norm, 1e-4);
        }

        // ---------------------------------------------------------------- colour

        static inline float3 oklabToLinearSRGB(float3 lab) {
            float l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
            float m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
            float s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
            float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
            return float3( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                          -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                          -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
        }

        static inline float3 linearToSRGB(float3 c) {
            float3 lo = c * 12.92;
            float3 hi = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
            return select(hi, lo, c <= 0.0031308);
        }

        static inline float rampCoordinate(float x) {
            // Sample texel centres of the 256-texel ramp.
            return (saturate(x) * 255.0 + 0.5) / 256.0;
        }

        // ---------------------------------------------------------------- pass 1: field

        fragment float4 field_fragment(VSOut in [[stage_in]],
                                       constant FieldUniforms& u [[buffer(0)]],
                                       texture2d<float> rampFrom [[texture(0)]],
                                       texture2d<float> rampTo   [[texture(1)]],
                                       sampler rampSampler       [[sampler(0)]]) {
            float2 p = float2(in.uv.x * u.aspect, in.uv.y) * u.scale;
            float2 o0 = u.offsets[0].xy, o1 = u.offsets[0].zw;
            float2 o2 = u.offsets[1].xy, o3 = u.offsets[1].zw;
            float2 o4 = u.offsets[2].xy, o5 = u.offsets[2].zw;

            // Two levels of domain warping, each layer drifting independently.
            float2 p0 = rot(p, 0.93233, 0.36162), p1 = rot(p, 0.42666, 0.90441);
            float2 p2 = rot(p, -0.44294, 0.89656), p3 = rot(p, -0.91003, 0.41450);
            float2 p4 = rot(p, 0.68950, 0.72429);
            float2 q = float2(fbm(p0 + o0, 1.5),
                              fbm(p1 + o1 + float2(5, 13), 1.5));
            float2 r = float2(fbm(p2 + u.warp * q + o2 + float2(17, 3), 2.0),
                              fbm(p3 + u.warp * q + o3 + float2(8, 29), 2.0));
            float n = fbm(p4 + u.warp * r + o4, mix(1.5, 3.5, u.complexity));
            // Large, slow layer that shifts which part of the palette dominates where.
            float m = fbm(p1 * 0.5 + o5 + float2(41, 7), 1.5);

            float contrast = mix(1.6, 0.8, u.blend);
            float x = 0.46 + n * contrast + m * 0.6;

            float3 labA = rampFrom.sample(rampSampler, float2(rampCoordinate(x), 0.5)).xyz;
            float3 labB = rampTo.sample(rampSampler, float2(rampCoordinate(x), 0.5)).xyz;
            float3 lab = mix(labA, labB, u.transition);
            // Gentle lightness lift where the warp is strongest: reads as soft light.
            lab.x += (length(r) - 0.25) * 0.05 * (1.0 - 0.5 * u.blend);

            return float4(max(oklabToLinearSRGB(lab), 0.0), 1.0);
        }

        // ---------------------------------------------------------------- pass 2: composite

        static inline float hash01(uint2 p, uint seed) {
            uint h = (p.x * 0x8da6b343u) ^ (p.y * 0xd8163841u) ^ (seed * 0xcb1ab31fu);
            h ^= h >> 16; h *= 0x7feb352du;
            h ^= h >> 15; h *= 0x846ca68bu;
            h ^= h >> 16;
            return float(h) * (1.0 / 4294967296.0);
        }

        // Cubic B-spline filtering from 4 bilinear taps: smooth, no ringing, ideal for
        // upscaling soft gradients.
        static inline float3 sampleBSpline(texture2d<float> t, sampler s, float2 uv, float2 size) {
            float2 pos = uv * size - 0.5;
            float2 i = floor(pos);
            float2 f = pos - i;
            float2 f2 = f * f, f3 = f2 * f;
            float2 w0 = (-f3 + 3.0 * f2 - 3.0 * f + 1.0) / 6.0;
            float2 w1 = (3.0 * f3 - 6.0 * f2 + 4.0) / 6.0;
            float2 w2 = (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0) / 6.0;
            float2 w3 = f3 / 6.0;
            float2 g0 = w0 + w1, g1 = w2 + w3;
            float2 h0 = (i - 1.0 + w1 / g0 + 0.5) / size;
            float2 h1 = (i + 1.0 + w3 / g1 + 0.5) / size;
            float3 a = t.sample(s, float2(h0.x, h0.y)).rgb;
            float3 b = t.sample(s, float2(h1.x, h0.y)).rgb;
            float3 c = t.sample(s, float2(h0.x, h1.y)).rgb;
            float3 d = t.sample(s, float2(h1.x, h1.y)).rgb;
            return g0.y * (g0.x * a + g1.x * b) + g1.y * (g0.x * c + g1.x * d);
        }

        fragment float4 composite_fragment(VSOut in [[stage_in]],
                                           constant CompositeUniforms& u [[buffer(0)]],
                                           texture2d<float> field [[texture(0)]],
                                           sampler fieldSampler   [[sampler(0)]]) {
            float3 c = sampleBSpline(field, fieldSampler, in.uv, u.sourceSize);
            c *= u.brightness;
            float lum = dot(c, float3(0.2126, 0.7152, 0.0722));
            c = max(mix(float3(lum), c, u.saturation), 0.0);

            float3 e = linearToSRGB(saturate(c));
            uint2 px = uint2(in.position.xy);
            // Luminance grain, triangular distribution, changes every frame.
            float g = hash01(px, u.seed) + hash01(px, u.seed + 7919u) - 1.0;
            e += g * u.grain * 0.06;
            // TPDF dither of ±1 LSB, independent of grain, after sRGB encoding.
            float d = hash01(px, 0x9e3779b9u) + hash01(px.yx, 0x85ebca6bu) - 1.0;
            e += d / 255.0;
            return float4(e, 1.0);
        }
        """
    }
}
