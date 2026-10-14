// Validate geometry from the current xrEndFrame submission and produce shader
// mapping constants. Previous-frame eye/cylinder geometry is never a substitute.
// Geometry validity and swapchain write ownership are independent requirements.

#pragma once
#include "../backend/xr_subset.h"
#include <cmath>
#include <cstring>
// Read the current call's layers at xrEndFrame ENTRY. A previous successful
// submission is never a geometry source. This grants no image-write permission.
namespace current_geometry {
struct Selection {
    bool valid=false;
    uint64_t session=0,space=0;
    uint32_t frame=0;
    xr_read::Pose poses[2]{};
    xr_read::Fov fovs[2]{};
};
struct Request {
    uint64_t frame=0,layout=0,scene_chain=0,hud_chain=0;
    uint32_t scene_width=0,scene_height=0,hud_width=0,hud_height=0;
    Selection selected;
};
struct Snapshot {
    uint64_t frame=0,layout=0,session=0,space=0;
    uint32_t selected_frame=0;
    int64_t display_time=0;
    xr_read::Cylinder cylinder{};
    xr_read::ProjectionView eyes[2]{};
    uint32_t hud_width=0,hud_height=0;
};
struct Constants {
    float cylinder_quaternion[4]{},cylinder_position_radius[4]{};
    float eye_quaternion[4]{},eye_position_angle[4]{},fov_tangents[4]{};
    float eye_rectangle[4]{},scene_size_aspect[4]{};
    // Original mapping's 112 bytes above; b1 below supplies actual source UI
    // subimage correspondence and the explicitly supplied current panel region.
    float source_scale_bias[4]{},panel_bounds[4]{};
};
static_assert(sizeof(Constants)==144);
inline bool pose(const xr_read::Pose& p){
    const auto& q=p.orientation;const double length=double(q.x)*q.x+double(q.y)*q.y+double(q.z)*q.z+double(q.w)*q.w;
    return std::isfinite(length)&&length>.99&&length<1.01&&std::isfinite(p.position.x)&&std::isfinite(p.position.y)&&std::isfinite(p.position.z);
}
inline bool fov(const xr_read::Fov& f){
    constexpr float limit=1.5707f;
    return std::isfinite(f.angleLeft)&&std::isfinite(f.angleRight)&&std::isfinite(f.angleUp)&&std::isfinite(f.angleDown)&&
        f.angleLeft<f.angleRight&&f.angleDown<f.angleUp&&f.angleLeft>-limit&&f.angleRight<limit&&f.angleDown>-limit&&f.angleUp<limit;
}
inline bool rect(const xr_read::Rect& r,uint32_t width,uint32_t height){
    return r.offset.x>=0&&r.offset.y>=0&&r.extent.width>0&&r.extent.height>0&&
        uint64_t(r.offset.x)+uint32_t(r.extent.width)<=width&&uint64_t(r.offset.y)+uint32_t(r.extent.height)<=height;
}
inline bool overlap(const xr_read::Rect& a,const xr_read::Rect& b){
    return int64_t(a.offset.x)<int64_t(b.offset.x)+b.extent.width&&int64_t(b.offset.x)<int64_t(a.offset.x)+a.extent.width&&
        int64_t(a.offset.y)<int64_t(b.offset.y)+b.extent.height&&int64_t(b.offset.y)<int64_t(a.offset.y)+a.extent.height;
}
// Separate plain-data guarded read avoids C++ unwinding inside SEH.
inline bool read_layers(const xr_read::EndInfo* info,uint64_t scene,uint64_t hud,Snapshot* out){
    __try {
        if(!info||info->type!=xr_read::frame_end_info||info->next||!info->layerCount||info->layerCount>16||!info->layers)return false;
        bool found_scene=false,found_hud=false;out->display_time=info->displayTime;
        for(uint32_t i=0;i<info->layerCount;i++){
            const auto* layer=info->layers[i];if(!layer)return false;
            if(layer->type==xr_read::projection){
                const auto* p=reinterpret_cast<const xr_read::Projection*>(layer);
                if(p->viewCount!=2||!p->views)return false;
                if(reinterpret_cast<uint64_t>(p->views[0].subImage.swapchain)!=scene&&reinterpret_cast<uint64_t>(p->views[1].subImage.swapchain)!=scene)continue;
                if(found_scene||p->next||p->views[0].type!=48||p->views[1].type!=48||p->views[0].next||p->views[1].next||
                    reinterpret_cast<uint64_t>(p->views[0].subImage.swapchain)!=scene||reinterpret_cast<uint64_t>(p->views[1].subImage.swapchain)!=scene)return false;
                out->eyes[0]=p->views[0];out->eyes[1]=p->views[1];out->space=reinterpret_cast<uint64_t>(p->space);found_scene=true;
            }else if(layer->type==xr_read::cylinder){
                const auto* c=reinterpret_cast<const xr_read::Cylinder*>(layer);
                if(reinterpret_cast<uint64_t>(c->subImage.swapchain)!=hud)continue;
                if(found_hud||c->next||c->eyeVisibility!=0)return false;
                out->cylinder=*c;found_hud=true;
            }
        }
        return found_scene&&found_hud;
    }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
inline bool read(xr_read::Handle session,const xr_read::EndInfo* info,const Request& r,Snapshot& result){
    result={};
    if(!r.frame||!r.layout||!r.scene_chain||!r.hud_chain||r.scene_chain==r.hud_chain||!r.scene_width||!r.scene_height||
        !r.hud_width||!r.hud_height||!r.selected.valid||r.selected.session!=reinterpret_cast<uint64_t>(session))return false;
    Snapshot s{};if(!read_layers(info,r.scene_chain,r.hud_chain,&s)||!s.space||s.space!=r.selected.space||
        reinterpret_cast<uint64_t>(s.cylinder.space)!=s.space)return false;
    const auto& c=s.cylinder;
    if(!pose(c.pose)||!std::isfinite(c.radius)||c.radius<=0||!std::isfinite(c.centralAngle)||c.centralAngle<=0||c.centralAngle>6.283186f||
        !std::isfinite(c.aspectRatio)||c.aspectRatio<=0||c.subImage.imageArrayIndex||!rect(c.subImage.imageRect,r.hud_width,r.hud_height))return false;
    for(unsigned i=0;i<2;i++){
        const auto& e=s.eyes[i];
        if(!pose(e.pose)||!fov(e.fov)||e.subImage.imageArrayIndex||!rect(e.subImage.imageRect,r.scene_width,r.scene_height)||
            std::memcmp(&e.pose,&r.selected.poses[i],sizeof(e.pose))||std::memcmp(&e.fov,&r.selected.fovs[i],sizeof(e.fov)))return false;
    }
    if(overlap(s.eyes[0].subImage.imageRect,s.eyes[1].subImage.imageRect))return false;
    s.frame=r.frame;s.layout=r.layout;s.session=reinterpret_cast<uint64_t>(session);s.selected_frame=r.selected.frame;
    s.hud_width=r.hud_width;s.hud_height=r.hud_height;result=s;return true;
}
inline bool constants(const Snapshot& s,unsigned eye,uint64_t region_frame,uint64_t region_layout,const float (&bounds)[4],Constants& out){
    out={};if(eye>1||!s.frame||region_frame!=s.frame||!s.layout||region_layout!=s.layout||!s.hud_width||!s.hud_height)return false;
    for(float value:bounds)if(!std::isfinite(value)||value<0||value>1)return false;
    if(bounds[0]>=bounds[2]||bounds[1]>=bounds[3])return false;
    const auto& c=s.cylinder;const auto& e=s.eyes[eye];
    if(!pose(c.pose)||!pose(e.pose)||!fov(e.fov)||!rect(c.subImage.imageRect,s.hud_width,s.hud_height)||
        !std::isfinite(c.radius)||c.radius<=0||!std::isfinite(c.centralAngle)||c.centralAngle<=0||
        !std::isfinite(c.aspectRatio)||c.aspectRatio<=0||e.subImage.imageRect.extent.width<=0||e.subImage.imageRect.extent.height<=0)return false;
    Constants p{};
    auto quaternion=[](const xr_read::Quaternion& q,float (&v)[4]){
        const float n=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);v[0]=q.x/n;v[1]=q.y/n;v[2]=q.z/n;v[3]=q.w/n;
    };
    quaternion(c.pose.orientation,p.cylinder_quaternion);quaternion(e.pose.orientation,p.eye_quaternion);
    p.cylinder_position_radius[0]=c.pose.position.x;p.cylinder_position_radius[1]=c.pose.position.y;p.cylinder_position_radius[2]=c.pose.position.z;p.cylinder_position_radius[3]=c.radius;
    p.eye_position_angle[0]=e.pose.position.x;p.eye_position_angle[1]=e.pose.position.y;p.eye_position_angle[2]=e.pose.position.z;p.eye_position_angle[3]=c.centralAngle;
    p.fov_tangents[0]=std::tan(e.fov.angleLeft);p.fov_tangents[1]=std::tan(e.fov.angleRight);p.fov_tangents[2]=std::tan(e.fov.angleUp);p.fov_tangents[3]=std::tan(e.fov.angleDown);
    // Owned outputs cover each exact eye subrectangle. Packing offsets are kept
    // in Snapshot for the later destination copy, never folded into HUD UVs.
    p.eye_rectangle[2]=float(e.subImage.imageRect.extent.width);p.eye_rectangle[3]=float(e.subImage.imageRect.extent.height);
    p.scene_size_aspect[0]=p.eye_rectangle[2];p.scene_size_aspect[1]=p.eye_rectangle[3];p.scene_size_aspect[2]=c.aspectRatio;
    const auto& r=c.subImage.imageRect;
    p.source_scale_bias[0]=float(r.extent.width)/s.hud_width;p.source_scale_bias[1]=float(r.extent.height)/s.hud_height;
    p.source_scale_bias[2]=float(r.offset.x)/s.hud_width;p.source_scale_bias[3]=float(r.offset.y)/s.hud_height;
    std::memcpy(p.panel_bounds,bounds,sizeof(bounds));out=p;return true;
}
}
