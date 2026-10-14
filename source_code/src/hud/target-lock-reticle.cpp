// UEVR module entry for automatic seeker sizing. Supplies lifetime, naming
// and bounded-read helpers to seeker-auto.h, then activates it on engine ticks.

// Automatic target-lock reticle sizing.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
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
static std::wstring fname(UEVR_FNameHandle n){
    wchar_t buffer[1024]{};if(n)host->sdk->fname->to_string(n,buffer,1024);return buffer;
}
static std::wstring objectName(UEVR_UObjectHandle o){
    if(!o)return L"";
    std::wstring result=fname(host->sdk->uobject->get_fname(o));
    auto outer=host->sdk->uobject->get_outer(o);
    for(int i=0;outer&&outer!=o&&i<16;++i){result=fname(host->sdk->uobject->get_fname(outer))+L"."+result;outer=host->sdk->uobject->get_outer(outer);}
    return result;
}

struct ArrayView{const unsigned char* data;int32_t count,capacity;};
#include "seeker-auto.h"
static void tick(UEVR_UGameEngineHandle,float){++tickCount;seeker_auto::tick();}
extern "C"  void uevr_plugin_required_version(UEVR_PluginVersion* v){v->major=UEVR_PLUGIN_VERSION_MAJOR;v->minor=UEVR_PLUGIN_VERSION_MINOR;v->patch=UEVR_PLUGIN_VERSION_PATCH;}
extern "C"  bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* p){
    if(!p||!p->version||p->version->major!=UEVR_PLUGIN_VERSION_MAJOR||p->version->minor<UEVR_PLUGIN_VERSION_MINOR||!p->sdk||!p->functions||!p->functions->get_persistent_dir||!p->functions->register_inline_hook)return false;
    auto s=p->sdk;
    if(!s->uobject||!s->fname||!s->callbacks||!s->callbacks->on_post_engine_tick)return false;
    host=p;return s->callbacks->on_post_engine_tick(tick);
}
