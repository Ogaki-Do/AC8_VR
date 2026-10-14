// Bridge painted velocity-icon coordinates into the native bomb draw. Packets
// include widget/canvas identities and a freshness time; never reuse an anchor
// from a previous HUD or accumulate an offset over the previous output.

#pragma once
#include <mutex>
// A native dynamic-draw primitive cannot be reparented as a UMG child. Attach
// its origin to the painted velocity icon and share that draw's horizontal
// attachment with its landing geometry. Vertical landing calibration is retained.
namespace bomb_line_anchor {
constexpr uintptr_t originCaller=0x72456c5;
struct Anchor {bool enabled=false;uintptr_t widget=0,canvas=0;double x=0,y=0;uint64_t updated=0;};
inline std::mutex mutex;
inline Anchor anchor{};
inline void control(const char* event,const char* data){
 if(!event||std::strcmp(event,"AC8_BombLineAnchor")||!data)return;
 int enabled=0;uintptr_t widget=0,canvas=0;double x=0,y=0;char a=0,b=0,c=0,d=0;std::istringstream in(data);
 if(!(in>>enabled>>a>>widget>>b>>canvas>>c>>x>>d>>y)||a!='|'||b!='|'||c!='|'||d!='|'||(enabled!=0&&enabled!=1)||!std::isfinite(x+y)||std::abs(x)>=1e7||std::abs(y)>=1e7||(enabled&&(!widget||!canvas)))return;
 in>>std::ws;if(!in.eof())return;
 std::lock_guard<std::mutex> lock(mutex);anchor={enabled!=0,widget,canvas,x,y,GetTickCount64()};
}
inline bool apply(uintptr_t caller,double& x,double& y,uint64_t now){
 if(caller!=originCaller||!bomb_projection::scope.active||!std::isfinite(x+y))return false;
 bomb_projection::originAttachment={};
 std::unique_lock<std::mutex> lock(mutex,std::try_to_lock);if(!lock.owns_lock())return false;
 if(!anchor.enabled||now<anchor.updated||now-anchor.updated>1250||
    anchor.widget!=reinterpret_cast<uintptr_t>(bomb_projection::scopedWidget)||anchor.canvas!=reinterpret_cast<uintptr_t>(bomb_projection::scopedCanvas))return false;
 bomb_projection::originAttachment={true,anchor.x-x};
 x=anchor.x;y=anchor.y;return true;
}
inline bool landingCaller(uintptr_t caller){
 // Exact callers observed in both manual and automatic native bomb captures.
 return caller==0x72457ba||caller==0x723d7e9||caller==0x723d911||caller==0x724759d;
}
inline bool applyHorizontal(uintptr_t caller,double& x){
 const auto delta=bomb_projection::originAttachment;
 if(!bomb_projection::scope.active||!delta.active||!landingCaller(caller)||delta.horizontal==0||!std::isfinite(x+delta.horizontal))return false;
 x+=delta.horizontal;return true;
}

}
