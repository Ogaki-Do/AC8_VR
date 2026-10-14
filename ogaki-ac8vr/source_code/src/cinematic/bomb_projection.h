// Establish the current bomb widget/canvas draw scope and validate its camera
// schema. This scope restricts the circle and line corrections to the intended
// primitive; unrelated world projections must keep the native result.

#pragma once
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <algorithm>
#include <sstream>
// Native LiveExplosivePredicationWidget draw slot165 calls both trajectory and
// landing-circle helpers. Keep all game geometry/ballistics and native screen
// conversion, but use the normal camera lens and pose within ONLY this draw.
namespace bomb_projection {
using Object=UEVR_UObjectHandle;using Draw=void(*)(Object,Object);
struct Scope {bool active=false;double fov=0,aspect=0,width=0,height=0,calibratedFov=0;};
struct OriginAttachment {bool active=false;double horizontal=0;};
inline thread_local OriginAttachment originAttachment{};
inline thread_local Scope scope{};
inline thread_local Object scopedCanvas=nullptr,scopedWidget=nullptr;
inline const UEVR_PluginInitializeParam* host=nullptr;
inline Draw original=nullptr;
inline std::atomic<double> fovAdjustmentDegrees=0;
inline std::atomic<bool> calibrationEnabled=false;
inline bool installed=false;
inline UEVR_UClassHandle widgetClass=nullptr,canvasClass=nullptr;
inline UEVR_UFunctionHandle fovFunction=nullptr;
constexpr uintptr_t drawRva=0x723cd60;
constexpr std::array<unsigned char,32> drawHead{{0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x20,0x48,0x8b,0xda,0x48,0x8b,0xf9,0xe8,0x1b,0x00,0x00,0x00,0x48,0x8b,0xd3,0x48,0x8b,0xcf,0x48,0x8b,0x5c,0x24,0x30}};
inline bool validLens(double fov,double aspect){return std::isfinite(fov+aspect)&&fov>.25&&fov<170&&aspect>.5&&aspect<5;}
inline double adjustedFov(double native){
 const auto delta=calibrationEnabled.load()?fovAdjustmentDegrees.load():0;
 return delta==0?native:std::clamp(native+delta,1.0,169.0);
}
inline double currentFov(){return scope.calibratedFov>0?scope.calibratedFov:adjustedFov(scope.fov);}
inline bool scalePixel(double& x,double& y){
 if(!scope.active||!calibrationEnabled.load()||scope.width<=0||scope.height<=0||!validLens(scope.fov,scope.aspect))return false;
 const double target=currentFov();if(target==scope.fov||!validLens(target,scope.aspect)||!std::isfinite(x+y))return false;
 const double ratio=std::tan(scope.fov*3.14159265358979323846/360)/std::tan(target*3.14159265358979323846/360);
 const double cx=scope.width/2,cy=scope.height/2;x=cx+(x-cx)*ratio;y=cy+(y-cy)*ratio;return true;
}
inline void calibrationControl(const char* event,const char* data){
 if(!event||std::strcmp(event,"AC8_BombProjectionControls")||!data)return;
 int enabled=0,keyboard=0,flight=0;double adjustment=0;char a=0,b=0,c=0;std::istringstream in(data);
 if(!(in>>enabled>>a>>adjustment>>b>>keyboard>>c>>flight)||a!='|'||b!='|'||c!='|'||(enabled!=0&&enabled!=1)||(keyboard!=0&&keyboard!=1)||(flight!=0&&flight!=1)||!std::isfinite(adjustment)||adjustment< -40||adjustment>40)return;
 in>>std::ws;if(!in.eof())return;
 fovAdjustmentDegrees=adjustment;calibrationEnabled=enabled!=0;
}
template<class T> inline bool read(const void* p,T& value){SIZE_T n=0;return p&&ReadProcessMemory(GetCurrentProcess(),p,&value,sizeof(value),&n)&&n==sizeof(value);}
inline Object reference(Object o,const wchar_t* name){Object value=nullptr;if(o)read(host->sdk->uobject->get_property_data(o,name),value);return value;}
inline bool cameraLens(Object widget,Object canvas,Scope& value){
    auto* sdk=host->sdk;
    if(!widgetClass)widgetClass=reinterpret_cast<UEVR_UClassHandle>(sdk->uobject_array->find_uobject(L"Class /Script/Live.LiveExplosivePredicationWidget"));
    if(!canvasClass)canvasClass=reinterpret_cast<UEVR_UClassHandle>(sdk->uobject_array->find_uobject(L"Class /Script/Live.LiveDynamicDrawCanvas"));
    if(!widgetClass||!canvasClass||!widget||!canvas||!sdk->uobject->is_a(widget,widgetClass)||!sdk->uobject->is_a(canvas,canvasClass))return false;
    auto pc=sdk->functions->get_player_controller(0);auto hud=reference(widget,L"CachedLiveHUD");
    if(!pc||!hud||reference(pc,L"MyHUD")!=hud)return false;
    auto manager=reference(pc,L"PlayerCameraManager");if(!manager)return false;
    if(!fovFunction){
        auto cls=reinterpret_cast<UEVR_UStructHandle>(sdk->uobject->get_class(manager));auto fn=sdk->ustruct->find_function(cls,L"GetFOVAngle");
        if(!fn)return false;auto structure=reinterpret_cast<UEVR_UStructHandle>(fn);auto ret=sdk->ustruct->find_property(structure,L"ReturnValue");
        if(!ret||sdk->ustruct->get_properties_size(structure)!=4||sdk->fproperty->get_offset(ret)!=0||!sdk->fproperty->is_return_param(ret))return false;
        fovFunction=fn;
    }
    float fov=0;sdk->uobject->process_event(manager,fovFunction,&fov);
    const auto width=host->vr->get_ui_width(),height=host->vr->get_ui_height();
    const double aspect=height?static_cast<double>(width)/height:0;
    if(!validLens(fov,aspect))return false;value={true,fov,aspect,static_cast<double>(width),static_cast<double>(height),adjustedFov(fov)};return true;
}
inline void wrapper(Object widget,Object canvas){
 const auto oldScope=scope;const auto oldCanvas=scopedCanvas;const auto oldWidget=scopedWidget;const auto oldAttachment=originAttachment;Scope value{};
 scope=cameraLens(widget,canvas,value)?value:Scope{};
 scopedCanvas=scope.active?canvas:nullptr;scopedWidget=scope.active?widget:nullptr;originAttachment={};
 struct Restore {Scope old;Object canvas,widget;OriginAttachment attachment;~Restore(){scope=old;scopedCanvas=canvas;scopedWidget=widget;originAttachment=attachment;}}restore{oldScope,oldCanvas,oldWidget,oldAttachment};
 if(original)original(widget,canvas);
}
#ifndef AC8_BOMB_PROJECTION_FIXTURE
inline bool initialize(const UEVR_PluginInitializeParam* p){
    host=p;if(!p||!p->sdk||!p->vr||!p->vr->get_ui_width||!p->vr->get_ui_height||!p->callbacks||!p->callbacks->on_custom_event)return false;
    auto* sdk=p->sdk;if(!sdk->uobject||!sdk->uobject->is_a||!sdk->uobject_array||!sdk->ustruct||!sdk->fproperty||!sdk->functions||!sdk->callbacks)return false;
    auto module=GetModuleHandleW(nullptr);wchar_t path[32768]{};std::string hash;std::array<unsigned char,32> bytes{};
    if(!module||!GetModuleFileNameW(module,path,32768)||!boundary::file_hash(path,hash)||hash!="51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F"||
       !read(reinterpret_cast<unsigned char*>(module)+drawRva,bytes)||bytes!=drawHead){return false;}
    // Retain only the verified current-bomb draw scope. Matrix corrections
    // belong to bomb_circle.h and are restored after its scoped draw.
    const int id=p->functions->register_inline_hook(reinterpret_cast<unsigned char*>(module)+drawRva,reinterpret_cast<void*>(&wrapper),reinterpret_cast<void**>(&original));
    installed=id>=0&&original;if(!installed&&id>=0)p->functions->unregister_inline_hook(id);
    return installed;
}
#endif
}
