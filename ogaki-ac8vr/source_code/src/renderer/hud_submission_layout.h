// Accept one scene projection and one HUD cylinder plus independent UI quads.
// Reject ambiguous/aliased chains instead of guessing which image is writable.

#pragma once
#include "../backend/xr_subset.h"
namespace hud_submission_layout {
// Preserve extra compositor UI quads. Scene projection and HUD cylinder remain unique.
inline bool supported(const xr_read::EndInfo* info) {
    if(!info||info->type!=xr_read::frame_end_info||info->next||!info->layers||info->layerCount<2||info->layerCount>16)return false;
    unsigned scene=0,hud=0;
    for(unsigned i=0;i<info->layerCount;++i){const auto* layer=info->layers[i];if(!layer||layer->next)return false;
        if(layer->type==xr_read::projection)++scene;
        else if(layer->type==xr_read::cylinder)++hud;
        else if(layer->type!=xr_read::quad)return false;}
    return scene==1&&hud==1;
}
inline bool independent_quads(const xr_read::EndInfo* info,uint64_t scene,uint64_t hud) {
    for(unsigned i=0;i<info->layerCount;++i)if(info->layers[i]->type==xr_read::quad){
        const auto* q=reinterpret_cast<const xr_read::Quad*>(info->layers[i]);const auto chain=reinterpret_cast<uint64_t>(q->subImage.swapchain);
        if(!chain||chain==scene||chain==hud)return false;}
    return true;
}
}
