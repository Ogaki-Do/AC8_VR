// Coordinate D3D12 HUD-copy observation, glow generation and per-eye composition.
// The recursive lock serializes host callbacks with the OpenXR bridge. Only
// current, fully covered, waited images may be written; fence completion protects
// resource reuse. Unsupported/reset/error states disable this path safely.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "../../vendor/uevr/backend-api.h"
#include "render-utils.h"
#include "hud_route_scene.h"
#include "openxr_handoff.h"
#include "hud_submission_layout.h"
#include <unordered_set>
#include <fstream>
#include <intrin.h>
namespace hud_renderer {
using Microsoft::WRL::ComPtr;
const UEVR_PluginInitializeParam* api=nullptr;
std::unique_ptr<hud_route_glow::Renderer> renderer;
std::unique_ptr<hud_route_scene::Renderer> scene_renderer;
openxr_handoff::Bridge bridge;
ComPtr<ID3D12Resource> ui;
ComPtr<ID3D12Fence> fence;
ComPtr<ID3D12Device> device;
std::recursive_mutex mutex;
std::unordered_set<ID3D12CommandList*> recorded,known_direct_lists;
std::filesystem::path assets_path;
uint64_t fence_value=0,writes=0,rejects=0,scene_writes=0,scene_consumer=0,generation_frame=0,generation_fence=0;
uint64_t observed_copies=0,held_images=0,frame_callbacks=0;
uint64_t skipped_busy=0,skipped_generation=0,skipped_geometry=0,skipped_pair=0,skipped_layers=0,skipped_record=0;
uint32_t last_layer_count=0;
std::array<int32_t,16> last_layer_types{};
std::atomic<bool> active{false},overlay{false};
std::atomic<bool> refresh_pending{false};
std::atomic<bool> flight_allowed{false};
std::atomic<const char*> refresh_reason{"glow_activation"};
bool failed=false,bridge_installed=false,late_session_recovered=false;
bool glow_requested=true;
bool startup_reset_pending=false;
uint64_t device_resets=0,startup_reset_recoveries=0;
const char* failure_reason="none";
const char* state="waiting_for_f9";
thread_local bool nested=false;
struct NestedScope {bool saved;NestedScope():saved(nested){nested=true;}~NestedScope(){nested=saved;}};
struct CopyRecord {
    acquired_images::Token token{};ComPtr<ID3D12Resource> resource;
    ID3D12CommandList* list=nullptr;uint64_t frame=0,ticket=0;
    D3D12_RESOURCE_STATES final_state=D3D12_RESOURCE_STATE_COPY_DEST;
    D3D12_RECT area{};bool hud=false,generated=false,valid=true;
};
std::vector<CopyRecord> copies;
using CopyFn=void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,ID3D12Resource*,ID3D12Resource*);
using RegionFn=void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,const D3D12_TEXTURE_COPY_LOCATION*,UINT,UINT,UINT,const D3D12_TEXTURE_COPY_LOCATION*,const D3D12_BOX*);
using BarrierFn=void(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,UINT,const D3D12_RESOURCE_BARRIER*);
using ExecuteFn=void(STDMETHODCALLTYPE*)(ID3D12CommandQueue*,UINT,ID3D12CommandList* const*);
using ResetFn=HRESULT(STDMETHODCALLTYPE*)(ID3D12GraphicsCommandList*,ID3D12CommandAllocator*,ID3D12PipelineState*);
CopyFn original_copy=nullptr;RegionFn original_region=nullptr;BarrierFn original_barrier=nullptr;ExecuteFn original_execute=nullptr;ResetFn original_reset=nullptr;

ID3D12Resource* safe_ui(){
    __try{auto* texture=api->sdk->stereo_hook->get_ui_render_target();return texture?static_cast<ID3D12Resource*>(api->sdk->frhitexture2d->get_native_resource(texture)):nullptr;}
    __except(EXCEPTION_EXECUTE_HANDLER){return nullptr;}
}
void stop(const char* reason){active=false;if(renderer)renderer->policy({});state=reason;
    if(failed&&std::strcmp(reason,"left_flight_off")&&std::strcmp(reason,"manual_off"))failure_reason=reason;
    }
bool enabled(){return active&&!failed;}
hud_policy::PacketCache policy_packets;
void lifecycle(const char* event,const char* data){
    if(event&&data&&!std::strcmp(event,"AC8_HUD_PolicyV50")){std::lock_guard<std::recursive_mutex> guard(mutex);const auto policy=policy_packets.update(data,GetTickCount64());if(renderer)renderer->policy(policy);return;}
    if(!event||!data||std::strcmp(event,"AC8_HUD_GlowLifecycle"))return;
    std::lock_guard<std::recursive_mutex> guard(mutex);
    if(!std::strcmp(data,"mission_entry")||!std::strcmp(data,"flight")){
        if(!std::strcmp(data,"mission_entry")){glow_requested=true;overlay=false;}
        else flight_allowed=true;
        if(!flight_allowed||!glow_requested||failed)return;
        active=true;copies.clear();generation_frame=generation_fence=0;
        refresh_reason="glow_activation";refresh_pending=true;
        state="waiting_current_scene_pair";return;
    }
    if(!std::strcmp(data,"outside_flight")){
        flight_allowed=false;copies.clear();generation_frame=generation_fence=0;
        stop("left_flight_off");return;
    }
    if(!std::strcmp(data,"pause_enter")||!std::strcmp(data,"pause_exit")){
        
        copies.clear();generation_frame=generation_fence=0;
        refresh_reason=!std::strcmp(data,"pause_enter")?"pause_enter":"pause_exit";
        refresh_pending=true;
        if(active)state="waiting_fresh_pause_frame";
    }
}

void engine_tick(UEVR_UGameEngineHandle,float){
    if(refresh_pending.exchange(false)&&api->functions->dispatch_lua_event)
        api->functions->dispatch_lua_event("AC8_HUD_Refresh",refresh_reason.load());
}
// Bridge observation occurs BEFORE the plugin lock. XR callbacks lock in the
// opposite direction (bridge -> plugin), so never call observed_image under it.
void observe_copy(ID3D12GraphicsCommandList* list,ID3D12Resource* dst,ID3D12Resource* src,const D3D12_RECT& area,bool full){
    acquired_images::Token token{};uint64_t frame=0;openxr_handoff::Binding binding;
    const bool observed=active.load()&&!overlay.load()&&bridge.observed_image(dst,token,frame,binding);
    std::lock_guard<std::recursive_mutex> lock(mutex);
    if(!enabled()||!renderer||dst==src)return;

    std::wstring name;if(!known_direct_lists.count(list)||!destination::isolated_list(list,name)){++rejects;return;}
    bool generated=false;
    if(full&&src==ui.Get()){
        if(recorded.size()>=64&&!recorded.count(list)){stop("recording_capacity_off");return;}
        // No change to the host's sharp source. Scene mode only runs generation.
        nested=true;try{generated=renderer->record(list,dst,src,overlay);if(generated){recorded.insert(list);++writes;state=overlay?"black_overlay_comparison_active":"waiting_current_scene_pair";}else ++rejects;}
        catch(...){failed=true;stop("record_failed_off");}nested=false;
    }
    if(overlay||!observed||binding.device.Get()!=device.Get()||!hud_route_scene::Renderer::supported(dst))return;
    ++observed_copies;
    // Every recognized scene copy must precede its final observed RT barrier.
    // Current tokens pin the actual acquired image; reset records are discarded.
    copies.erase(std::remove_if(copies.begin(),copies.end(),[&](const CopyRecord& r){return r.frame!=frame;}),copies.end());
    if(copies.size()>=64){stop("copy_capacity_off");return;}
    copies.push_back({token,dst,list,frame,0,D3D12_RESOURCE_STATE_COPY_DEST,area,full&&src==ui.Get(),generated,true});
}
void STDMETHODCALLTYPE copy(ID3D12GraphicsCommandList* list,ID3D12Resource* dst,ID3D12Resource* src){
    original_copy(list,dst,src);if(nested||!dst||!src)return;
    const auto d=dst->GetDesc();if(d.Width>LONG_MAX||d.Height>LONG_MAX)return;
    observe_copy(list,dst,src,{0,0,static_cast<LONG>(d.Width),static_cast<LONG>(d.Height)},true);
}
void STDMETHODCALLTYPE region(ID3D12GraphicsCommandList* list,const D3D12_TEXTURE_COPY_LOCATION* dst,UINT x,UINT y,UINT z,const D3D12_TEXTURE_COPY_LOCATION* src,const D3D12_BOX* box){
    original_region(list,dst,x,y,z,src,box);if(nested||!dst||!src||!dst->pResource||!src->pResource||z||dst->Type!=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX||src->Type!=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX||dst->SubresourceIndex||src->SubresourceIndex)return;
    const auto s=src->pResource->GetDesc(),d=dst->pResource->GetDesc();
    const UINT64 w=box?box->right-box->left:s.Width;const UINT64 h=box?box->bottom-box->top:s.Height;
    if(!w||!h||uint64_t(x)+w>d.Width||uint64_t(y)+h>d.Height||uint64_t(x)+w>LONG_MAX||uint64_t(y)+h>LONG_MAX||(box&&(box->front||box->back!=1)))return;
    const bool full=!x&&!y&&w==d.Width&&h==d.Height&&s.Width==d.Width&&s.Height==d.Height&&(!box||(!box->left&&!box->top));
    observe_copy(list,dst->pResource,src->pResource,{static_cast<LONG>(x),static_cast<LONG>(y),static_cast<LONG>(x+w),static_cast<LONG>(y+h)},full);
}
void STDMETHODCALLTYPE barriers(ID3D12GraphicsCommandList* list,UINT count,const D3D12_RESOURCE_BARRIER* barriers){
    original_barrier(list,count,barriers);if(nested||!barriers)return;
    std::lock_guard<std::recursive_mutex> lock(mutex);
    for(UINT i=0;i<count;++i){const auto& b=barriers[i];if(b.Type!=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION)continue;
        for(auto& r:copies)if(!r.ticket&&r.list==list&&r.token.resource==b.Transition.pResource){
            if(b.Flags!=D3D12_RESOURCE_BARRIER_FLAG_NONE||(b.Transition.Subresource!=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES&&b.Transition.Subresource!=0)||r.final_state!=b.Transition.StateBefore)r.valid=false;
            r.final_state=b.Transition.StateAfter;
        }
    }
}
void STDMETHODCALLTYPE execute(ID3D12CommandQueue* queue,UINT count,ID3D12CommandList* const* lists){
    if(nested){original_execute(queue,count,lists);return;}
    std::lock_guard<std::recursive_mutex> lock(mutex);bool uses=false;ComPtr<ID3D12Device> actual_device;
    const bool checked=queue->GetDesc().Type==D3D12_COMMAND_LIST_TYPE_DIRECT&&SUCCEEDED(queue->GetDevice(IID_PPV_ARGS(&actual_device)))&&actual_device.Get()==device.Get();
    for(UINT i=0;i<count&&lists;++i){uses=uses||recorded.count(lists[i])!=0;for(const auto& r:copies)uses=uses||(!r.ticket&&r.list==lists[i]);if(checked&&known_direct_lists.size()<64)known_direct_lists.insert(lists[i]);}
    if(uses&&(!checked||(fence_value&&FAILED(queue->Wait(fence.Get(),fence_value))))){failed=true;stop("queue_wait_failed_off");}
    original_execute(queue,count,lists);
    if(uses){const auto next=fence_value+1;const bool signaled=checked&&SUCCEEDED(queue->Signal(fence.Get(),next));
        for(UINT i=0;i<count&&lists;++i){recorded.erase(lists[i]);for(auto& r:copies)if(!r.ticket&&r.list==lists[i]){if(queue!=api->renderer->command_queue)r.valid=false;if(signaled){r.ticket=next;if(r.generated){generation_frame=r.frame;generation_fence=next;}}else r.valid=false;}}
        if(signaled)fence_value=next;else{failed=true;stop("queue_signal_failed_off");}
    }
}
HRESULT STDMETHODCALLTYPE reset(ID3D12GraphicsCommandList* list,ID3D12CommandAllocator* allocator,ID3D12PipelineState* pipeline){
    const auto result=original_reset(list,allocator,pipeline);if(SUCCEEDED(result)&&!nested){std::lock_guard<std::recursive_mutex> lock(mutex);recorded.erase(list);copies.erase(std::remove_if(copies.begin(),copies.end(),[&](const CopyRecord& r){return !r.ticket&&r.list==list;}),copies.end());}return result;
}


bool can_hold(const acquired_images::Token& token,uint64_t frame,void*){
    std::lock_guard<std::recursive_mutex> lock(mutex);if(!enabled()||overlay)return false;
    for(const auto& r:copies)if(r.frame==frame&&r.token==token&&r.ticket&&r.valid&&r.final_state==D3D12_RESOURCE_STATE_RENDER_TARGET){++held_images;return true;}return false;
}
bool coverage(const acquired_images::Token& token,uint64_t frame,const xr_read::Rect& rect,bool require_hud){
    // Verify the union of submitted copy rectangles, including split eye copies.
    std::vector<LONG> xs{rect.offset.x,rect.offset.x+rect.extent.width},ys{rect.offset.y,rect.offset.y+rect.extent.height};std::vector<D3D12_RECT> areas;
    for(const auto& r:copies)if(r.token==token&&r.frame==frame){
        if(!r.valid||!r.ticket||r.final_state!=D3D12_RESOURCE_STATE_RENDER_TARGET)return false;
        if(require_hud&&!r.hud)continue;auto a=r.area;a.left=std::max(a.left,LONG(rect.offset.x));a.top=std::max(a.top,LONG(rect.offset.y));a.right=std::min(a.right,LONG(rect.offset.x+rect.extent.width));a.bottom=std::min(a.bottom,LONG(rect.offset.y+rect.extent.height));
        if(a.left<a.right&&a.top<a.bottom){areas.push_back(a);xs.push_back(a.left);xs.push_back(a.right);ys.push_back(a.top);ys.push_back(a.bottom);}
    }
    std::sort(xs.begin(),xs.end());std::sort(ys.begin(),ys.end());
    for(size_t x=1;x<xs.size();++x)for(size_t y=1;y<ys.size();++y){if(xs[x]==xs[x-1]||ys[y]==ys[y-1])continue;bool found=false;for(const auto& a:areas)if(a.left<=xs[x-1]&&a.right>=xs[x]&&a.top<=ys[y-1]&&a.bottom>=ys[y]){found=true;break;}if(!found)return false;}
    return !areas.empty();
}
openxr_handoff::FrameOutcome frame_sink(openxr_handoff::Session session,const xr_read::EndInfo* info,const openxr_handoff::Held* held,size_t count,uint64_t frame,ID3D12Device* actual_device,ID3D12CommandQueue* queue,void*){
    using Outcome=openxr_handoff::FrameOutcome;std::lock_guard<std::recursive_mutex> lock(mutex);
    ++frame_callbacks;
    if(!enabled()||overlay||actual_device!=device.Get()||!queue)return Outcome::unchanged;
    last_layer_count=info?info->layerCount:0;last_layer_types.fill(0);
    if(info&&info->layers)for(unsigned i=0;i<(std::min)(last_layer_count,16u);++i)last_layer_types[i]=info->layers[i]?info->layers[i]->type:0;
    if(!hud_submission_layout::supported(info)){state="unsupported_layer_layout_skipped";++rejects;++skipped_layers;return Outcome::unchanged;}
    const openxr_handoff::Held *hud=nullptr,*scene=nullptr;
    for(size_t i=0;i<count;++i){bool is_hud=false;for(const auto& r:copies)if(r.token==held[i].token&&r.frame==frame&&r.hud)is_hud=true;
        if(is_hud){current_geometry::Snapshot candidate{};for(size_t j=0;j<count;++j)if(i!=j&&current_geometry::read_layers(info,held[j].token.chain,held[i].token.chain,&candidate)){if(hud||scene){state="ambiguous_layers_skipped";++rejects;return Outcome::unchanged;}hud=&held[i];scene=&held[j];}}
    }
    if(!hud||!scene){state="waiting_current_scene_pair";++skipped_pair;return Outcome::unchanged;}
    if(!hud_submission_layout::independent_quads(info,scene->token.chain,hud->token.chain)){state="shared_auxiliary_texture_skipped";++rejects;++skipped_layers;return Outcome::unchanged;}
    if(generation_frame!=frame||!generation_fence||!recorded.empty()||!bridge.pending_exact(hud->token)||!bridge.pending_exact(scene->token)){state="current_generation_gate_skipped";++rejects;++skipped_generation;return Outcome::unchanged;}
    const auto sd=scene->resource->GetDesc(),hd=hud->resource->GetDesc();
    current_geometry::Request request{};request.frame=frame;request.layout=1;request.scene_chain=scene->token.chain;request.hud_chain=hud->token.chain;request.scene_width=static_cast<uint32_t>(sd.Width);request.scene_height=sd.Height;request.hud_width=static_cast<uint32_t>(hd.Width);request.hud_height=hd.Height;
    current_geometry::Snapshot raw{},geometry{};if(!current_geometry::read_layers(info,request.scene_chain,request.hud_chain,&raw)){++rejects;return Outcome::unchanged;}
    // These are presentation-local poses from THIS call, not a claim about the
    // earlier engine frame-selection hook. Both layers must share actual space.
    request.selected.valid=true;request.selected.session=reinterpret_cast<uint64_t>(session);request.selected.space=raw.space;request.selected.frame=static_cast<uint32_t>(frame);
    for(unsigned i=0;i<2;++i){request.selected.poses[i]=raw.eyes[i].pose;request.selected.fovs[i]=raw.eyes[i].fov;}
    if(!current_geometry::read(session,info,request,geometry)||geometry.cylinder.layerFlags!=2||!coverage(hud->token,frame,geometry.cylinder.subImage.imageRect,true)||!coverage(scene->token,frame,geometry.eyes[0].subImage.imageRect,false)||!coverage(scene->token,frame,geometry.eyes[1].subImage.imageRect,false)){
        state="geometry_state_or_copy_coverage_skipped";++rejects;++skipped_geometry;return Outcome::unchanged;}
    if(fence->GetCompletedValue()==UINT64_MAX){failed=true;stop("device_removed_off");return Outcome::unchanged;}
    bool recorded_scene=false;
    try{if(!scene_renderer)scene_renderer=std::make_unique<hud_route_scene::Renderer>(device.Get(),assets_path,*renderer,scene->resource.Get());recorded_scene=scene_renderer->record(*renderer,scene->resource.Get(),hud->resource.Get(),geometry,fence.Get());}
    catch(...){failed=true;stop("scene_record_failed_off");}nested=false;
    if(!recorded_scene){if(scene_renderer&&scene_renderer->busy()){++skipped_busy;state="scene_consumer_busy_skipped";}else{++skipped_record;++rejects;}return Outcome::unchanged;}
    if(FAILED(queue->Wait(fence.Get(),fence_value))){failed=true;stop("scene_queue_wait_failed_off");return Outcome::unchanged;}
    auto* commands=scene_renderer->commands();nested=true;original_execute(queue,1,&commands);nested=false;
    const auto next=fence_value+1;if(FAILED(queue->Signal(fence.Get(),next))){failed=true;stop("scene_queue_signal_failed_off");return Outcome::fatal;}
    fence_value=next;scene_consumer=next;scene_renderer->submitted(next);
    ++scene_writes;state="native_scene_per_eye_active";return Outcome::submitted;
}
bool startup_reset_can_resume(bool same_device,bool healthy,bool direct_queue){
    return failed&&startup_reset_pending&&!writes&&!scene_writes&&!fence_value&&same_device&&healthy&&direct_queue;
}
void recover_startup_reset(){
    if(!startup_reset_pending||!api||!api->renderer||!device||!fence)return;
    auto* queue=static_cast<ID3D12CommandQueue*>(api->renderer->command_queue);
    ComPtr<ID3D12Device> actual;
    const bool same=queue&&api->renderer->device==device.Get()&&
        SUCCEEDED(queue->GetDevice(IID_PPV_ARGS(&actual)))&&actual.Get()==device.Get();
    if(!startup_reset_can_resume(same,device->GetDeviceRemovedReason()==S_OK,
          queue&&queue->GetDesc().Type==D3D12_COMMAND_LIST_TYPE_DIRECT)||fence->GetCompletedValue()!=0)return;
    // No glow command has been submitted. A same-device backbuffer resize can
    // retain the initialized shader resources; real device/GPU failures stay off.
    startup_reset_pending=false;failed=false;failure_reason="none";++startup_reset_recoveries;
    copies.clear();recorded.clear();generation_frame=generation_fence=0;
    active=flight_allowed&&glow_requested;
    if(active){refresh_reason="glow_activation";refresh_pending=true;}
    state=active?"waiting_current_scene_pair":"waiting_for_flight";
}
void present(){
    std::lock_guard<std::recursive_mutex> lock(mutex);ui=safe_ui();
    recover_startup_reset();

}
void device_reset(){std::lock_guard<std::recursive_mutex> lock(mutex);++device_resets;
    
    startup_reset_pending=(!failed||startup_reset_pending)&&!writes&&!scene_writes&&!fence_value;
    failed=true;copies.clear();generation_frame=generation_fence=0;stop("device_reset_off");}
bool initialize(const UEVR_PluginInitializeParam* params){
    api=params;device=static_cast<ID3D12Device*>(api->renderer->device);HMODULE module=nullptr;GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,reinterpret_cast<LPCWSTR>(&present),&module);
    wchar_t path[32768]{};if(!module||!GetModuleFileNameW(module,path,32768))return false;const auto directory=std::filesystem::path(path).parent_path();assets_path=directory/L"ac8-hud-assets";
    renderer=std::make_unique<hud_route_glow::Renderer>(device.Get(),assets_path);native_generation::check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)));
    ComPtr<ID3D12CommandAllocator> allocator;ComPtr<ID3D12GraphicsCommandList> list;native_generation::check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));native_generation::check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&list)));list->Close();
    auto** methods=*reinterpret_cast<void***>(list.Get());auto** queue_methods=*reinterpret_cast<void***>(api->renderer->command_queue);
    const int a=api->functions->register_inline_hook(methods[17],reinterpret_cast<void*>(&copy),reinterpret_cast<void**>(&original_copy));
    const int b=api->functions->register_inline_hook(queue_methods[10],reinterpret_cast<void*>(&execute),reinterpret_cast<void**>(&original_execute));
    const int c=api->functions->register_inline_hook(methods[10],reinterpret_cast<void*>(&reset),reinterpret_cast<void**>(&original_reset));
    const int d=api->functions->register_inline_hook(methods[16],reinterpret_cast<void*>(&region),reinterpret_cast<void**>(&original_region));
    const int e=api->functions->register_inline_hook(methods[26],reinterpret_cast<void*>(&barriers),reinterpret_cast<void**>(&original_barrier));
    if(a<0||b<0||c<0||d<0||e<0||!original_copy||!original_execute||!original_reset||!original_region||!original_barrier){failed=true;state="hook_failed_off";return true;}
    bridge_installed=bridge.attach(api,{can_hold,frame_sink,nullptr});
    if(bridge_installed&&api->openxr&&api->openxr->get_xr_session&&api->vr&&api->vr->is_openxr&&api->vr->is_openxr())
        late_session_recovered=bridge.adopt_existing_session(reinterpret_cast<void*>(api->openxr->get_xr_session()),device.Get(),static_cast<ID3D12CommandQueue*>(api->renderer->command_queue));
    if(api->sdk&&api->sdk->callbacks&&api->sdk->callbacks->on_pre_engine_tick)
        api->sdk->callbacks->on_pre_engine_tick(engine_tick);
    if(!api->callbacks->on_custom_event||!api->callbacks->on_custom_event(lifecycle)){failed=true;state="lifecycle_callback_failed_off";}
    if(!api->callbacks->on_present(present)){failed=true;state="callback_failed_off";}if(api->callbacks->on_device_reset)api->callbacks->on_device_reset(device_reset);return true;
}
}
extern "C"  void uevr_plugin_required_version(UEVR_PluginVersion* v){if(v)*v={UEVR_PLUGIN_VERSION_MAJOR,UEVR_PLUGIN_VERSION_MINOR,UEVR_PLUGIN_VERSION_PATCH};}
extern "C"  bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* p){
    if(!p||!p->renderer||!p->sdk||!p->sdk->stereo_hook||!p->sdk->frhitexture2d||!p->callbacks||!p->functions||!p->sdk->stereo_hook->get_ui_render_target||!p->sdk->frhitexture2d->get_native_resource||!p->callbacks->on_present||!p->functions->register_inline_hook||p->renderer->renderer_type!=UEVR_RENDERER_D3D12||!p->renderer->device||!p->renderer->command_queue)return false;
    try{return hud_renderer::initialize(p);}catch(...){hud_renderer::failed=true;hud_renderer::state="initialization_failed_off";return true;}
}

