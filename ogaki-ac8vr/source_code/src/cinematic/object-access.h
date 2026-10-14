// Small reflected-object helpers shared by native pause ownership discovery.
// Raw reads are bounded copies; callers must establish object identity/lifetime
// before invoking SDK reflection. This file performs no writes or enumeration.

#pragma once
#include <string>
namespace object_access {
using Object=UEVR_UObjectHandle;
inline const UEVR_PluginInitializeParam* host=nullptr;
template<class T> inline bool read(const void* p,T& v){SIZE_T n=0;return p&&ReadProcessMemory(GetCurrentProcess(),p,&v,sizeof(v),&n)&&n==sizeof(v);}
inline std::wstring fname(UEVR_FNameHandle n){wchar_t b[1024]{};if(n)host->sdk->fname->to_string(n,b,1024);return b;}
inline std::wstring path(Object o){
    if(!o)return {};std::wstring result=fname(host->sdk->uobject->get_fname(o));
    for(unsigned depth=0;o&&depth<24;++depth){auto outer=host->sdk->uobject->get_outer(o);if(!outer||outer==o)break;result=fname(host->sdk->uobject->get_fname(outer))+L"."+result;o=outer;}return result;
}
inline void* property(Object o,const wchar_t* n){return o?host->sdk->uobject->get_property_data(o,n):nullptr;}
inline Object reference(Object o,const wchar_t* n){Object p=nullptr;read(property(o,n),p);return p;}
inline std::wstring type(UEVR_FPropertyHandle p){auto c=host->sdk->ffield->get_class(reinterpret_cast<UEVR_FFieldHandle>(p));return c?fname(host->sdk->ffield_class->get_fname(c)):L"";}
}
