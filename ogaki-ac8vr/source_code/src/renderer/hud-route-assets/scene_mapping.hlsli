// Invert the current eye/cylinder projection to find HUD texture coordinates.
// Coordinates outside the valid curved panel return an invalid mapping so the
// caller can preserve the scene. Constants must match current_geometry.h.

// Geometry adapter only. Does not replace or implement any game glow shader.
// OpenXR right-handed coordinates: +Y up, view forward -Z, UV origin top left.
// Caller must resolve both poses into the same space and normalize quaternions.
cbuffer Mapping : register(b1) {
    float4 CylinderQuaternion;
    float4 CylinderPositionRadius;
    float4 EyeQuaternion;
    float4 EyePositionAngle;
    float4 FovTangentsLRUD;
    float4 EyeRectangle;
    float4 SceneSizeAspect; // xy=texture size, z=cylinder aspect ratio
};
float3 Rotate(float4 q, float3 p) {
    float3 t = 2 * cross(q.xyz, p);
    return p + q.w*t + cross(q.xyz,t);
}
float3 CylinderPoint(float2 uv) {
    float radius=CylinderPositionRadius.w;
    float angle=EyePositionAngle.w;
    float theta=(uv.x-0.5)*angle;
    float height=radius*angle/SceneSizeAspect.z;
    float3 p=float3(radius*sin(theta),(0.5-uv.y)*height,-radius*cos(theta));
    return Rotate(CylinderQuaternion,p)+CylinderPositionRadius.xyz;
}
float4 ForwardMap(float4 position:SV_Position,float2 hudUV:TEXCOORD0):SV_Target {
    float4 qi=float4(-EyeQuaternion.xyz,EyeQuaternion.w);
    float3 p=Rotate(qi,CylinderPoint(hudUV)-EyePositionAngle.xyz);
    if(p.z>=-1e-8) return float4(0,0,0,0);
    float2 slope=p.xy/-p.z;
    float2 eyeUV=float2((slope.x-FovTangentsLRUD.x)/(FovTangentsLRUD.y-FovTangentsLRUD.x),
                       (FovTangentsLRUD.z-slope.y)/(FovTangentsLRUD.z-FovTangentsLRUD.w));
    float2 sceneUV=(EyeRectangle.xy+eyeUV*EyeRectangle.zw)/SceneSizeAspect.xy;
    bool visible=all(eyeUV>=0)&&all(eyeUV<=1);
    return float4(sceneUV,visible?1:0,1);
}
float4 InverseMap(float4 position:SV_Position):SV_Target {
    float2 eyeUV=(position.xy-EyeRectangle.xy)/EyeRectangle.zw;
    if(any(eyeUV<0)||any(eyeUV>1)) return 0;
    float3 eyeRay=float3(lerp(FovTangentsLRUD.x,FovTangentsLRUD.y,eyeUV.x),
                         lerp(FovTangentsLRUD.z,FovTangentsLRUD.w,eyeUV.y),-1);
    float4 qi=float4(-CylinderQuaternion.xyz,CylinderQuaternion.w);
    float3 origin=Rotate(qi,EyePositionAngle.xyz-CylinderPositionRadius.xyz);
    float3 direction=Rotate(qi,Rotate(EyeQuaternion,eyeRay));
    float radius=CylinderPositionRadius.w;
    float a=dot(direction.xz,direction.xz);
    float b=2*dot(origin.xz,direction.xz);
    float c=dot(origin.xz,origin.xz)-radius*radius;
    float disc=b*b-4*a*c;
    if(a<1e-12||disc<0) return 0;
    float2 roots=float2(-b-sqrt(disc),-b+sqrt(disc))/(2*a);
    [loop] for(int i=0;i<2;i++) {
        float t=roots[i];
        if(t<=0) continue;
        float3 p=origin+t*direction;
        float angle=EyePositionAngle.w;
        float2 uv=float2(0.5+atan2(p.x,-p.z)/angle,
                        0.5-p.y/(radius*angle/SceneSizeAspect.z));
        if(all(uv>=0)&&all(uv<=1)) return float4(uv,1,1);
    }
    return 0;
}
struct VertexOutput {float4 position:SV_Position;float2 uv:TEXCOORD0;};
VertexOutput MappingVS(uint id:SV_VertexID) {
    VertexOutput o;
    o.uv=float2((id<<1)&2,id&2);
    o.position=float4(o.uv*float2(2,-2)+float2(-1,1),0,1);
    return o;
}
// Offline GPU fixture maps its tiny output grid across the actual submitted eye rectangle.
float4 TestInverse(float4 position:SV_Position,float2 uv:TEXCOORD0):SV_Target {
    return InverseMap(float4(EyeRectangle.xy+uv*EyeRectangle.zw,0,1));
}

