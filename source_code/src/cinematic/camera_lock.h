// Pair early/post stereo callbacks so authored cinematic camera motion remains
// stable while retaining the eye separation supplied by UEVR. Pending data is
// thread-local and matched to the callback arguments before reuse.

#pragma once
#include <cmath>
#include <cstdlib>
#include <atomic>
#include <cstring>
#include <cstdio>
namespace cinematic_camera {
inline const UEVR_PluginInitializeParam* host=nullptr;
inline std::atomic<bool> enabled{false};
inline std::atomic<unsigned long long> writes{0};
struct Pose {double x,y,z,pitch,yaw,roll;};
struct Pending {void* device;void* position;void* rotation;int index;bool precision,valid;Pose pose;};
inline thread_local Pending pending{};
inline thread_local Pose component_pose{};
inline thread_local bool component_valid=false;
inline std::atomic<unsigned long long> component_writes{0},component_rejected{0};
inline thread_local bool zero_based=false;
inline Pose read(UEVR_Vector3f* p,UEVR_Rotatorf* r,bool precision){
    if(precision){const auto* pd=reinterpret_cast<UEVR_Vector3d*>(p);const auto* rd=reinterpret_cast<UEVR_Rotatord*>(r);return {pd->x,pd->y,pd->z,rd->pitch,rd->yaw,rd->roll};}
    return {p->x,p->y,p->z,r->pitch,r->yaw,r->roll};
}
inline void early(UEVR_StereoRenderingDeviceHandle device,int index,float,UEVR_Vector3f* p,UEVR_Rotatorf* r,bool precision){
    pending.valid=false;component_valid=false;
    if(!enabled||!p||!r||index<0||index>2)return;
    if(index==0)zero_based=true;else if(index==2)zero_based=false;
    pending={device,p,r,index,precision,true,read(p,r,precision)};
}
// OpenXR eye offset -> UE local axes, then authored camera orientation.
// Runtime supplies both eye offsets; no IPD constant or strength multiplier.
inline Pose target(Pose p,UEVR_Vector3f eye,double units){
    constexpr double radians=3.14159265358979323846/180;
    const double sp=std::sin(p.pitch*radians),cp=std::cos(p.pitch*radians),sy=std::sin(p.yaw*radians),cy=std::cos(p.yaw*radians),sr=std::sin(p.roll*radians),cr=std::cos(p.roll*radians);
    const double x=-eye.z*units,y=eye.x*units,z=eye.y*units;
    p.x+=x*cp*cy+y*(sr*sp*cy-cr*sy)+z*(-cr*sp*cy-sr*sy);
    p.y+=x*cp*sy+y*(sr*sp*sy+cr*cy)+z*(cy*sr-cr*sp*sy);
    p.z+=x*sp-y*sr*cp+z*cr*cp;
    return p;
}
inline void post(UEVR_StereoRenderingDeviceHandle device,int index,float meters,UEVR_Vector3f* p,UEVR_Rotatorf* r,bool precision){
    const auto saved=pending;pending.valid=false;
    if(!enabled||!saved.valid||device!=saved.device||index!=saved.index||p!=saved.position||r!=saved.rotation||precision!=saved.precision||!host||!host->vr||!host->vr->get_eye_offset||!host->vr->get_mod_value)return;
    char method[32]{},scale[32]{};host->vr->get_mod_value("VR_RenderingMethod",method,32);
    if(std::strcmp(method,"0")!=0)return; // Bounded first test: native stereo only; no AFR eye guessing.
    host->vr->get_mod_value("VR_WorldScale",scale,32);const double units=meters*std::atof(scale);
    const int eye_index=zero_based?index:index-1;if(eye_index<0||eye_index>1||!std::isfinite(units)||units<=0)return;
    UEVR_Vector3f eye{};host->vr->get_eye_offset(static_cast<UEVR_Eye>(eye_index),&eye);
    const auto t=target(component_valid?component_pose:saved.pose,eye,units);
    if(component_valid)++component_writes;component_valid=false;
    if(!std::isfinite(t.x+t.y+t.z+t.pitch+t.yaw+t.roll))return;
    if(precision){auto* pd=reinterpret_cast<UEVR_Vector3d*>(p);auto* rd=reinterpret_cast<UEVR_Rotatord*>(r);*pd={t.x,t.y,t.z};*rd={t.pitch,t.yaw,t.roll};}
    else {*p={static_cast<float>(t.x),static_cast<float>(t.y),static_cast<float>(t.z)};*r={static_cast<float>(t.pitch),static_cast<float>(t.yaw),static_cast<float>(t.roll)};}
    ++writes;
}
inline void control(const char* name,const char* data){
    if(name&&std::strcmp(name,"AC8_AuthoredCameraPose")==0){
        component_valid=false;Pose p{};char trailing=0;
        if(enabled&&pending.valid&&data&&sscanf_s(data,"%lf|%lf|%lf|%lf|%lf|%lf%c",&p.x,&p.y,&p.z,&p.pitch,&p.yaw,&p.roll,&trailing,1u)==6&&
            std::isfinite(p.x+p.y+p.z+p.pitch+p.yaw+p.roll)&&
            std::abs(p.x)<1.e12&&std::abs(p.y)<1.e12&&std::abs(p.z)<1.e12&&
            std::abs(p.pitch)<=36000&&std::abs(p.yaw)<=36000&&std::abs(p.roll)<=36000){component_pose=p;component_valid=true;}
        else ++component_rejected;
        return;
    }
    if(name&&std::strcmp(name,"AC8_CinematicCamera")==0)enabled=data&&std::strcmp(data,"on")==0;
}
}
