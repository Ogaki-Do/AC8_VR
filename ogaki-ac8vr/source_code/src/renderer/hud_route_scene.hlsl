// Final HUD blend into the current eye image. InverseMap uses current XR layer
// geometry. Full-screen black fade detection and dark-panel coverage are retained;
// there is no broad cyan-pixel recoloring of the flattened scene.

// Same native blending and assets as the proven overlay; real background is
// sampled in destination coordinates. HUD coordinates come from current XR layers.
#include "hud_route_preview.hlsl"
Texture2D<float4> SceneTexture : register(t8);
#include "hud-route-assets/scene_mapping.hlsli"
cbuffer SourceMapping : register(b2) { float4 SourceScaleBias; float4 PanelBounds; };
struct SceneVertex {float4 position:SV_Position;float2 uv:TEXCOORD0;nointerpolation float fade:TEXCOORD1;};
float BlackFadeCoverage(float4 value){
 float peak=max(value.r,max(value.g,value.b));
 return peak<=2.0/255.0 ? saturate(value.a) : 0;
}
SceneVertex SceneVS(uint id:SV_VertexID){
 Vertex base=VS(id);SceneVertex result;result.position=base.position;result.uv=base.uv;
 const float2 points[8]={float2(.03,.03),float2(.97,.03),float2(.03,.97),float2(.97,.97),float2(.16,.15),float2(.84,.15),float2(.16,.85),float2(.84,.85)};
 float coverage=1;
 [unroll]for(int p=0;p<8;++p)coverage=min(coverage,BlackFadeCoverage(Sharp.SampleLevel(BilinearClampSampler,points[p],0)));
 result.fade=coverage;return result;
}
float4 ScenePS(SceneVertex i) : SV_Target {
    float4 scene=SceneTexture.Load(int3(int2(i.position.xy),0));
    float4 map=InverseMap(i.position);
    if(map.z<0.5)return float4(scene.rgb*(1-i.fade),scene.a);
    float2 hudUV=map.xy*SourceScaleBias.xy+SourceScaleBias.zw;
    const float3 luminance=float3(0.298912,0.586611,0.114477);
    float2 uv=hudUV*ViewPortScaler.xy;
    float4 policy=PolicyMask.Sample(BilinearClampSampler,hudUV);
    float4 original=Sharp.Sample(BilinearClampSampler,hudUV);
    float4 combine=lerp(CombineColorTexture.Sample(BilinearClampSampler,uv),original,policy.r);
    // Captured flat-screen rectangles do not follow relocated widgets or pause
    // layouts. Alpha exceeding premultiplied emission identifies dark coverage
    // in the current source itself; pure emissive text keeps the common blend.
    bool emissiveBar=policy.b>0.5 && policy.r>0.5 && original.g>original.r*1.2 && original.g>original.b*1.2;
    bool planeEmission=policy.b>0.5 && policy.r<0.5;
    bool sharpEmission=policy.b>1.5 && policy.b<2.5;
    bool borderEmission=policy.b>2.5 && policy.b<3.5;
    bool inside=HasDarkCoverage(combine)&&!emissiveBar&&!planeEmission&&!sharpEmission;
    bool radio=false;
    bool alphaBlend=SceneBlendPattern>0||inside;
    bool menu=SceneBlendPattern==3,replay=SceneBlendPattern==2;
    float rate=clamp(1-dot(scene.rgb,luminance),0.2,1);
    if(radio)rate=RadioPortraitLuminanceRate;if(alphaBlend)rate=1;
    float4 first=FirstGlowTexture.Sample(BilinearClampSampler,uv)*GlowIntensity*rate*(1-policy.r);
    first.a=saturate(dot(first.rgb,luminance));
    float4 base=float4(combine.rgb+first.rgb,combine.a+first.a*(1-combine.a));
    float4 secondary=SecondaryGlowTexture.Sample(BilinearClampSampler,uv)*SecondaryGlowIntensity*rate*(1-policy.r);
    secondary.a=dot(secondary.rgb,luminance);
    float4 additive=AdditionalGlowTexture.Sample(BilinearClampSampler,uv)*rate*(1-policy.r);
    float3 secondaryRGB=0;
    if(!replay){
        // No extra decorative dots on HUD, tutorials, movies or input prompts.
        secondaryRGB=secondary.rgb;
    }else secondaryRGB=secondary.rgb+additive.rgb;
    float4 empty=EmptyLayerTexture.Sample(BilinearClampSampler,uv);
    float4 core=empty*rate,depth=empty*rate,normal=empty*rate*BlendOpacity;
    float4 color=0;
    if((alphaBlend||radio)&&!menu){
        float4 background=float4(scene.rgb,1);if(!inside)background=ScreenBlend(background,core);
        color=background*(1-base.a)+base;
        color.rgb=color.rgb*(1-saturate(dot(secondaryRGB,luminance)))+secondaryRGB;
    }else{
        float neighborhood=GetIntentsityAdjustedByNeighborhood(CombineColorTexture,BilinearClampSampler,uv,float2(1.0/2560,1.0/1440),luminance);
        color=BlendGlowToScene(SoftLightTexture.Sample(BilinearClampSampler,uv)*(1-policy.r),depth,additive,core,base,float4(scene.rgb,1),neighborhood,menu);
        color=color*(1-normal.a)+normal;color.rgb+=secondaryRGB;
    }
    color.rgb=lerp(color.rgb,scene.rgb+original.rgb,(emissiveBar||sharpEmission)?policy.r:0);
    // Narrow border: one controlled emissive contribution, without the native
    // neighborhood/soft-light amplification. The original picture is separate.
    float3 borderColor=scene.rgb+BorderEmissionRGB(original.rgb*rate,first.rgb+secondaryRGB+additive.rgb);
    color.rgb=lerp(color.rgb,borderColor,borderEmission?saturate(original.a*8):0);
    // Preserve the stored premultiplied sharp copy and coverage; live alpha
    // sufficiency remains a single portrait test, never an opaque PNG inference.
    color.rgb=lerp(color.rgb,original.rgb+scene.rgb*(1-original.a),policy.g);
    return float4(saturate(color.rgb),scene.a);
}
