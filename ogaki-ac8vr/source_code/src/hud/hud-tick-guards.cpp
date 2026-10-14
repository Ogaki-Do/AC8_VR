// Protect native warning/message state from a second viewport tick consuming
// it before the HUD actor sees it. Only verified current HUD/message instances
// are suppressed; object identity and caller-route checks remain mandatory.

// Confirmed duplicate-tick correction. Preserve the native HUD texture updates;
// skip only duplicate game overrides on the separately verified viewport path.
// Preserve native warning/color/message state and viewport painting.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <intrin.h>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <mutex>
#include "../../vendor/uevr/plugin-api.h"
#include "../backend/backend_boundary.h"
#include "menu-gauge-guard.h"
namespace hud_tick_guard {
#include "hud-tick-validation.h"
#include "hud-tick-guard-guards.h"
using Object=UEVR_UObjectHandle;
using WidgetTick=void(*)(Object,const void*,float);
using ActorTick=void(*)(Object,float);
static const UEVR_PluginInitializeParam* host=nullptr;
static WidgetTick originals[2]{};
static ActorTick actorOriginal=nullptr;
static std::array<int,3> hookIDs{{-1,-1,-1}};
static std::mutex gate;
static std::atomic<bool> installed{false};
static std::atomic<bool> guardEnabled{true};
static std::array<std::atomic<ULONGLONG>,2> duplicateSkipped{},widgetForwarded{};
static std::atomic<ULONGLONG> engineOrdinal{0};
static bool attempted=false;
static const char* status="waiting_for_native_hud";
struct Subjects {std::array<Object,3> objects{};std::array<std::array<unsigned char,32>,3> headers{};};
static Subjects subjects{};
struct State {
    bool valid=false;std::array<unsigned char,4> hud{};
    std::array<unsigned char,10> message{};
    unsigned char defaultColor=255,messageTickGate=255;
    std::array<float,4> color{};
};


template<class T> static bool read(const void* address,T& value){
    SIZE_T n=0;return address&&ReadProcessMemory(GetCurrentProcess(),address,&value,sizeof(value),&n)&&n==sizeof(value);
}
static unsigned char* bytes(void* address){return static_cast<unsigned char*>(address);}
static Object property(Object o,const wchar_t* name){
    Object result=nullptr;if(o)read(host->sdk->uobject->get_property_data(o,name),result);return result;
}
static bool validSubjects(const Subjects& s){
    for(size_t i=0;i<3;++i){
        std::array<unsigned char,32> header{};unsigned flags=0;
        if(!read(s.objects[i],header))return false;
        std::memcpy(&flags,header.data()+8,4);
        if(flags&(1u<<30)||std::memcmp(header.data(),s.headers[i].data(),8)||
           std::memcmp(header.data()+12,s.headers[i].data()+12,20))return false;
    }
    Object h=nullptr,r=nullptr,m=nullptr,mh=nullptr;
    return read(bytes(s.objects[0])+0x310,h)&&h==s.objects[2]&&
           read(bytes(h)+0x778,r)&&r==s.objects[0]&&
           read(bytes(h)+0x7e8,m)&&m==s.objects[1]&&
           read(bytes(m)+0x3a8,mh)&&mh==h;
}
static State sample(const Subjects& s){
    State result;if(!validSubjects(s))return result;
    constexpr size_t offsets[]={0xa50,0xa64,0xa65,0xa78};
    for(size_t i=0;i<4;++i)if(!read(bytes(s.objects[2])+offsets[i],result.hud[i]))return result;
    if(!read(bytes(s.objects[1])+0x5d8,result.message)||
       !read(bytes(s.objects[1])+0x1338,result.messageTickGate)||
       !read(bytes(s.objects[0])+0x340,result.defaultColor)||
       !read(bytes(s.objects[0])+0x330,result.color))return result;
    for(float c:result.color)if(!std::isfinite(c))return result;
    result.valid=validSubjects(s);return result;
}
// Unknown or mixed routes always forward. These are exact-build caller return
// addresses, not thread IDs, frame heuristics, message strings or color guesses.
enum class Route:unsigned {Unknown=0,ExtraViewport=1,NativeTexture=2,Mixed=3};
static Route classify(const void* const* stack,size_t count,uintptr_t base){
    bool viewport=false,native=false;
    for(size_t i=0;i<count;++i){const auto a=reinterpret_cast<uintptr_t>(stack[i]);
        viewport|=a==base+routeReturns[0];native|=a==base+routeReturns[1];}
    return viewport?(native?Route::Mixed:Route::ExtraViewport):(native?Route::NativeTexture:Route::Unknown);
}
#ifdef AC8_HUD_TICK_FIXTURE
static USHORT (*stackProvider)(std::array<void*,48>&)=nullptr;
#endif
static Route currentRoute(){
    std::array<void*,48> stack{};USHORT count=0;
#ifdef AC8_HUD_TICK_FIXTURE
    if(stackProvider)count=stackProvider(stack);else
#endif
    count=CaptureStackBackTrace(0,static_cast<DWORD>(stack.size()),stack.data(),nullptr);
    return classify(stack.data(),count,reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr)));
}
static bool suppress(unsigned kind,Object object,Route route){
    if(route!=Route::ExtraViewport||!guardEnabled.load()||!installed.load())return false;
    Subjects current{};{std::lock_guard<std::mutex> lock(gate);current=subjects;}
    return kind<2&&object==current.objects[kind]&&validSubjects(current);
}



static void rootWrapper(Object o,const void* g,float dt){
    const auto route=guardEnabled.load()&&installed.load()?currentRoute():Route::Unknown;
    if(suppress(0,o,route))++duplicateSkipped[0];else{++widgetForwarded[0];originals[0](o,g,dt);}
}
static void messageWrapper(Object o,const void* g,float dt){
    const auto route=guardEnabled.load()&&installed.load()?currentRoute():Route::Unknown;
    if(suppress(1,o,route))++duplicateSkipped[1];else{++widgetForwarded[1];originals[1](o,g,dt);}
}
static void actorWrapper(Object o,float dt){actorOriginal(o,dt);}
static bool discover(Subjects& s){
    auto pc=host->sdk->functions->get_player_controller(0);s.objects[2]=property(pc,L"MyHUD");
    s.objects[0]=property(s.objects[2],L"HudWidget");s.objects[1]=property(s.objects[0],L"HUDMessageWidget");
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    constexpr size_t slots[]={111,111,159};
    for(size_t i=0;i<3;++i){
        uintptr_t* table=nullptr;uintptr_t tick=0;
        if(!read(s.objects[i],s.headers[i])||!read(s.objects[i],table)||!read(table+slots[i],tick)||tick!=base+tickRVAs[i])return false;
    }
    return validSubjects(s)&&sample(s).valid;
}
static void unregisterAll(){
    for(int i=2;i>=0;--i)if(hookIDs[i]>=0){host->functions->unregister_inline_hook(hookIDs[i]);hookIDs[i]=-1;}
}
static bool registerAll(void* module){
    void* destinations[]={reinterpret_cast<void*>(&rootWrapper),reinterpret_cast<void*>(&messageWrapper),reinterpret_cast<void*>(&actorWrapper)};
    void** trampolines[]={reinterpret_cast<void**>(&originals[0]),reinterpret_cast<void**>(&originals[1]),reinterpret_cast<void**>(&actorOriginal)};
    for(size_t i=0;i<2;++i){
        hookIDs[i]=host->functions->register_inline_hook(bytes(module)+tickRVAs[i],destinations[i],trampolines[i]);
        if(hookIDs[i]<0||!*trampolines[i]){unregisterAll();return false;}
    }
    return true;
}
static void install(const Subjects& s){
    attempted=true;auto module=GetModuleHandleW(nullptr);wchar_t path[32768]{};std::string hash;
    if(!module||!GetModuleFileNameW(module,path,32768)||!boundary::file_hash(path,hash)||
       hash!="51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F"){status="executable_guard_failed";return;}
    IMAGE_DOS_HEADER dos{};IMAGE_NT_HEADERS64 nt{};
    if(!read(module,dos)||dos.e_magic!=IMAGE_DOS_SIGNATURE||dos.e_lfanew<0||dos.e_lfanew>4096||
       !read(bytes(module)+dos.e_lfanew,nt)||nt.Signature!=IMAGE_NT_SIGNATURE||nt.FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||
       nt.FileHeader.TimeDateStamp!=gameTimestamp||nt.OptionalHeader.SizeOfImage!=gameImageSize){status="pe_guard_failed";return;}
    for(size_t i=0;i<3;++i){std::array<unsigned char,32> actual{};
        if(!read(bytes(module)+tickRVAs[i],actual)||std::memcmp(actual.data(),tickHeads[i],32)){status="tick_signature_guard_failed";return;}}
    for(size_t i=0;i<2;++i){std::array<unsigned char,5> actual{};
        if(!read(bytes(module)+routeReturns[i]-5,actual)||std::memcmp(actual.data(),routeHeads[i],5)){status="caller_route_guard_failed";return;}}
    subjects=s;
    if(!registerAll(module)){status="hook_registration_failed_rolled_back";return;}
    installed=true;status="guarding_duplicate_viewport_ticks";
}


static void tick(UEVR_UGameEngineHandle,float){
    const auto ordinal=++engineOrdinal;
    if(!attempted&&ordinal%30==0){Subjects found{};if(discover(found))install(found);}
    if(installed.load()&&ordinal%30==0){Subjects found{};std::lock_guard<std::mutex> lock(gate);subjects=discover(found)?found:Subjects{};}
}
}
extern "C"  void uevr_plugin_required_version(UEVR_PluginVersion* v){v->major=UEVR_PLUGIN_VERSION_MAJOR;v->minor=UEVR_PLUGIN_VERSION_MINOR;v->patch=UEVR_PLUGIN_VERSION_PATCH;}
extern "C"  bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* p){
    if(!p||!p->version||p->version->major!=UEVR_PLUGIN_VERSION_MAJOR||p->version->minor<UEVR_PLUGIN_VERSION_MINOR||
       !p->functions||!p->functions->get_persistent_dir||!p->functions->register_inline_hook||!p->functions->unregister_inline_hook||
       !p->sdk||!p->sdk->functions||!p->sdk->functions->get_player_controller||!p->sdk->uobject||!p->sdk->uobject->get_property_data||
       !p->sdk->callbacks||!p->sdk->callbacks->on_post_engine_tick)return false;
    hud_tick_guard::host=p;
    menu_gauge_guard::initialize(p);
    return p->sdk->callbacks->on_post_engine_tick(hud_tick_guard::tick);
}
