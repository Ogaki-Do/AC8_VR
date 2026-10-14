// Shared authored HUD blending and policy functions. Native glow and sharp
// layers use separate decisions. Coverage classification below still examines
// alpha/color to distinguish dark panels; do not describe it as threshold-free.

Texture2D<float4> PolicyMask : register(t9);
Texture2D<float4> Sharp : register(t0);
Texture2D<float4> SoftLightTexture : register(t1);
Texture2D<float4> AdditionalGlowTexture : register(t2);
Texture2D<float4> FirstGlowTexture : register(t3);
Texture2D<float4> SecondaryGlowTexture : register(t4);
Texture2D<float4> CombineColorTexture : register(t5);
Texture2D<float4> MenuDecoTexture : register(t6);
Texture2D<float4> EmptyLayerTexture : register(t7);
SamplerState BilinearClampSampler : register(s0);
SamplerState BilinearWrapSampler : register(s1);
cbuffer AuthoredParameters : register(b0) {
    float GlowIntensity : packoffset(c9);
    float SecondaryGlowIntensity : packoffset(c9.y);
    float SecondaryDotIntensity : packoffset(c9.z);
    float RadioPortraitLuminanceRate : packoffset(c9.w);
    float4 BlendMaskRectangle : packoffset(c10);
    float4 BlendMaskRectangleForRadio : packoffset(c11);
    float4 ViewPortScaler : packoffset(c14);
    float4 SoftLightColorScale : packoffset(c15);
    float HUDDistortionScale : packoffset(c16);
    float FirstSoftLightOpacity : packoffset(c16.y);
    float SecondSoftLightOpacity : packoffset(c16.z);
    float BlendOpacity : packoffset(c16.w);
    float HDRUILuminance : packoffset(c17.y);
    uint SceneBlendPattern : packoffset(c17.z);
    uint UseExtraLayer : packoffset(c17.w);
};
#define Texture2DSample(texture,sampler,uv) texture.Sample(sampler,uv)
#include "hud-route-assets/hud_route_authored_helpers.hlsli"
struct Vertex { float4 position : SV_Position; float2 uv : TEXCOORD0; };
float3 BorderEmissionRGB(float3 sharp,float3 glow) {
    // Keep the halo subordinate to the colored stroke. Large captured glow
    // intensity values must not clip the edge into a white/desaturated band.
    float sharpPeak=max(sharp.r,max(sharp.g,sharp.b));
    float glowPeak=max(glow.r,max(glow.g,glow.b));
    glow*=min(1,sharpPeak*0.25/max(glowPeak,0.00001));
    return (sharp+glow)*0.55;
}
bool HasDarkCoverage(float4 source) {
    float peak=max(source.r,max(source.g,source.b));
    bool warningRed=source.r>source.g*3 && source.r>source.b*3;
    float emission=peak;
    float slack=warningRed ? source.a*0.05 : 0;
    // Relax the coverage threshold for mixtures of the actual stored native
    // red/green palettes. Their over-composition adds alpha but splits color
    // across R/G, so max(RGB) alone falsely implies an opaque dark panel.
    // Solve the two palette weights; reject grayscale/other hues using B.
    const float3 red=float3(137.0/140,27.0/140,19.0/140);
    const float3 green=float3(44.0/140,1,35.0/140);
    float redWeight=(source.r-green.r*source.g)/(red.r-green.r*red.g);
    float greenWeight=source.g-red.g*redWeight;
    float predictedBlue=red.b*redWeight+green.b*greenWeight;
    bool paletteMix=redWeight>=0 && greenWeight>=0 &&
        abs(source.b-predictedBlue)<=source.a*0.02+1.0/255.0;
    if(paletteMix){
        emission=max(emission,redWeight+greenWeight);
        slack=source.a*0.05;
    }
    // Tinted radar/menu fills have alpha far above estimated emission and
    // keep the previous panel blend. No intensity or blur-kernel changes.
    return source.a>emission+slack+1.0/255.0;
}
Vertex VS(uint id : SV_VertexID) {
    Vertex o;
    o.uv=float2((id<<1)&2,id&2);
    o.position=float4(o.uv*float2(2,-2)+float2(-1,1),0,1);
    return o;
}
float4 PS(Vertex i) : SV_Target {
    const float3 luminance=float3(0.298912,0.586611,0.114477);
    float2 uv=i.uv*ViewPortScaler.xy;
    float4 policy=PolicyMask.Sample(BilinearClampSampler,i.uv);
    float4 original=Sharp.Sample(BilinearClampSampler,i.uv);
    float4 combine=lerp(CombineColorTexture.Sample(BilinearClampSampler,uv),original,policy.r);
    bool emissiveBar=policy.b>0.5 && policy.r>0.5 && original.g>original.r*1.2 && original.g>original.b*1.2;
    bool planeEmission=policy.b>0.5 && policy.r<0.5;
    bool sharpEmission=policy.b>1.5 && policy.b<2.5;
    bool borderEmission=policy.b>2.5 && policy.b<3.5;
    bool inside=HasDarkCoverage(combine)&&!emissiveBar&&!planeEmission&&!sharpEmission;
    bool radio=false;
    bool alphaBlend=SceneBlendPattern>0||inside;
    bool menu=SceneBlendPattern==3,replay=SceneBlendPattern==2;
    // Black-background emission only. The exact real-scene response is a
    // separate per-eye operation; never bake scenery into this shared HUD.
    float rate=radio?RadioPortraitLuminanceRate:1;if(alphaBlend)rate=1;
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
        float4 background=float4(0,0,0,1);if(!inside)background=ScreenBlend(background,core);
        color=background*(1-base.a)+base;
        color.rgb=color.rgb*(1-saturate(dot(secondaryRGB,luminance)))+secondaryRGB;
    }else{
        float neighborhood=GetIntentsityAdjustedByNeighborhood(CombineColorTexture,BilinearClampSampler,uv,float2(1.0/2560,1.0/1440),luminance);
        color=BlendGlowToScene(SoftLightTexture.Sample(BilinearClampSampler,uv)*(1-policy.r),depth,additive,core,base,float4(0,0,0,1),neighborhood,menu);
        color=color*(1-normal.a)+normal;color.rgb+=secondaryRGB;
    }
    // The game writes an opaque scene. A transparent HUD layer needs a separate
    // transport alpha. Source HUD alpha and authored glow alpha are retained.
    color.rgb=lerp(color.rgb,original.rgb,(emissiveBar||sharpEmission)?policy.r:0);
    color.rgb=lerp(color.rgb,BorderEmissionRGB(original.rgb,first.rgb+secondaryRGB+additive.rgb),borderEmission?saturate(original.a*8):0);
    color=lerp(color,original,policy.g);
    float sharpAlpha=original.a;
    float alpha=saturate(max(sharpAlpha,base.a)+saturate(dot(secondaryRGB,luminance))*(1-max(sharpAlpha,base.a)));
    alpha=max(alpha,saturate(dot(max(0,color.rgb),luminance)));
    return float4(saturate(color.rgb),lerp(alpha,original.a,policy.g));
}
