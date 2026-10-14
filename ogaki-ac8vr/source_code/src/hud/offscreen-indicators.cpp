// Apply independent position controls and a shared scale to native locator
// geometry. Each hook records the start of its own emitted vertices and changes
// only that range, keeping other HUD draws and the two locator centers separate.

// Two scoped native draw hooks share one scale control. Each transforms only
// its newly emitted locator geometry; their independently placed centers stay put.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include "../../vendor/uevr/plugin-api.h"
#include "../backend/backend_boundary.h"

namespace target_arrow {
struct Point {double x,y;};
struct Array {unsigned char* data;int32_t count,capacity;};
struct Margin {float left,top,right,bottom;};
static_assert(sizeof(Point)==16 && sizeof(Array)==16 && sizeof(Margin)==16);
using Draw=void(*)(UEVR_UObjectHandle,UEVR_UObjectHandle);
static const UEVR_PluginInitializeParam* host=nullptr;
static Draw original=nullptr,originalForward=nullptr;
static std::atomic<bool> enabled{true};
static std::atomic<double> offsetX{0},offsetY{-950},scale{.5};
static std::atomic<uint64_t> calls{0},eligible{0},shifted{0},pointsMoved{0},textMoved{0},rejected{0};
static std::atomic<uint64_t> forwardCalls{0},forwardEligible{0},forwardScaled{0},forwardPoints{0},forwardTexts{0},forwardRejected{0};
static bool attempted=false,installed=false;
static std::atomic<bool> layoutVerified{false};
static std::atomic<bool> fontLayoutVerified{false};
static int fontBytes=0;
static unsigned ticks=0;
static UEVR_UClassHandle locatorClass=nullptr,canvasClass=nullptr,slotClass=nullptr,textClass=nullptr;
static UEVR_UFunctionHandle setPosition=nullptr,setFont=nullptr;
static std::filesystem::path directory;
static std::filesystem::file_time_type controlsStamp{};
static std::string reason="waiting for initialization";
constexpr uintptr_t bodyRva=119793440,forwardRva=119797200,lineRva=120045712,textRva=119818592,slotRva=119820912;
constexpr unsigned char bodyHead[]={0x40,0x55,0x57,0x41,0x57,0x48,0x8d,0xac,0x24,0xb0,0xfd,0xff,0xff,0x48,0x81,0xec,0x50,0x03,0x00,0x00};
constexpr unsigned char forwardHead[]={0x40,0x55,0x57,0x41,0x56,0x48,0x8d,0xac,0x24,0x40,0xff,0xff,0xff,0x48,0x81,0xec,0xc0,0x01,0x00,0x00};
constexpr unsigned char lineHead[]={0x48,0x8b,0xc4,0x53,0x57,0x48,0x81,0xec,0xa8,0x00,0x00,0x00};
constexpr unsigned char textHead[]={0x48,0x8b,0xc4,0x4c,0x89,0x48,0x20,0x4c,0x89,0x40,0x18,0x55,0x41,0x56,0x41,0x57};
constexpr unsigned char slotHead[]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18};

template<class T> static bool read(const void* p,T& value) {
    SIZE_T n=0;return p && ReadProcessMemory(GetCurrentProcess(),p,&value,sizeof(value),&n) && n==sizeof(value);
}
static unsigned char* bytes(void* p) {return static_cast<unsigned char*>(p);}
static bool validArray(const Array& a) {
    return a.count>=0 && a.count<=8192 && a.capacity>=a.count && a.capacity<=65536 && (!a.count||a.data);
}
static bool addedRange(int before,int after,int capacity,int maxAdded) {
    return before>=0 && after>=before && after<=capacity && after-before<=maxAdded;
}
static bool shiftedPoint(const Point& input,Point delta,Point& output) {
    if(!std::isfinite(input.x)||!std::isfinite(input.y)||!std::isfinite(delta.x)||!std::isfinite(delta.y)||
       std::abs(input.x)>50000 || std::abs(input.y)>50000 || std::abs(delta.x)>5000 || std::abs(delta.y)>5000)return false;
    output={input.x+delta.x,input.y+delta.y};return std::abs(output.x)<=55000 && std::abs(output.y)<=55000;
}
static bool scaledPoint(Point input,Point pivot,double factor,Point delta,Point& output) {
    if(factor==1)return shiftedPoint(input,delta,output);
    Point checked{};
    if(!std::isfinite(factor)||factor<.1||factor>4 ||
       !shiftedPoint(input,{},checked)||!shiftedPoint(pivot,{},checked))return false;
    return shiftedPoint({pivot.x+(input.x-pivot.x)*factor,pivot.y+(input.y-pivot.y)*factor},delta,output);
}
static bool number(const std::string& text,const char* key,double& value) {
    const auto p=text.find(std::string("\"")+key+"\"");if(p==std::string::npos)return false;
    const auto colon=text.find(':',p);if(colon==std::string::npos)return false;
    const char* begin=text.c_str()+colon+1;char* end=nullptr;value=std::strtod(begin,&end);
    return end!=begin && std::isfinite(value) && std::abs(value)<=5000;
}
static bool parseControls(const std::string& text,bool& on,Point& delta,double& factor) {
    if(text.size()>1024 || !number(text,"offsetX",delta.x)||!number(text,"offsetY",delta.y))return false;
    factor=1;
    if(text.find("\"scale\"")!=std::string::npos && (!number(text,"scale",factor)||factor<.1||factor>4))return false;
    auto p=text.find("\"enabled\"");if(p==std::string::npos)return false;
    p=text.find(':',p);if(p==std::string::npos)return false;
    p=text.find_first_not_of(" \t\r\n",p+1);if(p==std::string::npos)return false;
    if(text.compare(p,4,"true")==0)on=true;else if(text.compare(p,5,"false")==0)on=false;else return false;
    return true;
}
static std::wstring fname(UEVR_FNameHandle n) {
    wchar_t b[256]{};if(n)host->sdk->fname->to_string(n,b,256);return b;
}
static std::wstring propertyType(UEVR_FPropertyHandle p) {
    auto c=host->sdk->ffield->get_class(reinterpret_cast<UEVR_FFieldHandle>(p));
    return c?fname(host->sdk->ffield_class->get_fname(c)):L"";
}
static bool namedOffset(UEVR_UStructHandle cls,const wchar_t* name,const wchar_t* type,int offset) {
    auto p=host->sdk->ustruct->find_property(cls,name);
    return p && propertyType(p)==type && host->sdk->fproperty->get_offset(p)==offset;
}
static bool bindFontLayout() {
    const auto text=reinterpret_cast<UEVR_UStructHandle>(textClass);
    if(!text || !namedOffset(text,L"Font",L"StructProperty",488))return false;
    const auto fontProperty=host->sdk->ustruct->find_property(text,L"Font");
    const auto fontStruct=host->sdk->fstructproperty->get_struct(reinterpret_cast<UEVR_FStructPropertyHandle>(fontProperty));
    if(!fontStruct)return false;
    const auto size=host->sdk->uscriptstruct->get_struct_size(fontStruct);
    if(size<76 || size>256 ||
       !namedOffset(reinterpret_cast<UEVR_UStructHandle>(fontStruct),L"Size",L"FloatProperty",72))return false;
    setFont=host->sdk->ustruct->find_function(text,L"SetFont");
    if(!setFont || host->sdk->ustruct->get_properties_size(reinterpret_cast<UEVR_UStructHandle>(setFont))!=size)return false;
    const auto fontFirst=host->sdk->ustruct->get_child_properties(reinterpret_cast<UEVR_UStructHandle>(setFont));
    const auto fontParam=reinterpret_cast<UEVR_FPropertyHandle>(fontFirst);
    if(!fontParam || propertyType(fontParam)!=L"StructProperty" || !host->sdk->fproperty->is_param(fontParam) ||
       host->sdk->fproperty->is_return_param(fontParam) || host->sdk->fproperty->get_offset(fontParam)!=0 ||
       host->sdk->ffield->get_next(fontFirst) ||
       host->sdk->fstructproperty->get_struct(reinterpret_cast<UEVR_FStructPropertyHandle>(fontParam))!=fontStruct)return false;
    fontBytes=size;return true;
}
static bool bindLayout() {
    auto find=host->sdk->uobject_array->find_uobject;
    locatorClass=reinterpret_cast<UEVR_UClassHandle>(find(L"Class /Script/Live.LiveLocatorWidget"));
    canvasClass=reinterpret_cast<UEVR_UClassHandle>(find(L"Class /Script/Live.LiveDynamicDrawCanvas"));
    slotClass=reinterpret_cast<UEVR_UClassHandle>(find(L"Class /Script/UMG.CanvasPanelSlot"));
    textClass=reinterpret_cast<UEVR_UClassHandle>(find(L"Class /Script/UMG.TextBlock"));
    if(!locatorClass || !canvasClass || !slotClass || !textClass)return false;
    const auto canvas=reinterpret_cast<UEVR_UStructHandle>(canvasClass);
    const auto locator=reinterpret_cast<UEVR_UStructHandle>(locatorClass);
    const auto slot=reinterpret_cast<UEVR_UStructHandle>(slotClass);
    if(!namedOffset(canvas,L"TextSlots",L"ArrayProperty",0x1b8) ||
       !namedOffset(canvas,L"LowestPriorityTextSlots",L"ArrayProperty",0x228) ||
       !namedOffset(locator,L"FowardLocatorOffset",L"StructProperty",0x3c8) ||
       !namedOffset(slot,L"LayoutData",L"StructProperty",56) ||
       !namedOffset(slot,L"Content",L"ObjectProperty",48))return false;
    setPosition=host->sdk->ustruct->find_function(slot,L"SetPosition");
    if(!setPosition || host->sdk->ustruct->get_properties_size(reinterpret_cast<UEVR_UStructHandle>(setPosition))!=16)return false;
    const auto first=host->sdk->ustruct->get_child_properties(reinterpret_cast<UEVR_UStructHandle>(setPosition));
    const auto p=reinterpret_cast<UEVR_FPropertyHandle>(first);
    if(!p || propertyType(p)!=L"StructProperty" || !host->sdk->fproperty->is_param(p) ||
       host->sdk->fproperty->is_return_param(p) || host->sdk->fproperty->get_offset(p)!=0 || host->sdk->ffield->get_next(first))return false;
    const auto vec=host->sdk->fstructproperty->get_struct(reinterpret_cast<UEVR_FStructPropertyHandle>(p));
    return vec && host->sdk->uscriptstruct->get_struct_size(vec)==16 &&
           namedOffset(reinterpret_cast<UEVR_UStructHandle>(vec),L"X",L"DoubleProperty",0) &&
           namedOffset(reinterpret_cast<UEVR_UStructHandle>(vec),L"Y",L"DoubleProperty",8);
}
struct Before {void* renderer=nullptr;int points=0,normal=0,low=0;};
static bool snapshot(UEVR_UObjectHandle canvas,Before& before) {
    Array points{};
    return read(bytes(canvas)+0x190,before.renderer) && before.renderer &&
        read(bytes(before.renderer)+0x228,points) && validArray(points) &&
        (before.points=points.count,true) && read(bytes(canvas)+0x1c8,before.normal) &&
        read(bytes(canvas)+0x238,before.low) && before.normal>=0 && before.low>=0 && before.normal<=2048 && before.low<=2048;
}
struct TextChange {
    UEVR_UObjectHandle slot=nullptr,content=nullptr;Point original{},position{};
    std::array<unsigned char,256> font{};float fontSize=0;
};
static bool readFont(UEVR_UObjectHandle content,std::array<unsigned char,256>& font) {
    SIZE_T copied=0;const auto p=host->sdk->uobject->get_property_data(content,L"Font");
    return p && fontBytes>=76 && fontBytes<=256 &&
        ReadProcessMemory(GetCurrentProcess(),p,font.data(),static_cast<SIZE_T>(fontBytes),&copied) &&
        copied==static_cast<SIZE_T>(fontBytes);
}
static bool gatherText(UEVR_UObjectHandle canvas,int before,int cursorOffset,int poolOffset,Point delta,double factor,
                       std::array<TextChange,16>& changes,int& count) {
    int after=0;Array pool{};
    if(!read(bytes(canvas)+cursorOffset,after)||!read(bytes(canvas)+poolOffset,pool)||!validArray(pool)||
       !addedRange(before,after,pool.count,16-count))return false;
    for(int i=before;i<after;++i) {
        auto& c=changes[static_cast<size_t>(count)];Margin margin{};UEVR_UObjectHandle parent=nullptr;
        if(!read(pool.data+static_cast<size_t>(i)*8,c.slot)||!c.slot||!host->sdk->uobject->is_a(c.slot,slotClass)||
           !read(host->sdk->uobject->get_property_data(c.slot,L"Parent"),parent)||parent!=canvas||
           !read(host->sdk->uobject->get_property_data(c.slot,L"LayoutData"),margin))return false;
        c.original={margin.left,margin.top};
        if(!shiftedPoint(c.original,delta,c.position))return false;
        if(factor!=1) {
            if(!read(host->sdk->uobject->get_property_data(c.slot,L"Content"),c.content)||!c.content ||
               !host->sdk->uobject->is_a(c.content,textClass) ||
               !readFont(c.content,c.font))return false;
            float originalSize=0;std::memcpy(&originalSize,c.font.data()+72,sizeof(originalSize));
            if(!std::isfinite(originalSize)||originalSize<1||originalSize>512)return false;
            c.fontSize=static_cast<float>(originalSize*factor);
            std::memcpy(c.font.data()+72,&c.fontSize,sizeof(c.fontSize));
        }
        ++count;
    }
    return true;
}
// All validation precedes modification. Only the newly appended range is
// touched. Each locator scales about its own center; earlier draws stay intact.
static bool shiftEmitted(UEVR_UObjectHandle canvas,const Before& before,Point delta,double factor=1,bool forward=false) {
    void* renderer=nullptr;Array points{};std::array<Point,512> moved{};std::array<TextChange,16> texts{};int textCount=0;
    if(!read(bytes(canvas)+0x190,renderer)||renderer!=before.renderer ||
       !read(bytes(renderer)+0x228,points)||!validArray(points)||!addedRange(before.points,points.count,points.capacity,512) ||
       !std::isfinite(factor)||factor<.1||factor>4 ||
       !gatherText(canvas,before.normal,0x1c8,0x1b8,delta,factor,texts,textCount) ||
       !gatherText(canvas,before.low,0x238,0x228,delta,factor,texts,textCount))return false;
    const int count=points.count-before.points;
    Point minimum{50000,50000},maximum{-50000,-50000};
    for(int i=0;i<count;++i) {
        Point value{};
        if(!read(points.data+static_cast<size_t>(before.points+i)*16,value)||!shiftedPoint(value,{},moved[static_cast<size_t>(i)]))return false;
        minimum.x=std::min(minimum.x,value.x);minimum.y=std::min(minimum.y,value.y);
        maximum.x=std::max(maximum.x,value.x);maximum.y=std::max(maximum.y,value.y);
    }
    if(!count && !textCount)return true;
    if(!count && factor!=1)return false; // No proven arrow pivot for a text-only batch.
    const Point pivot=count?Point{(minimum.x+maximum.x)*.5,(minimum.y+maximum.y)*.5}:Point{};
    for(int i=0;i<count;++i) {
        auto& p=moved[static_cast<size_t>(i)];if(!scaledPoint(p,pivot,factor,delta,p))return false;
    }
    for(int i=0;i<textCount;++i) {
        auto& c=texts[static_cast<size_t>(i)];if(!scaledPoint(c.original,pivot,factor,delta,c.position))return false;
    }
    if(count) {
        SIZE_T written=0;const auto size=static_cast<SIZE_T>(count)*sizeof(Point);
        if(!WriteProcessMemory(GetCurrentProcess(),points.data+static_cast<size_t>(before.points)*16,moved.data(),size,&written)||written!=size)return false;
    }
    for(int i=0;i<textCount;++i) {
        auto& c=texts[static_cast<size_t>(i)];
        if(factor!=1) {
            // Native locator-text resets Font on every draw (original +0x4BE..0x4F1).
            // Scale the fresh font rather than leaving a transform on pooled widgets.
            host->sdk->uobject->process_event(c.content,setFont,c.font.data());
            std::array<unsigned char,256> font{};float resultSize=0;
            if(!readFont(c.content,font)) {
                enabled=false;reason="font setter readback unreadable; disabled until next test";return false;
            }
            std::memcpy(&resultSize,font.data()+72,sizeof(resultSize));
            if(!std::isfinite(resultSize)||std::abs(resultSize-c.fontSize)>.01) {
                enabled=false;reason="font setter readback failed; disabled until next test";return false;
            }
        }
        host->sdk->uobject->process_event(c.slot,setPosition,&c.position);
        Margin result{};
        if(!read(host->sdk->uobject->get_property_data(c.slot,L"LayoutData"),result)||
           std::abs(result.left-c.position.x)>.05 || std::abs(result.top-c.position.y)>.05) {
            enabled=false;reason="text setter readback failed; disabled until next test";return false;
        }
    }
    if(forward){++forwardScaled;forwardPoints+=static_cast<uint64_t>(count);forwardTexts+=static_cast<uint64_t>(textCount);}
    else{++shifted;pointsMoved+=static_cast<uint64_t>(count);textMoved+=static_cast<uint64_t>(textCount);}
    return true;
}
static void wrapper(UEVR_UObjectHandle widget,UEVR_UObjectHandle canvas) {
    ++calls;
    const auto fn=original;if(!fn)return;
    Before before{};unsigned char mode=255;
    const bool active=enabled.load() && layoutVerified && widget && canvas &&
        host->sdk->uobject->is_a(widget,locatorClass) && host->sdk->uobject->is_a(canvas,canvasClass) &&
        read(bytes(widget)+0x618,mode) && mode==0 && snapshot(canvas,before);
    const Point delta{offsetX.load(),offsetY.load()};
    const double factor=fontLayoutVerified?scale.load():1;
    fn(widget,canvas);
    if(!active)return;
    ++eligible;
    if(!shiftEmitted(canvas,before,delta,factor))++rejected;
}
static void forwardWrapper(UEVR_UObjectHandle widget,UEVR_UObjectHandle canvas) {
    ++forwardCalls;const auto fn=originalForward;if(!fn)return;
    Before before{};unsigned char mode=255;
    const bool active=enabled.load() && layoutVerified && widget && canvas &&
        host->sdk->uobject->is_a(widget,locatorClass) && host->sdk->uobject->is_a(canvas,canvasClass) &&
        read(bytes(widget)+0x618,mode) && mode==0 && snapshot(canvas,before);
    const double factor=fontLayoutVerified?scale.load():1;
    fn(widget,canvas);
    if(!active || factor==1)return;
    ++forwardEligible;
    // The forward body's existing FowardLocatorOffset already places it.
    // Apply the shared scale only; never add the target's translation here.
    if(!shiftEmitted(canvas,before,{},factor,true))++forwardRejected;
}
template<size_t N> static bool codeMatches(const unsigned char* p,const unsigned char(&expected)[N]) {
    std::array<unsigned char,N> actual{};SIZE_T n=0;
    return ReadProcessMemory(GetCurrentProcess(),p,actual.data(),N,&n) && n==N && std::memcmp(actual.data(),expected,N)==0;
}
static void install() {
    attempted=true;wchar_t path[32768]{};std::string hash;auto module=GetModuleHandleW(nullptr);
    if(!module || !GetModuleFileNameW(module,path,32768)||!boundary::file_hash(path,hash)||
       hash!="51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F") {
        reason="game executable guard failed; no hook installed";return;
    }
    auto base=reinterpret_cast<unsigned char*>(module);
    if(!codeMatches(base+bodyRva,bodyHead)||!codeMatches(base+forwardRva,forwardHead)||
       !codeMatches(base+lineRva,lineHead)||!codeMatches(base+textRva,textHead)||!codeMatches(base+slotRva,slotHead)) {
        reason="native drawing code guard failed; no hook installed";return;
    }
    const int targetHook=host->functions->register_inline_hook(base+bodyRva,reinterpret_cast<void*>(&wrapper),reinterpret_cast<void**>(&original));
    const int forwardHook=host->functions->register_inline_hook(base+forwardRva,reinterpret_cast<void*>(&forwardWrapper),reinterpret_cast<void**>(&originalForward));
    installed=targetHook>=0 && original && forwardHook>=0 && originalForward;
    if(!installed) {
        if(targetHook>=0)host->functions->unregister_inline_hook(targetHook);
        if(forwardHook>=0)host->functions->unregister_inline_hook(forwardHook);
        original=nullptr;originalForward=nullptr;
    }
    reason=installed?"both locator hooks installed; waiting for reflected layout validation":"paired hook registration failed; both removed";
}
static void controls() {
    std::error_code ec;const auto path=directory/L"ac8_target_arrow_shift_controls.json";
    const auto stamp=std::filesystem::last_write_time(path,ec);if(ec || stamp==controlsStamp)return;
    std::ifstream file(path);std::string text((std::istreambuf_iterator<char>(file)),{});bool on=false;Point delta{};double factor=1;
    if(parseControls(text,on,delta,factor)){enabled=on;offsetX=delta.x;offsetY=delta.y;scale=factor;controlsStamp=stamp;}
}

static void tick(UEVR_UGameEngineHandle,float) {
    ++ticks;
    if(directory.empty()){wchar_t p[32768]{};host->functions->get_persistent_dir(p,32768);directory=std::filesystem::path(p)/L"data";controls();}
    if(!attempted)install();
    if(installed && !layoutVerified && (ticks==1 || ticks%60==0)) {
        layoutVerified=bindLayout();if(layoutVerified)reason="target shift active; checking font schema for paired scale";
    }
    if(layoutVerified && !fontLayoutVerified && (ticks==1 || ticks%60==0)) {
        fontLayoutVerified=bindFontLayout();if(fontLayoutVerified)reason="target/forward locators share scale; separate positions preserved";
    }
    if(ticks==1 || ticks%60==0){controls();}
}
} // namespace target_arrow
extern "C"  void uevr_plugin_required_version(UEVR_PluginVersion* v) {
    v->major=UEVR_PLUGIN_VERSION_MAJOR;v->minor=UEVR_PLUGIN_VERSION_MINOR;v->patch=UEVR_PLUGIN_VERSION_PATCH;
}
extern "C"  bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* p) {
    if(!p||!p->version||p->version->major!=UEVR_PLUGIN_VERSION_MAJOR||p->version->minor<UEVR_PLUGIN_VERSION_MINOR||
       !p->functions||!p->functions->get_persistent_dir||!p->functions->register_inline_hook||!p->functions->unregister_inline_hook||!p->sdk)return false;
    const auto s=p->sdk;
    if(!s->uobject||!s->uobject_array||!s->fname||!s->ustruct||!s->ffield||!s->ffield_class||!s->fproperty||
       !s->fstructproperty||!s->uscriptstruct||!s->callbacks||!s->callbacks->on_post_engine_tick)return false;
    target_arrow::host=p;return s->callbacks->on_post_engine_tick(target_arrow::tick);
}
