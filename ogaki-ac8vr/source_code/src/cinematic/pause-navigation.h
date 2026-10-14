// Prevent one pause-menu input from advancing twice through duplicate widget
// ticks. Suppression requires a pause-owned live object, an extra-viewport route
// and recent native-texture tick evidence. Unknown routes always forward.
// Stack inspection here is functional routing, not a capture/report feature.

#pragma once
#include <map>
#include <mutex>
#include <atomic>
// Native pause-class ownership includes the active page and command list.
// Retain native texture ticks and painting. Only the extra viewport tick is skipped.
// Unknown/mixed routes pass; no keyboard/controller messages are consumed.
namespace pause_navigation {
using Object=UEVR_UObjectHandle;using Tick=void(*)(Object,const void*,float);
inline const UEVR_PluginInitializeParam* host=nullptr;
inline std::mutex mutex;
inline std::atomic<uint64_t> engine=0;
inline std::array<Tick,8> originals{};
inline std::array<uintptr_t,8> targets{};
inline unsigned hookCount=0;
inline std::atomic<bool> paused=false;
inline std::atomic<bool> guard_enabled{true};
inline bool skip_pause_viewport(bool owned,unsigned route,bool isPaused){return owned&&isPaused&&route==1u;}
inline void control(const char* event,const char* data){
 if(!event||std::strcmp(event,"AC8_PauseTickGuard")||!data)return;
 if(!std::strcmp(data,"on"))guard_enabled=true;
 else if(!std::strcmp(data,"off"))guard_enabled=false;
}
inline constexpr const wchar_t* pauseClasses[]={
 L"Class /Script/Live.LiveMenuPauseWidget",
 L"Class /Script/Live.LiveMenuPauseCommandListWidget",
 L"Class /Script/Live.LiveMenuPauseBootWidget",
 L"Class /Script/Live.LiveMenuPauseDerivationWidget",
 L"Class /Script/Live.LiveMenuPauseMusicPlayerWidfget"
};
inline unsigned missingClasses=0,hookBudgetMisses=0;
inline Object currentInstance=nullptr;
inline std::array<std::atomic<uint64_t>,4> routeCounts{};
#ifdef AC8_PAUSE_FIXTURE
inline unsigned (*stackProvider)(std::array<void*,96>&)=nullptr;
#endif
inline std::atomic<uint64_t> forwarded=0,suppressed=0;
inline thread_local uintptr_t executing=0;
struct Last {uint64_t ordinal=0;std::array<unsigned char,40> identity{};};
inline std::map<uintptr_t,Last> last;
inline bool buildAccepted=false;
inline unsigned detouredTargets=0;
inline uint64_t nextDiscovery=0;

struct Subject {uintptr_t object=0;std::array<unsigned char,40> identity{};std::wstring name,nativeClass;bool pauseOwned=false,nativeSeen=false;uint64_t nativeOrdinal=0;};
inline std::map<uintptr_t,Subject> subjects;

inline bool valid(const Subject& s){
 if(host&&(!host->sdk->uobject_hook->exists(reinterpret_cast<Object>(s.object))))return false;
 std::array<unsigned char,40> header{};unsigned flags=0;
 if(!object_access::read(reinterpret_cast<void*>(s.object),header))return false;
 // RF flags legitimately change during normal UObject/Slate work. Compare the
 // vtable, index, class, FName and outer; reject destruction flags separately.
 if(std::memcmp(header.data(),s.identity.data(),8)||std::memcmp(header.data()+12,s.identity.data()+12,28))return false;
 std::memcpy(&flags,header.data()+8,4);return !(flags&(0x8000u|0x10000u|0x40000000u));
}

template<unsigned slot> inline void wrapper(Object object,const void* geometry,float delta){
    const auto address=reinterpret_cast<uintptr_t>(object);const auto original=originals[slot];
    if(address&&address==executing){if(original)original(object,geometry,delta);return;}
    Subject subject{};unsigned route=0;
    if(paused){std::lock_guard<std::mutex> guard(mutex);auto found=subjects.find(address);
        if(found!=subjects.end()&&valid(found->second))subject=found->second;}
    if(guard_enabled&&skip_pause_viewport(subject.pauseOwned,1u,paused.load())){
        std::array<void*,96> frames{};unsigned depth=0;
#ifdef AC8_PAUSE_FIXTURE
        if(stackProvider)depth=stackProvider(frames);else
#endif
        depth=CaptureStackBackTrace(0,static_cast<DWORD>(frames.size()),frames.data(),nullptr);
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));bool viewport=false,native=false;
        for(unsigned i=0;i<depth;++i){const auto a=reinterpret_cast<uintptr_t>(frames[i]);viewport|=a==base+0x4ac778d;native|=a==base+0x73011d6;}
        route=viewport?(native?3u:1u):native?2u:0u;
    }
    bool nativeRecent=false;
    if(subject.pauseOwned){++routeCounts[route];std::lock_guard<std::mutex> guard(mutex);auto found=subjects.find(address);
        if(found!=subjects.end()&&valid(found->second)){auto& row=found->second;
            if(route==2u){row.nativeSeen=true;row.nativeOrdinal=engine.load();}
            nativeRecent=row.nativeSeen&&engine.load()>=row.nativeOrdinal&&engine.load()-row.nativeOrdinal<=2;}}
    // Suppress only a duplicate viewport route after this exact object has
    // recently ticked through the game's native texture route. Other routes pass.
    if(guard_enabled&&nativeRecent&&skip_pause_viewport(subject.pauseOwned,route,paused.load()))++suppressed;
    else if(original){const auto previous=executing;executing=address;original(object,geometry,delta);executing=previous;++forwarded;}
}


inline bool gameBuild(){
    const auto base=reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr));IMAGE_DOS_HEADER dos{};IMAGE_NT_HEADERS64 nt{};
    return object_access::read(base,dos)&&dos.e_magic==IMAGE_DOS_SIGNATURE&&dos.e_lfanew>0&&dos.e_lfanew<4096&&
        object_access::read(base+dos.e_lfanew,nt)&&nt.Signature==IMAGE_NT_SIGNATURE&&nt.FileHeader.TimeDateStamp==1788928637&&nt.OptionalHeader.SizeOfImage==563453952;
}
inline void discover(){
    buildAccepted=gameBuild();if(!buildAccepted)return;
    detouredTargets=missingClasses=hookBudgetMisses=0;currentInstance=nullptr;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));std::map<uintptr_t,Subject> current;
    auto* sdk=host->sdk;
    auto pc=sdk->functions->get_player_controller(0);
    if(pc&&!sdk->uobject_hook->exists(pc))pc=nullptr;
    auto hud=pc?object_access::reference(pc,L"MyHUD"):nullptr;
    if(hud&&!sdk->uobject_hook->exists(hud))hud=nullptr;
    auto root=hud?object_access::reference(hud,L"HudMenuWidget"):nullptr;
    if(!root&&hud)root=object_access::reference(hud,L"GlowWidgetPtr");
    if(root&&sdk->uobject_hook->exists(root))currentInstance=sdk->uobject->get_outer(root);
    auto gi=sdk->uobject_array->find_uobject(L"Class /Script/Engine.GameInstance");
    if(!currentInstance||!gi||!sdk->uobject_hook->exists(currentInstance)||!sdk->uobject->is_a(currentInstance,reinterpret_cast<UEVR_UClassHandle>(gi))){
        std::lock_guard<std::mutex> guard(mutex);subjects.clear();return;
    }
    for(const auto className:pauseClasses){
      auto klass=sdk->uobject_array->find_uobject(className);if(!klass){++missingClasses;continue;}
      std::array<Object,256> objects{};
      const int count=sdk->uobject_hook->get_objects_by_class(reinterpret_cast<UEVR_UClassHandle>(klass),objects.data(),static_cast<unsigned>(objects.size()),false);
      for(int i=0;i<std::min(count,256)&&current.size()<256;++i){
        auto o=objects[static_cast<size_t>(i)];if(!o||current.count(reinterpret_cast<uintptr_t>(o))||!sdk->uobject_hook->exists(o)||!sdk->uobject->is_a(o,reinterpret_cast<UEVR_UClassHandle>(klass)))continue;
        auto owner=o;bool owned=false;
        for(unsigned depth=0;owner&&depth<16;++depth){if(!sdk->uobject_hook->exists(owner))break;if(owner==currentInstance){owned=true;break;}owner=sdk->uobject->get_outer(owner);}
        if(!owned)continue;
        unsigned flags=0;if(!object_access::read(reinterpret_cast<unsigned char*>(o)+8,flags)||(flags&(0x10u|0x20u|0x8000u|0x10000u|0x40000000u)))continue;
        // Native rendering may own visibility outside the ordinary viewport.
        // An object that is never ticked cannot trigger this guard.
        uintptr_t table=0,address=0;if(!object_access::read(o,table)||!object_access::read(reinterpret_cast<void*>(table+111*sizeof(uintptr_t)),address)||address<base||address>=base+563453952)continue;
        unsigned slot=0;for(;slot<hookCount;++slot)if(targets[slot]==address)break;
        if(slot==hookCount){if(hookCount>=originals.size()){++hookBudgetMisses;continue;}MEMORY_BASIC_INFORMATION memory{};unsigned char head=0;
            if(!VirtualQuery(reinterpret_cast<void*>(address),&memory,sizeof(memory))||!(memory.Protect&(PAGE_EXECUTE|PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY))||!object_access::read(reinterpret_cast<void*>(address),head))continue;
            if(head==0xe9||head==0xeb||head==0xff){++detouredTargets;continue;}
            void* wrappers[]={reinterpret_cast<void*>(&wrapper<0>),reinterpret_cast<void*>(&wrapper<1>),reinterpret_cast<void*>(&wrapper<2>),reinterpret_cast<void*>(&wrapper<3>),reinterpret_cast<void*>(&wrapper<4>),reinterpret_cast<void*>(&wrapper<5>),reinterpret_cast<void*>(&wrapper<6>),reinterpret_cast<void*>(&wrapper<7>)};
            const int id=host->functions->register_inline_hook(reinterpret_cast<void*>(address),wrappers[slot],reinterpret_cast<void**>(&originals[slot]));
            if(id<0||!originals[slot])continue;targets[slot]=address;++hookCount;
        }
        Subject s{};s.object=reinterpret_cast<uintptr_t>(o);s.name=object_access::path(o);s.nativeClass=className;s.pauseOwned=true;if(!object_access::read(o,s.identity))continue;
        current[s.object]=std::move(s);
      }
    }
    std::lock_guard<std::mutex> guard(mutex);
    for(auto& entry:current){auto old=subjects.find(entry.first);if(old!=subjects.end()&&valid(old->second)){
        entry.second.nativeSeen=old->second.nativeSeen;entry.second.nativeOrdinal=old->second.nativeOrdinal;
    }}
    subjects=std::move(current);
}

// Reflection metadata is stable across frames; pause state and the controller
// are not. Keep querying IsGamePaused each tick, but bind its schema once.
// Property descriptors are used only during binding, never retained. UObject
// identities include index/class/name/outer so address reuse triggers a rebind.
struct PauseQueryCache {
    const UEVR_PluginInitializeParam* owner=nullptr;
    Subject klass{},object{},function{};
    bool ready=false;
};
inline PauseQueryCache pauseQuery;
inline bool rememberQueryObject(Object object,Subject& identity){
    if(!object||!host->sdk->uobject_hook->exists(object))return false;
    identity.object=reinterpret_cast<uintptr_t>(object);
    return object_access::read(object,identity.identity)&&valid(identity);
}
inline bool bindPauseQuery(){
    pauseQuery={};
    auto cls=host->sdk->uobject_array->find_uobject(L"Class /Script/Engine.GameplayStatics");if(!cls||!host->sdk->uclass)return false;
    Subject classIdentity{};if(!rememberQueryObject(cls,classIdentity))return false;
    auto object=host->sdk->uclass->get_class_default_object(reinterpret_cast<UEVR_UClassHandle>(cls));
    Subject objectIdentity{};if(!rememberQueryObject(object,objectIdentity))return false;
    auto function=host->sdk->ustruct->find_function(reinterpret_cast<UEVR_UStructHandle>(cls),L"IsGamePaused");
    Subject functionIdentity{};if(!rememberQueryObject(reinterpret_cast<Object>(function),functionIdentity))return false;
    auto structure=reinterpret_cast<UEVR_UStructHandle>(function);const auto size=host->sdk->ustruct->get_properties_size(structure);
    auto context=host->sdk->ustruct->find_property(structure,L"WorldContextObject"),ret=host->sdk->ustruct->find_property(structure,L"ReturnValue");
    if(size<9||size>16||!context||!ret||object_access::type(context)!=L"ObjectProperty"||object_access::type(ret)!=L"BoolProperty"||host->sdk->fproperty->get_offset(context)!=0||host->sdk->fproperty->get_offset(ret)!=8)return false;
    pauseQuery.owner=host;pauseQuery.klass=std::move(classIdentity);pauseQuery.object=std::move(objectIdentity);pauseQuery.function=std::move(functionIdentity);pauseQuery.ready=true;
    return true;
}
inline bool gamePaused(){
    if(!host||!host->sdk||!host->sdk->uobject_hook)return false;
    if(pauseQuery.owner!=host||!pauseQuery.ready||!valid(pauseQuery.klass)||!valid(pauseQuery.object)||!valid(pauseQuery.function)){
        if(!bindPauseQuery())return false;
    }
    std::array<unsigned char,16> args{};auto pc=host->sdk->functions->get_player_controller(0);
    Subject controller{};if(!rememberQueryObject(pc,controller))return false;
    std::memcpy(args.data(),&pc,8);
    host->sdk->uobject->process_event(reinterpret_cast<Object>(pauseQuery.object.object),reinterpret_cast<UEVR_UFunctionHandle>(pauseQuery.function.object),args.data());
    return args[8]!=0;
}
inline void tick(UEVR_UGameEngineHandle,float){
    ++engine;if(!host)return;const auto now=GetTickCount64();const bool wasPaused=paused.load();paused=gamePaused();
    if(guard_enabled&&paused){
        if(!wasPaused||now>=nextDiscovery){discover();nextDiscovery=now+500;}
    }else if(wasPaused){std::lock_guard<std::mutex> guard(mutex);subjects.clear();}
}
}
