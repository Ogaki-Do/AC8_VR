// Rasterize widget-owned policy rectangles, then filter the glow input.
// Region flags come from Lua geometry; this pass does not identify allies by
// screen-pixel color. Sharp blending and glow eligibility remain separate.

#include "hud_route_preview.hlsl"
cbuffer RegionParameters : register(b3) {float4 RegionBounds;float4 RegionFlags;};
float4 MaskPS(Vertex i) : SV_Target {
    float2 edge=min(i.uv-RegionBounds.xy,RegionBounds.zw-i.uv)*float2(2560,1338);
    // One source pixel of antialiasing at most. No brightness threshold.
    return RegionFlags*saturate(min(edge.x,edge.y)+0.5);
}
float4 PrefilterPS(Vertex i) : SV_Target {
    float4 source=Sharp.Sample(BilinearClampSampler,i.uv);
    float4 policy=PolicyMask.Sample(BilinearClampSampler,i.uv);
    // Normal sharp blending and glow eligibility are independent decisions.
    return source*(1-policy.r);
}
