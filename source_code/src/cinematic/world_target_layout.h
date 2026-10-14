// Temporarily supply flat-style text metrics during a target's native update.
// The left label has its own correction. Nested scopes avoid repeated scaling;
// original fields are restored and native introduction animation state is kept.

#pragma once
#include <array>
#include <mutex>
#include <cmath>
#include <cstring>
#include <fstream>
// Box construction is native; the Lua post-tick writer owns persistent size.
// Native update scopes retain only the accepted text metrics/left-label correction.
// The introduction's initial geometry and animation state remain native.
namespace world_target_layout {
using Object=UEVR_UObjectHandle;
using SizeFunction=void(*)(Object);
using UpdateFunction=void(*)(Object,const void*,const void*);
struct Position {double x,y,z;};
using PlacementFunction=void(*)(const void*,Object,const Position*);
inline const UEVR_PluginInitializeParam* host=nullptr;
inline uintptr_t gameBase=0;
inline bool ready=false;
inline SizeFunction originalSize=nullptr;
inline UpdateFunction originalUpdate=nullptr;
inline PlacementFunction originalPlacement=nullptr;
struct Controls {uintptr_t level=0;bool enabled=false;float box=1,label=1,font=1,spacing=0;bool flat=true;float raise=0,leftDrop=0;};
inline Controls controls{};
inline std::mutex lock;
inline thread_local Object scopedActor=nullptr;
struct Field {const wchar_t* name;size_t offset;};
inline constexpr std::array<Field,14> fields{{
 {L"TextRenderOffsetX",0x328},{L"TextRenderOffsetY",0x32c},
 {L"AllianceTextRenderOffsetYMax",0x330},{L"AllianceTextRenderOffsetYMin",0x334},
 {L"NextTextRenderOffsetYMax",0x338},{L"NextTextRenderOffsetYMin",0x33c},
 {L"SelectTargetAddContainerBoxSize",0x340},{L"BaseTextRenderOffsetY",0x344},
 {L"VRTextRenderOffsetX",0x348},{L"VRTextRenderOffsetY",0x34c},
 {L"VRBaseTextRenderOffsetY",0x350},{L"ContainerBoxImageSize",0x354},
 {L"TextScreenHeight",0x358},{L"TextYSpacing",0x5d8}
}};
template<class T>inline bool read(const void* p,T& value){SIZE_T size=0;return p&&ReadProcessMemory(GetCurrentProcess(),p,&value,sizeof(value),&size)&&size==sizeof(value);}
inline bool valid(const Controls& c){return std::isfinite(c.box+c.label+c.font+c.spacing+c.raise+c.leftDrop)&&c.box>=.1f&&c.box<=2&&c.label>=.1f&&c.label<=2&&c.font>=.1f&&c.font<=2&&std::abs(c.spacing)<=200&&std::abs(c.raise)<=200&&std::abs(c.leftDrop)<=200;}
inline bool calculate(const std::array<float,14>& input,const Controls& c,std::array<float,14>& output){
 if(!valid(c))return false;
 for(float value:input)if(!std::isfinite(value)||std::abs(value)>10000)return false;
 output=input;if(!c.enabled)return true;
 for(size_t i=0;i<12;++i)if(i!=6&&i!=11)output[i]=input[i]*c.box; // dimensions already persistently scaled by Lua
 output[12]=input[12]*c.label*c.font;
 output[13]=(input[13]+c.spacing)*c.label*c.font;
 // Native VR offsets keep an unscaled vertical bias. Use the flat authored
 // anchor distances scaled with the box, while retaining each label's logic.
 if(c.flat){output[8]=output[0];output[9]=output[1];output[10]=output[7];}
 output[7]+=c.raise;output[10]+=c.raise;
 return true;
}
inline bool snapshot(Controls& value){std::unique_lock<std::mutex> guard(lock,std::try_to_lock);if(!guard.owns_lock())return false;value=controls;return true;}
struct Scope {
 Object actor=nullptr,previous=nullptr;std::array<float,14> original{};
 Scope(Object value){
  Controls c{};uintptr_t table=0;uint32_t flags=0;
  if(!ready||!value||value==scopedActor||!snapshot(c)||!c.enabled||!c.level||
   !read(value,table)||table!=gameBase+0xca8eb78||
   !read(reinterpret_cast<unsigned char*>(value)+8,flags)||(flags&0x30)||
   reinterpret_cast<uintptr_t>(host->sdk->uobject->get_outer(value))!=c.level)return;
  for(size_t i=0;i<fields.size();++i)if(!read(reinterpret_cast<unsigned char*>(value)+fields[i].offset,original[i]))return;
  std::array<float,14> wanted{};if(!calculate(original,c,wanted))return;
  actor=value;previous=scopedActor;scopedActor=value;
  for(size_t i=0;i<fields.size();++i)std::memcpy(reinterpret_cast<unsigned char*>(actor)+fields[i].offset,&wanted[i],sizeof(float));
 }
 ~Scope(){if(actor){for(size_t i=0;i<fields.size();++i)std::memcpy(reinterpret_cast<unsigned char*>(actor)+fields[i].offset,&original[i],sizeof(float));scopedActor=previous;}}
};
inline void sizeWrapper(Object actor){if(originalSize)originalSize(actor);} // no initial geometry scope
inline void updateWrapper(Object actor,const void* update,const void* extra){Scope scope(actor);if(originalUpdate)originalUpdate(actor,update,extra);}
// The native placement helper writes each label's freshly computed location.
// Correct only AllianceText inside the verified current-actor update scope.
inline bool leftPosition(const void* context,Object component,const Position* input,Position& output){
 Controls c{};Object actor=nullptr,alliance=nullptr;double height=0;
 if(!ready||!scopedActor||!snapshot(c)||!c.enabled||c.leftDrop==0||
  !read(context,actor)||actor!=scopedActor||
  !read(reinterpret_cast<unsigned char*>(actor)+0x2f8,alliance)||component!=alliance||
  !read(reinterpret_cast<unsigned char*>(actor)+0x7e8,height)||!std::isfinite(height)||height<100||height>10000||
  !read(input,output)||!std::isfinite(output.x+output.y+output.z))return false;
 // Native +Y places AllianceText above the container, so a positive drop
 // subtracts authored pixels divided by the same native viewport height.
 output.y-=c.leftDrop/height;return true;
}
inline void placementWrapper(const void* context,Object component,const Position* input){
 if(!originalPlacement)return;Position adjusted{};
 originalPlacement(context,component,leftPosition(context,component,input,adjusted)?&adjusted:input);
}
inline void control(const char* event,const char* data){
 if(!event||std::strcmp(event,"AC8_WorldTargetLayout")||!data)return;
 Controls c{};unsigned enabled=0,flat=0;unsigned long long level=0;char extra=0;
 int count=sscanf_s(data,"%llu|%u|%f|%f|%f|%f|%u|%f|%f%c",&level,&enabled,&c.box,&c.label,&c.font,&c.spacing,&flat,&c.raise,&c.leftDrop,&extra,1u);
 if(count!=9){c.leftDrop=0;count=sscanf_s(data,"%llu|%u|%f|%f|%f|%f|%u|%f%c",&level,&enabled,&c.box,&c.label,&c.font,&c.spacing,&flat,&c.raise,&extra,1u);if(count!=8)return;}
 if(enabled>1||flat>1||!valid(c))return;
 c.level=static_cast<uintptr_t>(level);c.enabled=enabled!=0;c.flat=flat!=0;
 std::lock_guard<std::mutex> guard(lock);controls=c;
}
#ifndef AC8_WORLD_TARGET_FIXTURE
inline bool schema(){
 const auto cls=host->sdk->uobject_array->find_uobject(L"Class /Script/Live.LiveTargetContainerActor");if(!cls)return false;
 for(const auto& field:fields){const auto p=host->sdk->ustruct->find_property(reinterpret_cast<UEVR_UStructHandle>(cls),field.name);
  if(!p||host->sdk->fproperty->get_offset(p)!=static_cast<int>(field.offset))return false;
  const auto type=host->sdk->ffield->get_class(reinterpret_cast<UEVR_FFieldHandle>(p));wchar_t name[64]{};
  if(!type)return false;host->sdk->fname->to_string(host->sdk->ffield_class->get_fname(type),name,64);if(std::wcscmp(name,L"FloatProperty"))return false;
 }
 const auto alliance=host->sdk->ustruct->find_property(reinterpret_cast<UEVR_UStructHandle>(cls),L"AllianceText");
 if(!alliance||host->sdk->fproperty->get_offset(alliance)!=0x2f8)return false;
 const auto type=host->sdk->ffield->get_class(reinterpret_cast<UEVR_FFieldHandle>(alliance));wchar_t name[64]{};
 if(!type)return false;host->sdk->fname->to_string(host->sdk->ffield_class->get_fname(type),name,64);
 return std::wcscmp(name,L"ObjectProperty")==0;
}
inline bool initialize(const UEVR_PluginInitializeParam* p){
 host=p;const auto module=GetModuleHandleW(nullptr);gameBase=reinterpret_cast<uintptr_t>(module);
 wchar_t filename[32768]{};std::string hash;
 constexpr std::array<unsigned char,32> updateHead{{0x4c,0x89,0x44,0x24,0x18,0x48,0x89,0x54,0x24,0x10,0x55,0x56,0x41,0x55,0x48,0x8d,0xac,0x24,0xd0,0xfa,0xff,0xff,0x48,0x81,0xec,0x30,0x06,0,0,0x48,0x83,0xb9}};
 constexpr std::array<unsigned char,32> placementHead{{0x48,0x83,0xec,0x48,0x48,0x8b,0x1,0xf,0x10,0x82,0xa0,0x1,0x0,0x0,0xf2,0xf,0x10,0xd,0xfa,0x54,0x2,0x6,0xf2,0xf,0x5e,0x88,0xe8,0x7,0x0,0x0,0x48,0x8b}};
 std::array<unsigned char,32> b{},d{};
 if(!module||!GetModuleFileNameW(module,filename,32768)||!boundary::file_hash(filename,hash)||hash!="51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F"||
  !schema()||!read(reinterpret_cast<void*>(gameBase+0x72802d0),b)||b!=updateHead||!read(reinterpret_cast<void*>(gameBase+0x7284990),d)||d!=placementHead)return false;
 const int second=p->functions->register_inline_hook(reinterpret_cast<void*>(gameBase+0x72802d0),reinterpret_cast<void*>(&updateWrapper),reinterpret_cast<void**>(&originalUpdate));
 const int third=p->functions->register_inline_hook(reinterpret_cast<void*>(gameBase+0x7284990),reinterpret_cast<void*>(&placementWrapper),reinterpret_cast<void**>(&originalPlacement));
 ready=second>=0&&third>=0&&originalUpdate&&originalPlacement&&p->callbacks->on_custom_event(control);
 if(!ready){if(second>=0)p->functions->unregister_inline_hook(second);if(third>=0)p->functions->unregister_inline_hook(third);originalSize=nullptr;originalUpdate=nullptr;originalPlacement=nullptr;}
 return ready;
}
#endif
}
