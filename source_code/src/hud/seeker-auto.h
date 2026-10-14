// Reduce the supported target-lock artwork after a native readback confirms
// its size convention. Readback is required activation validation, not telemetry.
// Exact actor/texture allowlists prevent scaling unrelated billboard artwork.

#pragma once
#include <mutex>
#include "../backend/backend_boundary.h"
namespace seeker_auto {
struct Size {double x,y;};
using Function=void(*)(UEVR_UObjectHandle,UEVR_UObjectHandle,const Size*,const void*,float);
static Function original=nullptr;
static std::atomic<bool> enabled{false};
static std::atomic<bool> validated{false};
static bool attempted=false,installed=false;
static std::atomic<unsigned> calls{0},changed{0};
static std::filesystem::path directory;


static bool textureMatches(UEVR_UObjectHandle texture){
    if(!texture)return false;auto name=objectName(texture);
    for(auto family:{L"01",L"02"})for(int i=0;i<4;++i){auto asset=std::wstring(L"T_HUD_Seeker")+family+L"_00"+std::to_wstring(i);if(name==L"/Game/UI/Texture/HUD/"+asset+L"."+asset)return true;}
    return false;
}
static bool actorMatches(UEVR_UObjectHandle actor){
    if(!actor)return false;auto cls=host->sdk->uobject->get_class(actor);
    auto name=objectName(actor);
    return name.find(L".PersistentLevel.")!=std::wstring::npos&&name.find(L"Default__")==std::wstring::npos&&cls&&fname(host->sdk->uobject->get_fname(reinterpret_cast<UEVR_UObjectHandle>(cls)))==L"BP_ChronicleTexture3DUIActor_C";
}
static bool prepare(const Size* input,float scalar,bool on,Size& result){
    if(!copy(input,result)||!std::isfinite(result.x)||!std::isfinite(result.y)||!std::isfinite(scalar)||std::abs(result.x)>10000||std::abs(result.y)>10000)return false;
    if(!std::isfinite(result.x*scalar)||!std::isfinite(result.y*scalar)||std::abs(result.x*scalar)>100||std::abs(result.y*scalar)>100)return false;
    if(on){result.x*=.25;result.y*=.25;}return true;
}
static void wrapper(UEVR_UObjectHandle actor,UEVR_UObjectHandle texture,const Size* input,const void* color,float scalar){
    auto fn=original;if(!fn)return;
    Size local{};const bool match=actorMatches(actor)&&textureMatches(texture);const bool on=enabled.load();
    if(!match||!prepare(input,scalar,on,local)){fn(actor,texture,input,color,scalar);return;}
    ++calls;if(on)++changed;
    fn(actor,texture,on?&local:input,color,scalar);
        UEVR_UObjectHandle component=nullptr;ArrayView array{};float x=0,y=0;
        bool readback=copy(host->sdk->uobject->get_property_data(actor,L"TextureBox"),component)&&component&&copy(host->sdk->uobject->get_property_data(component,L"Elements"),array)&&array.count==1&&array.data&&copy(array.data+0x14,x)&&copy(array.data+0x18,y);
        if(!on&&readback&&std::abs(x-local.x*scalar)<1e-6&&std::abs(y-local.y*scalar)<1e-6)validated=true;

}
static void install(){
    attempted=true;wchar_t path[32768]{};auto module=GetModuleHandleW(nullptr);std::string hash;
    if(!module||!host->functions->register_inline_hook||!GetModuleFileNameW(module,path,32768)||!boundary::file_hash(path,hash)||hash!="51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F")return;
    auto target=reinterpret_cast<unsigned char*>(module)+0x72a3f00;
    constexpr unsigned char expected[]={0x48,0x8b,0xc4,0x55,0x53,0x57,0x41,0x56,0x41,0x57,0x48,0x8b,0xec,0x48,0x83,0xec,0x60};
    unsigned char actual[sizeof(expected)]{};SIZE_T bytes=0;
    if(!ReadProcessMemory(GetCurrentProcess(),target,actual,sizeof(actual),&bytes)||bytes!=sizeof(actual)||std::memcmp(actual,expected,sizeof(actual)))return;
    installed=host->functions->register_inline_hook(target,reinterpret_cast<void*>(&wrapper),reinterpret_cast<void**>(&original))>=0&&original;
}
static void activate(){enabled=installed&&validated.load();}
static void tick(){
    if(directory.empty()){
        wchar_t p[32768]{};host->functions->get_persistent_dir(p,32768);
        directory=std::filesystem::path(p)/L"data";
    }
    if(!attempted)install();
    activate();

}
}
