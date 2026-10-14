// Scale eligible world billboard elements through reflected SetElements.
// Keep the original and last-applied size separately, including per-axis game
// updates, so repeated discovery never compounds the requested scale.

// Included after world-targets.cpp provides guarded reflection helpers.
#include <map>
#include <set>
#include <cmath>
#include <iomanip>
#include <cstdlib>
namespace escort_draw {
struct Sizes {float x,y;};
struct Saved {std::vector<Sizes> original,last;};
static std::map<std::wstring,Saved> saved;
static bool enabled=false;
static unsigned writes=0,failures=0;
static std::atomic<float> pin_scale{1};
static unsigned componentKind(const std::wstring& name){
    const auto leaf=name.substr(name.rfind(L'.')+1);
    return leaf==L"EscortBillboardImage"?1u:leaf==L"ClockTargetPinBillboardImage"?2u:leaf==L"AntiClockTargetPinBillboardImage"?3u:0u;
}
static void control(const char* event,const char* data){
    if(!event||!data)return;
    if(!std::strcmp(event,"AC8_WorldPipScale")){
        char* end=nullptr;const auto value=std::strtof(data,&end);
        if(end&&end!=data&&!*end&&std::isfinite(value)&&value>=.1f&&value<=2.f)pin_scale=value;
    }
}


static std::filesystem::path directory;
struct View {
    ArrayView array{};int stride=0,x=0,y=0;
    UEVR_UScriptStructHandle structure=nullptr;
};
static bool view(UEVR_UObjectHandle o,View& v){
    auto cls=reinterpret_cast<UEVR_UStructHandle>(host->sdk->uobject->get_class(o));
    auto p=property(cls,L"Elements");if(!p||propertyType(p)!=L"ArrayProperty")return false;
    auto inner=host->sdk->farrayproperty->get_inner(reinterpret_cast<UEVR_FArrayPropertyHandle>(p));
    if(!inner||propertyType(inner)!=L"StructProperty")return false;
    v.structure=host->sdk->fstructproperty->get_struct(reinterpret_cast<UEVR_FStructPropertyHandle>(inner));
    if(!v.structure)return false;
    v.stride=host->sdk->uscriptstruct->get_struct_size(v.structure);
    if(v.stride<8||v.stride>1024)return false;
    for(auto spec:{std::pair<const wchar_t*,int*>(L"BaseSizeX",&v.x),{L"BaseSizeY",&v.y}}){
        auto f=property(reinterpret_cast<UEVR_UStructHandle>(v.structure),spec.first);
        if(!f||propertyType(f)!=L"FloatProperty")return false;
        *spec.second=host->sdk->fproperty->get_offset(f);
        if(*spec.second<0||*spec.second>v.stride-4)return false;
    }
    return copy(host->sdk->uobject->get_property_data(o,L"Elements"),v.array)&&v.array.count>=0&&v.array.count<=16&&v.array.capacity>=v.array.count&&v.array.capacity<=4096&&(!v.array.count||v.array.data);
}
static bool sizes(const View& v,std::vector<Sizes>& values){
    values.clear();
    for(int i=0;i<v.array.count;++i){
        const auto base=v.array.data+static_cast<size_t>(i)*static_cast<size_t>(v.stride);
        Sizes s{};if(!copy(base+v.x,s.x)||!copy(base+v.y,s.y)||!std::isfinite(s.x)||!std::isfinite(s.y)||std::abs(s.x)>100||std::abs(s.y)>100)return false;
        values.push_back(s);
    }
    return true;
}
static bool equal(const std::vector<Sizes>& a,const std::vector<Sizes>& b){
    if(a.size()!=b.size())return false;
    for(size_t i=0;i<a.size();++i)if(std::abs(a[i].x-b[i].x)>1e-7f||std::abs(a[i].y-b[i].y)>1e-7f)return false;
    return true;
}
static std::vector<Sizes> scaled(std::vector<Sizes> values,float factor=.25f){for(auto& s:values){s.x*=factor;s.y*=factor;}return values;}
static bool set(UEVR_UObjectHandle o,const View& v,const std::vector<Sizes>& desired){
    if(desired.size()!=static_cast<size_t>(v.array.count)||!v.array.count)return false;
    auto cls=reinterpret_cast<UEVR_UStructHandle>(host->sdk->uobject->get_class(o));
    auto fn=host->sdk->ustruct->find_function(cls,L"SetElements");if(!fn)return false;
    auto fs=reinterpret_cast<UEVR_UStructHandle>(fn);
    const int length=host->sdk->ustruct->get_properties_size(fs);
    if(length<16||length>4096)return false;
    UEVR_FPropertyHandle parameter=nullptr;
    auto f=host->sdk->ustruct->get_child_properties(fs);
    for(int i=0;f&&i<32;++i,f=host->sdk->ffield->get_next(f)){
        auto p=reinterpret_cast<UEVR_FPropertyHandle>(f);
        if(!host->sdk->fproperty->is_param(p))continue;
        if(parameter||propertyType(p)!=L"ArrayProperty"||host->sdk->fproperty->is_return_param(p))return false;
        if(!(host->sdk->fproperty->get_property_flags(p)&2ULL))return false; // const input array only
        auto inner=host->sdk->farrayproperty->get_inner(reinterpret_cast<UEVR_FArrayPropertyHandle>(p));
        if(!inner||propertyType(inner)!=L"StructProperty"||host->sdk->fstructproperty->get_struct(reinterpret_cast<UEVR_FStructPropertyHandle>(inner))!=v.structure)return false;
        parameter=p;
    }
    if(!parameter)return false;
    const int offset=host->sdk->fproperty->get_offset(parameter);if(offset<0||offset>length-16)return false;
    // Keep every material, curve, screen-space flag and other field unchanged.
    std::vector<unsigned char> entries(static_cast<size_t>(v.array.count)*static_cast<size_t>(v.stride));
    SIZE_T bytes=0;
    if(!ReadProcessMemory(GetCurrentProcess(),v.array.data,entries.data(),entries.size(),&bytes)||bytes!=entries.size())return false;
    for(size_t i=0;i<desired.size();++i){
        std::memcpy(entries.data()+i*static_cast<size_t>(v.stride)+v.x,&desired[i].x,4);
        std::memcpy(entries.data()+i*static_cast<size_t>(v.stride)+v.y,&desired[i].y,4);
    }
    std::vector<unsigned char> params(static_cast<size_t>(length));
    ArrayView input{entries.data(),v.array.count,v.array.count};
    std::memcpy(params.data()+offset,&input,sizeof(input));
    host->sdk->uobject->process_event(o,fn,params.data());
    View after;std::vector<Sizes> result;
    return view(o,after)&&sizes(after,result)&&equal(result,desired);
}
static bool nameMatches(const std::wstring& name,const std::wstring& ownerClass){
    return ownerClass==L"ChronicleTargetContainerActorBP_C"&&name.find(L".PersistentLevel.")!=std::wstring::npos&&
        name.find(L"Default__")==std::wstring::npos&&componentKind(name)!=0;
}
static bool eligible(UEVR_UObjectHandle o,const std::wstring& name){
    auto actor=host->sdk->uobject->get_outer(o);
    auto cls=actor?host->sdk->uobject->get_class(actor):nullptr;
    if(!cls||!nameMatches(name,billboardFname(host->sdk->uobject->get_fname(reinterpret_cast<UEVR_UObjectHandle>(cls)))))return false;
    View v;if(!view(o,v)||v.array.count!=1)return false;
    auto material=property(reinterpret_cast<UEVR_UStructHandle>(v.structure),L"Material");
    if(!material||propertyType(material)!=L"ObjectProperty")return false;
    const int offset=host->sdk->fproperty->get_offset(material);
    if(offset<0||offset>v.stride-static_cast<int>(sizeof(void*)))return false;
    UEVR_UObjectHandle m=nullptr;
    if(!copy(v.array.data+offset,m)||!m)return false;
    const auto materialPath=objectName(m);const auto kind=componentKind(name);
    return kind==1?materialPath.find(L".MID_M_HUD_Container_Escort_000_")!=std::wstring::npos:
        kind==2?materialPath.find(L".MID_MI_HUD_Multi_TargetPinClockwise_002_")!=std::wstring::npos:
        kind==3&&materialPath.find(L".MID_MI_HUD_Multi_TargetPinAntiClockwise_002_")!=std::wstring::npos;
}
static Saved desiredState(const std::vector<Sizes>& now,const Saved* previous,float factor=.25f){
    Saved s{now,now};
    // A new game size on one axis must not compound the unchanged scaled axis.
    if(previous&&previous->original.size()==now.size()){
        for(size_t i=0;i<now.size();++i){
            if(std::abs(now[i].x-previous->last[i].x)<=1e-7f)s.original[i].x=previous->original[i].x;
            if(std::abs(now[i].y-previous->last[i].y)<=1e-7f)s.original[i].y=previous->original[i].y;
        }
    }
    s.last=scaled(s.original,factor);return s;
}
static bool restore(const std::wstring& name,Saved& s){
    auto o=host->sdk->uobject_array->find_uobject((L"MaterialBillboardComponent "+name).c_str());
    if(!o)return true;
    View v;std::vector<Sizes> now;
    if(!view(o,v)||!sizes(v,now))return false;
    if(equal(now,s.last)&&!set(o,v,s.original)){++failures;return false;}
    return true;
}
[[maybe_unused]] static void tick(){
    if(directory.empty()){
        wchar_t p[32768]{};host->functions->get_persistent_dir(p,32768);directory=std::filesystem::path(p)/L"data";
    }
    std::error_code error;
    if(tickCount%30==0)enabled=std::filesystem::exists(directory/L"ac8_escort_draw_scale_enabled.flag",error);
    std::wstring level;
    auto pc=host->sdk->functions->get_player_controller(0);UEVR_UObjectHandle hud=nullptr;
    if(pc&&copy(host->sdk->uobject->get_property_data(pc,L"MyHUD"),hud)&&hud){auto name=objectName(hud);auto at=name.find(L".PersistentLevel.");if(at!=std::wstring::npos&&name.find(L"LiveMainHUDParent4K_C_")!=std::wstring::npos)level=name.substr(0,at+17);}
    std::set<std::wstring> seen;unsigned matches=0,pinMatches=0;
    if((enabled||pin_scale.load()!=1)&&!level.empty()){
        auto c=host->sdk->uobject_array->find_uobject(L"Class /Script/Engine.MaterialBillboardComponent");
        if(c){
            std::vector<UEVR_UObjectHandle> objects(4096);
            int count=host->sdk->uobject_hook->get_objects_by_class(reinterpret_cast<UEVR_UClassHandle>(c),objects.data(),4096,false);
            for(int i=0;i<std::min(count,4096);++i){
                auto o=objects[static_cast<size_t>(i)];if(!o)continue;
                auto name=objectName(o);if(name.compare(0,level.size(),level)!=0||!eligible(o,name))continue;
                const auto kind=componentKind(name);if(kind==1&&!enabled)continue;
                ++matches;if(kind>1){++pinMatches;}
                View v;std::vector<Sizes> now;if(!view(o,v)||!sizes(v,now)||now.empty())continue;
                seen.insert(name);
                auto it=saved.find(name);
                
                // Game-generated new sizes become the new baseline; never compound our own output.
                auto state=desiredState(now,it==saved.end()?nullptr:&it->second,kind==1?.25f:pin_scale.load());
                if(equal(now,state.last))continue;
                saved[name]=state;
                if(set(o,v,state.last))++writes;else ++failures;
            }
        }
    }
    for(auto it=saved.begin();it!=saved.end();){if(!seen.count(it->first)&&restore(it->first,it->second))it=saved.erase(it);else ++it;}

}
}
