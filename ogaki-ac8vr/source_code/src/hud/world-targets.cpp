// UEVR module entry for reversible world billboard scaling. Supplies guarded
// reflection helpers and current-world discovery to escort-billboard-scale.h.
// Lua supplies the desired scale; native SetElements updates the render state.

// Reversible escort/world-pip scaling through reflected SetElements.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <array>
#include <mutex>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>
#include <cstring>
#include <sstream>
#include "../../vendor/uevr/plugin-api.h"
static const UEVR_PluginInitializeParam* host=nullptr;
static unsigned tickCount=0;
template<class T> bool copy(const void* p,T& value){
    SIZE_T bytes=0;return p&&ReadProcessMemory(GetCurrentProcess(),p,&value,sizeof(value),&bytes)&&bytes==sizeof(value);
}
static std::wstring billboardFname(UEVR_FNameHandle n){
    wchar_t buffer[1024]{};if(n)host->sdk->fname->to_string(n,buffer,1024);return buffer;
}
static std::wstring objectName(UEVR_UObjectHandle o){
    if(!o)return L"";
    std::wstring result=billboardFname(host->sdk->uobject->get_fname(o));
    auto outer=host->sdk->uobject->get_outer(o);
    for(int i=0;outer&&outer!=o&&i<16;++i){result=billboardFname(host->sdk->uobject->get_fname(outer))+L"."+result;outer=host->sdk->uobject->get_outer(outer);}
    return result;
}

struct ArrayView{const unsigned char* data;int32_t count,capacity;};

static std::wstring propertyType(UEVR_FPropertyHandle p){
    auto c=host->sdk->ffield->get_class(reinterpret_cast<UEVR_FFieldHandle>(p));
    return c?billboardFname(host->sdk->ffield_class->get_fname(c)):L"";
}
static UEVR_FPropertyHandle property(UEVR_UStructHandle s,const wchar_t* name){return host->sdk->ustruct->find_property(s,name);}
#include "escort-billboard-scale.h"
static void tick(UEVR_UGameEngineHandle,float){++tickCount;escort_draw::tick();}
extern "C"  void uevr_plugin_required_version(UEVR_PluginVersion* v){v->major=UEVR_PLUGIN_VERSION_MAJOR;v->minor=UEVR_PLUGIN_VERSION_MINOR;v->patch=UEVR_PLUGIN_VERSION_PATCH;}
extern "C"  bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* p){
    if(!p||!p->version||p->version->major!=UEVR_PLUGIN_VERSION_MAJOR||p->version->minor<UEVR_PLUGIN_VERSION_MINOR||!p->sdk||!p->functions||!p->functions->get_persistent_dir)return false;
    auto s=p->sdk;
    if(!s->uobject||!s->ustruct||!s->fname||!s->ffield||!s->ffield_class||!s->fproperty||!s->farrayproperty||!s->fstructproperty||!s->uscriptstruct||!s->uobject_array||!s->uobject_hook||!s->functions||!s->callbacks||!s->callbacks->on_post_engine_tick)return false;
    host=p;
    if(!p->callbacks||!p->callbacks->on_custom_event||!p->callbacks->on_custom_event(escort_draw::control))return false;
    return s->callbacks->on_post_engine_tick(tick);
}
