// Pure geometry for projecting the presentation window into each eye.
// Keep calculations in the declared XR spaces; head pose and authored camera
// pose are different inputs and must not be substituted for one another.

#pragma once
#include <algorithm>
#include <cmath>
#include <array>
#include "../backend/xr_subset.h"
namespace cinema_mask {
struct Aperture {int left,top,right,bottom;};
struct Window {xr_read::Pose pose{};void* space=nullptr;float width=0,height=0;};
struct Clip {float x,y,z,w;};
inline xr_read::Vector3 rotate(xr_read::Quaternion q,xr_read::Vector3 v) {
    const xr_read::Vector3 t{2*(q.y*v.z-q.z*v.y),2*(q.z*v.x-q.x*v.z),2*(q.x*v.y-q.y*v.x)};
    return {v.x+q.w*t.x+q.y*t.z-q.z*t.y,v.y+q.w*t.y+q.z*t.x-q.x*t.z,v.z+q.w*t.z+q.x*t.y-q.y*t.x};
}
inline void resize_window(Window& anchored,const Window& live,float previous_distance,float distance) {
    anchored.width=live.width;anchored.height=live.height;
    const auto shift=rotate(anchored.pose.orientation,{0,0,distance-previous_distance});
    anchored.pose.position.x-=shift.x;anchored.pose.position.y-=shift.y;anchored.pose.position.z-=shift.z;
}
inline bool flat_window(const xr_read::Layer* layer,Window& window) {
    if(!layer||!layer->space)return false;
    if(layer->type==xr_read::cylinder){const auto& c=*reinterpret_cast<const xr_read::Cylinder*>(layer);
        if(!std::isfinite(c.radius+c.centralAngle+c.aspectRatio)||c.radius<=0||c.centralAngle<=0||c.aspectRatio<=0)return false;
        window.pose=c.pose;window.space=c.space;window.width=c.radius*c.centralAngle;window.height=window.width/c.aspectRatio;
        const auto shift=rotate(c.pose.orientation,{0,0,c.radius});window.pose.position.x-=shift.x;window.pose.position.y-=shift.y;window.pose.position.z-=shift.z;
    }else if(layer->type==xr_read::quad){const auto& q=*reinterpret_cast<const xr_read::Quad*>(layer);window={q.pose,q.space,q.width,q.height};}
    else return false;
    return std::isfinite(window.width+window.height)&&window.width>0&&window.height>0;
}
inline std::array<Clip,6> window_vertices(const Window& window,const xr_read::ProjectionView& eye) {
    std::array<Clip,6> result{};const int corners[6][2]={{-1,1},{1,1},{-1,-1},{-1,-1},{1,1},{1,-1}};
    const auto q=eye.pose.orientation;const xr_read::Quaternion inverse{-q.x,-q.y,-q.z,q.w};
    const float l=std::tan(eye.fov.angleLeft),r=std::tan(eye.fov.angleRight),u=std::tan(eye.fov.angleUp),d=std::tan(eye.fov.angleDown);
    for(unsigned i=0;i<6;++i){auto p=rotate(window.pose.orientation,{corners[i][0]*window.width/2,corners[i][1]*window.height/2,0});
        p.x+=window.pose.position.x-eye.pose.position.x;p.y+=window.pose.position.y-eye.pose.position.y;p.z+=window.pose.position.z-eye.pose.position.z;p=rotate(inverse,p);
        result[i]={(2*p.x+(r+l)*p.z)/(r-l),(2*p.y+(u+d)*p.z)/(u-d),-.5f*p.z,-p.z};}
    return result;
}
inline std::array<Clip,6> window_parameters(const Window& window,const xr_read::ProjectionView& eye,int pixels) {
    const auto q=window.pose.orientation;const xr_read::Quaternion inv{-q.x,-q.y,-q.z,q.w};
    auto origin=eye.pose.position;origin.x-=window.pose.position.x;origin.y-=window.pose.position.y;origin.z-=window.pose.position.z;origin=rotate(inv,origin);
    const float l=std::tan(eye.fov.angleLeft),r=std::tan(eye.fov.angleRight),u=std::tan(eye.fov.angleUp),d=std::tan(eye.fov.angleDown);
    const auto dx=rotate(inv,rotate(eye.pose.orientation,{r-l,0,0})),dy=rotate(inv,rotate(eye.pose.orientation,{0,d-u,0})),ray=rotate(inv,rotate(eye.pose.orientation,{l,u,-1}));
    return {{{origin.x,origin.y,origin.z,window.width/2},{dx.x,dx.y,dx.z,window.height/2},{dy.x,dy.y,dy.z,float(pixels)},{ray.x,ray.y,ray.z,0},{},{}}};
}
// Fixed 60-degree horizontal opening, 16:9 in tangent space. Authored lens later.
inline bool aperture(const xr_read::Fov& f,int pixels,Aperture& r) {
    const float l=std::tan(f.angleLeft),rr=std::tan(f.angleRight);
    const float u=std::tan(f.angleUp),d=std::tan(f.angleDown);
    if(pixels<=0 || !std::isfinite(l+rr+u+d) || l>=0 || rr<=0 || u<=0 || d>=0) return false;
    constexpr float x=0.57735026919f,y=x*9.0f/16.0f;
    auto bound=[pixels](float v){return std::clamp(static_cast<int>(std::lround(v*pixels)),0,pixels);};
    r={bound((-x-l)/(rr-l)),bound((u-y)/(u-d)),bound((x-l)/(rr-l)),bound((u+y)/(u-d))};
    return r.left<r.right && r.top<r.bottom;
}
// Copy view pose/FOV exactly; never inherit an engine depth extension for a border.
inline xr_read::ProjectionView mask_view(const xr_read::ProjectionView& source,void* chain,unsigned eye,int pixels) {
    auto v=source;v.type=48;v.next=nullptr;v.subImage={chain,{{0,0},{pixels,pixels}},eye};return v;
}
}
