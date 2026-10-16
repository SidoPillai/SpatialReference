//
//  SplatShaders.metal
//  SpatialReference
//
//  A 3D Gaussian splat renderer for CompositorServices: splats are depth
//  sorted on the GPU every frame with a 16-bit counting sort, then drawn back
//  to front as screen-space ellipses into both eyes in one amplified pass.
//

#include <metal_stdlib>
using namespace metal;

/// One splat, ready to draw. 40 bytes.
struct Splat {
    packed_float3 position;
    /// sRGB r g b and linear opacity, 8 bits each.
    uint color;
    /// The 3D covariance's upper triangle: xx xy xz, then yy yz zz.
    packed_float3 covA;
    packed_float3 covB;
};

/// Mirrors `SplatRenderer.EyeUniforms`.
struct EyeUniforms {
    float4x4 viewProjection;
    float4x4 modelView;
    /// Focal lengths in pixels.
    float2 focal;
    /// The eye's size in (unfoveated) pixels.
    float2 screenSize;
    /// How far off axis a splat center may sit before its footprint is
    /// clamped, as tangents.
    float2 tanLimit;
    float2 padding;
};

/// Mirrors `SplatRenderer.FrameUniforms`.
struct FrameUniforms {
    EyeUniforms eyes[2];
    /// Scene to centre-eye view, for sorting and culling.
    float4x4 sortModelView;
    float gain;
    uint splatCount;
    float logNear;
    float inverseLogRange;
    /// A splat whose center is farther off axis than this, as a tangent, is
    /// outside both eyes.
    float cullTangent;
    float3 padding;
};

constant uint binCount = 65536;
constant uint culled = 0xFFFFFFFF;
constant float shC0 = 0.28209479177387814;

// MARK: - Loading

/// Turns a capture's raw attributes into drawable splats.
kernel void prepareSplats(device const float *positions [[buffer(0)]],
                          device const float *scales [[buffer(1)]],
                          device const float *rotations [[buffer(2)]],
                          device const float *opacities [[buffer(3)]],
                          device const float *colors [[buffer(4)]],
                          device Splat *splats [[buffer(5)]],
                          constant uint &count [[buffer(6)]],
                          uint id [[thread_position_in_grid]]) {
    if (id >= count) return;
    float3 p = float3(positions[id * 3], positions[id * 3 + 1], positions[id * 3 + 2]);
    float3 s = exp(float3(scales[id * 3], scales[id * 3 + 1], scales[id * 3 + 2]));
    float4 q = float4(rotations[id * 4], rotations[id * 4 + 1], rotations[id * 4 + 2], rotations[id * 4 + 3]);
    float x = q.x, y = q.y, z = q.z, w = q.w;

    float3x3 r = float3x3(float3(1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y)),
                          float3(2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x)),
                          float3(2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)));
    float3x3 m = float3x3(r[0] * s.x, r[1] * s.y, r[2] * s.z);
    float3x3 sigma = m * transpose(m);

    float3 dc = float3(colors[id * 3], colors[id * 3 + 1], colors[id * 3 + 2]);
    float3 rgb = saturate(0.5 + shC0 * dc);
    float alpha = 1 / (1 + exp(-opacities[id]));

    Splat out;
    out.position = packed_float3(p);
    out.color = pack_float_to_unorm4x8(float4(rgb, alpha));
    out.covA = packed_float3(sigma[0][0], sigma[0][1], sigma[0][2]);
    out.covB = packed_float3(sigma[1][1], sigma[1][2], sigma[2][2]);
    splats[id] = out;
}

// MARK: - Sorting

/// Gives each splat in view a depth key, far first, and counts each key.
kernel void splatKeys(device const Splat *splats [[buffer(0)]],
                      constant FrameUniforms &u [[buffer(1)]],
                      device uint *keys [[buffer(2)]],
                      device atomic_uint *histogram [[buffer(3)]],
                      uint id [[thread_position_in_grid]]) {
    if (id >= u.splatCount) return;
    Splat s = splats[id];
    float3 v = (u.sortModelView * float4(float3(s.position), 1)).xyz;
    float depth = -v.z;
    float alpha = unpack_unorm4x8_to_float(s.color).a;
    // Splats are a few σ wide, so let centers just outside the view through.
    float slack = depth * u.cullTangent + 0.05;
    if (depth < 0.02 || abs(v.x) > slack || abs(v.y) > slack || alpha < 1.0 / 255.0) {
        keys[id] = culled;
        return;
    }
    // Distance rather than depth, so the order doesn't shift as the head turns.
    float t = saturate((log(length(v)) - u.logNear) * u.inverseLogRange);
    uint key = uint((1 - t) * float(binCount - 1));
    keys[id] = key;
    atomic_fetch_add_explicit(&histogram[key], 1, memory_order_relaxed);
}

/// Turns the key counts into where each key's splats start. One threadgroup
/// of 1024 threads, 64 bins each; also writes the draw's instance count.
kernel void splatScan(device uint *histogram [[buffer(0)]],
                      device MTLDrawPrimitivesIndirectArguments *drawArgs [[buffer(1)]],
                      uint tid [[thread_index_in_threadgroup]],
                      uint lane [[thread_index_in_simdgroup]],
                      uint simd [[simdgroup_index_in_threadgroup]]) {
    constexpr uint perThread = binCount / 1024;
    threadgroup uint simdTotals[32];

    uint base = tid * perThread;
    uint sum = 0;
    for (uint i = 0; i < perThread; i++) sum += histogram[base + i];

    uint before = simd_prefix_exclusive_sum(sum);
    if (lane == 31) simdTotals[simd] = before + sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (simd == 0) {
        uint total = simdTotals[lane];
        simdTotals[lane] = simd_prefix_exclusive_sum(total);
        if (lane == 31) {
            drawArgs->vertexCount = 4;
            drawArgs->instanceCount = simdTotals[lane] + total;
            drawArgs->vertexStart = 0;
            drawArgs->baseInstance = 0;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    uint offset = simdTotals[simd] + before;
    for (uint i = 0; i < perThread; i++) {
        uint n = histogram[base + i];
        histogram[base + i] = offset;
        offset += n;
    }
}

/// Puts each splat in view at its place in draw order.
kernel void splatScatter(device const uint *keys [[buffer(0)]],
                         device atomic_uint *offsets [[buffer(1)]],
                         device uint *order [[buffer(2)]],
                         constant FrameUniforms &u [[buffer(3)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= u.splatCount) return;
    uint key = keys[id];
    if (key == culled) return;
    uint slot = atomic_fetch_add_explicit(&offsets[key], 1, memory_order_relaxed);
    order[slot] = id;
}

// MARK: - Drawing

struct SplatVertex {
    float4 position [[position]];
    /// Full precision on purpose: on Vision Pro, a `half4` here makes the
    /// draw silently produce nothing (no color, no depth) as soon as the
    /// fragment shader reads it, though it works in the simulator.
    float4 color;
    /// Where in the ellipse this corner is, ±2 along each axis.
    float2 offset;
};

static inline float3 linearFromSRGB(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

vertex SplatVertex splatVertex(uint vertexID [[vertex_id]],
                               uint instanceID [[instance_id]],
                               ushort eye [[amplification_id]],
                               device const Splat *splats [[buffer(0)]],
                               device const uint *order [[buffer(1)]],
                               constant FrameUniforms &u [[buffer(2)]]) {
    SplatVertex out;
    Splat s = splats[order[instanceID]];
    constant EyeUniforms &e = u.eyes[eye];

    float4 world = float4(float3(s.position), 1);
    float3 t = (e.modelView * world).xyz;
    float depth = -t.z;
    float4 clip = e.viewProjection * world;
    if (depth < 0.02) {
        out.position = float4(0, 0, 2, 1);  // outside the clip volume
        out.color = 0;
        out.offset = 0;
        return out;
    }

    // Project the 3D covariance to the screen: Σ' = J W Σ Wᵀ Jᵀ.
    float2 limit = 1.3 * e.tanLimit;
    float tx = clamp(t.x / depth, -limit.x, limit.x) * depth;
    float ty = clamp(t.y / depth, -limit.y, limit.y) * depth;
    float2 f = e.focal;
    // Camera looks down -z, so d(fx·x/depth)/dz = fx·x/depth².
    float3x3 j = float3x3(float3(f.x / depth, 0, 0),
                          float3(0, f.y / depth, 0),
                          float3(f.x * tx / (depth * depth), f.y * ty / (depth * depth), 0));
    float3x3 w = float3x3(e.modelView[0].xyz, e.modelView[1].xyz, e.modelView[2].xyz);
    float3x3 sigma = float3x3(float3(s.covA.x, s.covA.y, s.covA.z),
                              float3(s.covA.y, s.covB.x, s.covB.y),
                              float3(s.covA.z, s.covB.y, s.covB.z));
    float3x3 m = j * w;
    float3x3 cov = m * sigma * transpose(m);
    // A low-pass filter so no splat is smaller than about a pixel.
    float a = cov[0][0] + 0.3, b = cov[0][1], c = cov[1][1] + 0.3;

    float mid = 0.5 * (a + c);
    float radius = length(float2(0.5 * (a - c), b));
    float major = mid + radius, minor = max(mid - radius, 0.1);
    float2 axis = abs(b) < 1e-7 ? (a >= c ? float2(1, 0) : float2(0, 1)) : normalize(float2(b, major - a));
    float2 majorAxis = min(sqrt(2 * major), 2048.0) * axis;
    float2 minorAxis = min(sqrt(2 * minor), 2048.0) * float2(-axis.y, axis.x);

    float2 corner = float2(float(vertexID & 1), float(vertexID >> 1)) * 4 - 2;
    float2 pixels = corner.x * majorAxis + corner.y * minorAxis;
    clip.xy += pixels * 2 / e.screenSize * clip.w;

    float4 color = unpack_unorm4x8_to_float(s.color);
    out.position = clip;
    out.color = float4(linearFromSRGB(saturate(color.rgb * u.gain)), color.a);
    out.offset = corner;
    return out;
}

fragment half4 splatFragment(SplatVertex in [[stage_in]]) {
    float power = -dot(in.offset, in.offset);
    half alpha = half(exp(power) * in.color.a);
    if (power < -4 || alpha < half(1.0 / 255.0)) discard_fragment();
    // Premultiplied, blended back to front.
    return half4(half3(in.color.rgb) * alpha, alpha);
}
