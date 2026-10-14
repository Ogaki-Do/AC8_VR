// Correct the landing circle only inside the verified bomb draw. The cached
// view/lens matrices otherwise disagree with the trajectory projection in VR.
// Every temporary matrix change must be restored before returning to the game.

#pragma once
#include <algorithm>
// The circle's cached camera vectors affect its 3D ellipse construction; a
// dashed line simply projects its endpoints. Substitute only these cached
// vectors during a current-bomb circle draw; keep prediction and ground normal.
namespace bomb_circle {
using Object=UEVR_UObjectHandle;
struct Vec{double x=0,y=0,z=0;};
struct Rotation{double pitch=0,yaw=0,roll=0;};
struct Camera{Vec up,right,forward,position;};
using Draw=void(*)(Object,const Vec*,const Vec*,float,const void*,int,const void*);
inline Draw original=nullptr;
inline const UEVR_PluginInitializeParam* host=nullptr;
inline bool installed=false;
constexpr uintptr_t circleRva=0x7245e90,cacheOffset=0x468;
constexpr std::array<unsigned char,32> prologue{{0x48,0x8b,0xc4,0x48,0x89,0x58,0x10,0x48,0x89,0x78,0x20,0x4c,0x89,0x40,0x18,0x55,0x48,0x8d,0x68,0xb8,0x48,0x81,0xec,0x40,0x01,0x00,0x00,0x0f,0x29,0x70,0xe8,0x0f}};
inline bool finite(Vec v){return std::isfinite(v.x+v.y+v.z)&&std::max({std::abs(v.x),std::abs(v.y),std::abs(v.z)})<1e12;}
inline bool unit(Vec v){return finite(v)&&std::abs(v.x*v.x+v.y*v.y+v.z*v.z-1)<.01;}
inline bool valid(Camera c){return unit(c.up)&&unit(c.right)&&unit(c.forward)&&finite(c.position);}
inline bool makeCamera(Vec p,Rotation r,Camera& c){
 if(!finite(p)||!std::isfinite(r.pitch+r.yaw+r.roll))return false;
 constexpr double d=3.14159265358979323846/180;
 const double sp=std::sin(r.pitch*d),cp=std::cos(r.pitch*d),sy=std::sin(r.yaw*d),cy=std::cos(r.yaw*d),sr=std::sin(r.roll*d),cr=std::cos(r.roll*d);
 c={{-cr*sp*cy-sr*sy,cy*sr-cr*sp*sy,cr*cp},{sr*sp*cy-cr*sy,sr*sp*sy+cr*cy,-sr*cp},{cp*cy,cp*sy,sp},p};return valid(c);
}
inline thread_local Object activeCanvas=nullptr;
// The cached view is the post-head left eye and
// cached lens is 108deg, while trajectory projection uses the native cache
// basis and game FOV (77.819deg in that capture). Repair these actual matrices
// only during the native circle; retain native conic geometry and rendering.
struct Matrices {std::array<double,16> view{},lens{};};
#ifdef AC8_BOMB_PROJECTION_FIXTURE
using Observe=void(*)(Object,const Vec*,const Vec*,float,int,bool);
inline Observe observer=nullptr;
inline std::atomic<uint64_t> matrixWrites=0,matrixRejected=0;
#endif
inline bool finite(const std::array<double,16>& m){for(double v:m)if(!std::isfinite(v)||std::abs(v)>1e12)return false;return true;}
inline double dot(Vec a,Vec b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline bool buildMatrices(const Camera& c,const Matrices& saved,double fov,double aspect,Matrices& out){
 if(!valid(c)||!finite(saved.view)||!finite(saved.lens)||!bomb_projection::validLens(fov,aspect)||
  std::abs(dot(c.right,c.up))>.01||std::abs(dot(c.right,c.forward))>.01||std::abs(dot(c.up,c.forward))>.01||
  std::abs(saved.view[15]-1)>.01||saved.lens[0]<=0||saved.lens[5]<=0||std::abs(saved.lens[11]-1)>.01||std::abs(saved.lens[15])>.01)return false;
 out.view={c.right.x,c.up.x,c.forward.x,0,c.right.y,c.up.y,c.forward.y,0,c.right.z,c.up.z,c.forward.z,0,
  -dot(c.position,c.right),-dot(c.position,c.up),-dot(c.position,c.forward),1};
 out.lens=saved.lens;const double x=1/std::tan(fov*3.14159265358979323846/360);
 out.lens[0]=x;out.lens[5]=x*aspect;out.lens[8]=out.lens[9]=0;
 return finite(out.view)&&finite(out.lens);
}
inline void scopedMatrices(Object canvas,const Vec* center,const Vec* normal,float radius,const void* style,int segments,const void* color,double fov,double aspect){
 auto invoke=[&](){
#ifdef AC8_BOMB_PROJECTION_FIXTURE
 if(observer)observer(canvas,center,normal,radius,segments,true);
#endif
 if(original)original(canvas,center,normal,radius,style,segments,color);
#ifdef AC8_BOMB_PROJECTION_FIXTURE
 if(observer)observer(canvas,center,normal,radius,segments,false);
#endif
 };
 auto* bytes=reinterpret_cast<unsigned char*>(canvas);Matrices saved{},desired{};Camera native{};
 if(!canvas||!center||!normal||!std::isfinite(radius)||radius<=0||!bomb_projection::validLens(fov,aspect)||
  !bomb_projection::read(bytes+cacheOffset,native)||!bomb_projection::read(bytes+0x2d0,saved.view)||!bomb_projection::read(bytes+0x350,saved.lens)||
  !buildMatrices(native,saved,bomb_projection::scope.active?bomb_projection::currentFov():fov,aspect,desired)){
  #ifdef AC8_BOMB_PROJECTION_FIXTURE
 ++matrixRejected;
#endif
 invoke();return;
 }
 struct Restore{unsigned char* bytes;Matrices saved;~Restore(){std::memcpy(bytes+0x2d0,saved.view.data(),128);std::memcpy(bytes+0x350,saved.lens.data(),128);}}restore{bytes,saved};
 std::memcpy(bytes+0x2d0,desired.view.data(),128);std::memcpy(bytes+0x350,desired.lens.data(),128);
#ifdef AC8_BOMB_PROJECTION_FIXTURE
 ++matrixWrites;
#endif
 invoke();
}
inline void wrapper(Object canvas,const Vec* center,const Vec* normal,float radius,const void* style,int segments,const void* color){
 const bool eligible=bomb_projection::scope.active&&canvas==bomb_projection::scopedCanvas;
 if(eligible){const auto prior=activeCanvas;activeCanvas=canvas;struct Reset{Object prior;~Reset(){activeCanvas=prior;}}reset{prior};scopedMatrices(canvas,center,normal,radius,style,segments,color,bomb_projection::scope.fov,bomb_projection::scope.aspect);}
 else if(original)original(canvas,center,normal,radius,style,segments,color);
}

#ifndef AC8_BOMB_PROJECTION_FIXTURE
inline bool initialize(const UEVR_PluginInitializeParam* p){
 host=p;if(!bomb_projection::installed||!p||!p->functions||!p->callbacks||!p->callbacks->on_custom_event)return false;
 auto module=GetModuleHandleW(nullptr);std::array<unsigned char,32> bytes{};
 if(!module||!bomb_projection::read(reinterpret_cast<unsigned char*>(module)+circleRva,bytes)||bytes!=prologue){return false;}
 const int id=p->functions->register_inline_hook(reinterpret_cast<unsigned char*>(module)+circleRva,reinterpret_cast<void*>(&wrapper),reinterpret_cast<void**>(&original));
 installed=id>=0&&original;if(!installed&&id>=0)p->functions->unregister_inline_hook(id);
 return installed;
}
#endif
}
