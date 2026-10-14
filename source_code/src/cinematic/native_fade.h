// Read opacity from the verified native fade widget selected by Lua. The
// source address is a short-lived runtime reference, never a file identifier.
// Build, vtable and bounds checks prevent interpreting unrelated widget memory.

#pragma once
#include <atomic>
#include <array>
#include <cmath>
namespace native_fade {
inline uintptr_t gameBase=0;
inline bool ready=false;
inline std::atomic<uintptr_t> source{0};
inline std::atomic<float> multiplier{1};
constexpr uintptr_t widgetVtable=0xc6ee7d8;
template<class T>inline bool read(const void* p,T& value){SIZE_T size=0;return p&&ReadProcessMemory(GetCurrentProcess(),p,&value,sizeof(value),&size)&&size==sizeof(value);}
inline bool opacity(float& result){
 const auto widget=source.load();if(!ready||!widget)return false;
 uintptr_t table=0,slate=0,child=0;float alpha=0;
 if(!read(reinterpret_cast<void*>(widget),table)||table!=gameBase+widgetVtable||
  !read(reinterpret_cast<void*>(widget+0x310),slate)||!slate||
  !read(reinterpret_cast<void*>(slate+0x288),child)||!child||
  !read(reinterpret_cast<void*>(child+0x1cc),alpha)||!std::isfinite(alpha)||alpha<0||alpha>1)return false;
 result=alpha*multiplier.load();return std::isfinite(result)&&result>=0&&result<=1;
}
inline void control(const char* event,const char* data){
 if(!event||std::strcmp(event,"AC8_NativeFadeSource")||!data)return;
 uintptr_t widget=0;float value=0;char trailing=0;
 if(sscanf_s(data,"%llu|%f%c",&widget,&value,&trailing,1u)!=2||!std::isfinite(value)||value<0||value>1)return;
 multiplier=value;source=widget;
}
inline void initialize(){
 gameBase=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
 // Generated signatures verify the native SetFadeOpacity implementation and
 // the source-to-Slate binding before reading their fixed field offsets.
 const std::array<unsigned char,32> opacityHead={{0x48,0x8b,0x89,0x10,0x3,0x0,0x0,0x48,0x85,0xc9,0x74,0x28,0x48,0x8b,0x89,0x88,0x2,0x0,0x0,0x48,0x85,0xc9,0x74,0x1c,0xf3,0xf,0x10,0x2,0xf,0x2e,0x81,0xcc}};
 const std::array<unsigned char,32> bindingHead={{0x48,0x89,0x5c,0x24,0x8,0x57,0x48,0x83,0xec,0x20,0x80,0x3d,0x37,0xca,0x9d,0x6,0x0,0x48,0x8b,0xda,0x48,0x8b,0xf9,0x74,0xd,0x48,0x85,0xd2,0x74,0x8,0x48,0x8b}};
 std::array<unsigned char,32> a{},b{};
 ready=read(reinterpret_cast<void*>(gameBase+0x7a55010),a)&&a==opacityHead&&read(reinterpret_cast<void*>(gameBase+0x7a54fa0),b)&&b==bindingHead;
}
}
