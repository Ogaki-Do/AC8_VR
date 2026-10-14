// Fit an authored camera lens into the requested presentation window. All
// inputs are validated before producing scale factors; the caller decides when
// cinematic lens adjustment is enabled and owns synchronization.

#pragma once
#include <cmath>
#include <algorithm>
#include <mutex>
namespace cinematic_lens {
struct Lens {double fov=0,aspect=0;};
struct View {double width=0,height=0,distance=0,limit_x=0,limit_y=0;};
struct Fit {double width,height,half_x,half_y,scale_x,scale_y;};
inline bool fit(const Lens& lens,const View& view,Fit& result){
    if(!std::isfinite(lens.fov+lens.aspect+view.width+view.height+view.distance+view.limit_x+view.limit_y)||lens.fov<.25||lens.fov>170||lens.aspect<.5||lens.aspect>5||view.width<=0||view.height<=0||view.distance<=0||view.limit_x<=0||view.limit_y<=0)return false;
    result.width=std::min(view.width,view.height*lens.aspect);result.height=result.width/lens.aspect;
    result.half_x=std::min(result.width/(2*view.distance),std::min(view.limit_x,view.limit_y*lens.aspect));result.half_y=result.half_x/lens.aspect;
    const double authored_x=std::tan(lens.fov*3.14159265358979323846/360),authored_y=authored_x/lens.aspect;
    result.scale_x=result.half_x/authored_x;result.scale_y=result.half_y/authored_y;
    return std::isfinite(result.scale_x+result.scale_y)&&result.scale_x>0&&result.scale_y>0;
}
template<typename T> bool apply(T (&matrix)[4][4],const Fit& fit){
    // Keep native principal point, depth convention and crop/grow compensation.
    // The movie crop's angular extent maps to the authored camera's lens extent.
    if(!std::isfinite(matrix[0][0]+matrix[1][1])||matrix[0][0]<=0||matrix[1][1]<=0)return false;
    matrix[0][0]=static_cast<T>(matrix[0][0]*fit.scale_x);matrix[1][1]=static_cast<T>(matrix[1][1]*fit.scale_y);return true;
}
inline std::mutex mutex;
inline Lens lens{};
inline View view{};
inline bool requested=false;
inline bool current(Fit& out){std::lock_guard<std::mutex> guard(mutex);return requested&&fit(lens,view,out);}
}
