// Apply an optional cinematic lens fit at the verified projection boundary.
// UEVR precision and the active presentation mode gate the change. The bomb
// helpers remain separately scoped and must not inherit cinematic lens state.

#pragma once
#include "lens_projection.h"
#include "bomb_projection.h"
#include "bomb_circle.h"
namespace cinematic_projection {
using Function=void*(*)(void*,void*,int);
inline std::atomic<Function> original{nullptr};
inline std::atomic<bool> installed{false},allowed{false};
inline std::atomic<unsigned long long> writes{0};
inline std::atomic<const char*> state{"not_observed"};
inline std::mutex install_mutex;
inline thread_local bool double_precision=false;
inline void* wrapper(void* device,void* output,int index){
    const auto fn=original.load();if(!fn)return output;
    auto* result=fn(device,output,index);cinematic_lens::Fit fit{};
    if(result==output&&result&&double_precision&&cinematic_camera::enabled&&cinema_mask::requested&&cinematic_lens::current(fit)){
        auto& matrix=*reinterpret_cast<UEVR_Matrix4x4d*>(result);
        if(cinematic_lens::apply(matrix.m,fit))++writes;}
    return result;
}
inline void verify(){
    wchar_t path[32768]{};std::string hash;
    const auto game=GetModuleHandleW(nullptr);
    allowed=game&&GetModuleFileNameW(game,path,32768)&&boundary::file_hash(path,hash)&&hash=="51510E2A520565DBE81FB0D569E95CD4393077ACAAA859371489B80B8128829F";
    state=allowed?"waiting_stereo_vtable":"unsupported_game";
}
// Recorded live UEVR log: projection slot12, game RVA04BBF060, UE5 double ABI.
// Change one pointer, forward through the existing UEVR hook, adjust AFTER it returns.
inline bool attach_guarded(void* device){
    __try {
        auto** table=*reinterpret_cast<void***>(device);auto** slot=table+12;
        auto* expected=reinterpret_cast<unsigned char*>(GetModuleHandleW(nullptr))+0x04bbf060;
        if(*slot!=expected)return false;
        DWORD protection=0;if(!VirtualProtect(slot,sizeof(void*),PAGE_READWRITE,&protection))return false;
        original=reinterpret_cast<Function>(expected);
        const auto previous=InterlockedCompareExchangePointer(slot,reinterpret_cast<void*>(&wrapper),expected);
        DWORD ignored=0;VirtualProtect(slot,sizeof(void*),protection,&ignored);
        if(previous!=expected){original=nullptr;return false;}
        return true;
    }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
inline void early(UEVR_StereoRenderingDeviceHandle device,int,float,UEVR_Vector3f*,UEVR_Rotatorf*,bool precision){
    double_precision=precision;
    if(!allowed||installed||!precision||!device)return;
    std::lock_guard<std::mutex> guard(install_mutex);if(installed)return;
    HMODULE pinned=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&wrapper),&pinned);
    if(!pinned)return;
    installed=attach_guarded(device);state=installed?"projection_slot_installed":"projection_slot_mismatch";
}
inline void control(const char* name,const char* data){
    if(!name||!data)return;
    std::lock_guard<std::mutex> guard(cinematic_lens::mutex);
    if(std::strcmp(name,"AC8_CinematicLensMode")==0)cinematic_lens::requested=std::strcmp(data,"on")==0;
    if(std::strcmp(name,"AC8_CinematicLens")==0){char* end=nullptr;const double fov=std::strtod(data,&end);
        if(end&&*end=='|'){const double aspect=std::strtod(end+1,nullptr);if(std::isfinite(fov+aspect)&&fov>=.25&&fov<=170&&aspect>=.5&&aspect<=5)cinematic_lens::lens={fov,aspect};}}
}
}
