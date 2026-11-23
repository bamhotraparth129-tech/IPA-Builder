#include <metal_stdlib>
using namespace metal;
struct VoxelVertexIn { float3 position [[attribute(0)]]; float3 normal [[attribute(1)]]; };
struct VoxelVertexOut { float4 position [[position]]; float3 normal; };
vertex VoxelVertexOut voxel_vertex_main(VoxelVertexIn in [[stage_in]], constant float4x4& mvp [[buffer(1)]) {
    VoxelVertexOut out; out.position = mvp * float4(in.position, 1.0); out.normal = normalize(in.normal); return out;
}
fragment float4 voxel_fragment_main(VoxelVertexOut in [[stage_in]]) {
    float light = 0.35 + 0.65 * max(dot(normalize(in.normal), normalize(float3(0.4, 0.8, 0.3))), 0.0);
    return float4(float3(0.28, 0.68, 0.34) * light, 1.0);
}
