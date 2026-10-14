// Connect verified projection/map call sites to the bomb attachment helpers.
// The game remains responsible for ballistics, predicted impact and styling.
// Caller signatures and the current draw scope gate each adjustment.

#pragma once
#include <intrin.h>
#include "bomb_projection.h"
#include "bomb_circle.h"
#include "bomb_line_anchor.h"
// Accepted rendering support only: no recording hooks, telemetry, pose samples,
// trace buffers, capture events or file output.
namespace bomb_render {
using Object=UEVR_UObjectHandle;
struct Vec{double x,y,z;};struct XY{double x,y;};
using Project=bool(*)(Object,const Vec*,XY*,bool);
using Map=void(*)(Object,const XY*,XY*,XY*);
inline Project projectOriginal=nullptr;inline Map mapOriginal=nullptr;
inline uintptr_t gameBase=0;
inline bool project(Object o,const Vec* p,XY* out,bool relative){
 const bool result=projectOriginal?projectOriginal(o,p,out,relative):false;
 if(result&&bomb_projection::scope.active){XY v{};if(bomb_projection::read(out,v)&&bomb_projection::scalePixel(v.x,v.y))std::memcpy(out,&v,sizeof(v));}
 return result;
}
inline void map(Object o,const XY* p,XY* intermediate,XY* out){
 if(mapOriginal)mapOriginal(o,p,intermediate,out);
 if(!bomb_projection::scope.active)return;
 const auto address=reinterpret_cast<uintptr_t>(_ReturnAddress());const auto caller=address>=gameBase?address-gameBase:address;
 if(caller!=bomb_line_anchor::originCaller&&!bomb_line_anchor::landingCaller(caller))return;
 XY v{};if(!bomb_projection::read(out,v)||!std::isfinite(v.x+v.y))return;
 const bool changed=caller==bomb_line_anchor::originCaller?bomb_line_anchor::apply(caller,v.x,v.y,GetTickCount64()):bomb_line_anchor::applyHorizontal(caller,v.x);
 if(changed)std::memcpy(out,&v,sizeof(v));
}
#include "bomb_render_guards.h"
inline bool initialize(const UEVR_PluginInitializeParam* p){
 if(!p||!bomb_projection::installed||!bomb_circle::installed)return false;
 gameBase=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
 for(const auto& g:guards){std::array<unsigned char,32> bytes{};if(!bomb_projection::read(reinterpret_cast<void*>(gameBase+g.rva),bytes)||bytes!=g.head)return false;}
 const std::array<void*,2> replacements{reinterpret_cast<void*>(&project),reinterpret_cast<void*>(&map)};
 const std::array<void**,2> originals{reinterpret_cast<void**>(&projectOriginal),reinterpret_cast<void**>(&mapOriginal)};
 std::array<int,2> ids{};ids.fill(-1);unsigned attached=0;
 for(unsigned i=0;i<ids.size();++i){ids[i]=p->functions->register_inline_hook(reinterpret_cast<void*>(gameBase+guards[i].rva),replacements[i],originals[i]);if(ids[i]<0||!*originals[i])break;++attached;}
 if(attached!=ids.size()||!p->callbacks->on_custom_event(bomb_projection::calibrationControl)||!p->callbacks->on_custom_event(bomb_line_anchor::control)){
  for(auto id:ids)if(id>=0)p->functions->unregister_inline_hook(id);return false;
 }
 return true;
}
}
