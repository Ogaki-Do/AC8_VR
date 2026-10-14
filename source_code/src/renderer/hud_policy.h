// Parse bounded Lua policy rectangles and retain a wall-clock heartbeat.
// Unchanged packet text reuses parsed geometry, but refreshes its expiry on every
// delivery. Expired/invalid policy must not leave stale masks on a new HUD.

#pragma once
#include <array>
#include <cmath>
#include <sstream>
#include <string>
#include <cstring>
#include <cstdint>
namespace hud_policy {
// GPU channels: exclude glow input/output, normal sharp, emissive sharp,
// exclude additional decoration. Mode 3 is a reduced portrait border;
// mode 4 is normal sharp transparency with retained glow.
struct Region {float bounds[4]{},flags[4]{};};
struct Snapshot {
    std::array<Region,48> regions{};
    unsigned count=0;uint64_t time=0;
    bool fresh(uint64_t now)const{return time&&now>=time&&now-time<=250;}
};
inline bool parse(const char* data,uint64_t now,Snapshot& result){
    result={};if(!data||std::strlen(data)>16384)return false;
    std::string input(data);for(auto& c:input)if(c=='|')c=' ';
    std::istringstream stream(input);unsigned count=0;
    if(!(stream>>count)||count>result.regions.size())return false;
    for(unsigned i=0;i<count;++i){auto& r=result.regions[i];
        for(float& v:r.bounds)if(!(stream>>v)||!std::isfinite(v)||v<0||v>1)return false;
        if(r.bounds[0]>=r.bounds[2]||r.bounds[1]>=r.bounds[3])return false;
        for(unsigned j=0;j<4;++j){float& v=r.flags[j];if(!(stream>>v)||(v!=0&&v!=1&&!(j==2&&(v==2||v==3||v==4))))return false;}
        if(r.flags[1]&&r.flags[2])return false;
    }
    std::string extra;if(stream>>extra)return false;
    result.count=count;result.time=now;return true;
}
// The Lua producer still sends the full current packet every frame. Reusing a
// validated parse removes stream allocations without changing its timestamp,
// expiry, dropped-update recovery, or renderer recreation behavior.
struct PacketCache {
    std::string packet;
    Snapshot snapshot{};
    bool valid=false;
    uint64_t parses=0;
    Snapshot update(const char* data,uint64_t now){
        if(data&&valid&&packet==data){snapshot.time=now;return snapshot;}
        Snapshot next{};++parses;
        if(parse(data,now,next)){packet=data;snapshot=next;valid=true;}
        else{packet.clear();snapshot={};valid=false;}
        return snapshot;
    }
};
}
