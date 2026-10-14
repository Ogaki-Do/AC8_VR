// Observe supported OpenXR dispatch boundaries and hold eligible image releases
// until composition finishes. The bridge owns session/chain generations and
// must flush held releases on disable/reset/destroy, including failed frames.

#pragma once
// Guarded, process-resident OpenXR wrapper bridge. The controller supplies
// explicit eligibility and composition; this file never records GPU commands.
// A selected release returns provisional XR_SUCCESS. Its later runtime error
// cannot be replayed to that original call; all other calls retain real results.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <utility>
#include <vector>
#include "../../vendor/uevr/backend-api.h"
#include "../backend/backend_boundary.h"
#include "../backend/xr_subset.h"
#include "xr_dispatch_guards.h"
#include "acquired_images.h"

namespace openxr_handoff {
using Session=void*;
using Instance=void*;
using Swapchain=acquired_images::Swapchain;
using Result=int32_t;
constexpr Result runtime_failure=-2;
constexpr int32_t graphics_binding_d3d12=1000028000,image_d3d12=1000028001;
constexpr int32_t session_create_type=8,swapchain_create_type=9,release_info_type=57;
struct Base {int32_t type;const void* next;};
struct SessionCreateInfo {int32_t type;const void* next;uint64_t create_flags,system_id;};
struct GraphicsBinding {int32_t type;const void* next;ID3D12Device* device;ID3D12CommandQueue* queue;};
struct SwapchainCreateInfo {int32_t type;const void* next;uint64_t create_flags,usage_flags;int64_t format;
    uint32_t sample_count,width,height,face_count,array_size,mip_count;};
struct Image {int32_t type;void* next;ID3D12Resource* texture;};
struct Binding {Session session=nullptr;Microsoft::WRL::ComPtr<ID3D12Device> device;
    Microsoft::WRL::ComPtr<ID3D12CommandQueue> queue;
    explicit operator bool() const{return session&&device&&queue;}};
struct Held {acquired_images::Token token{};Microsoft::WRL::ComPtr<ID3D12Resource> resource;};
enum class FrameOutcome { unchanged,submitted,fatal };
struct Callbacks {
    bool (*can_hold)(const acquired_images::Token&,uint64_t frame,void*)=nullptr;
    FrameOutcome (*frame_sink)(Session,const xr_read::EndInfo*,const Held*,size_t,uint64_t,
                               ID3D12Device*,ID3D12CommandQueue*,void*)=nullptr;
    void* context=nullptr;
};
struct HookApi {int (*install)(void*,void*,void**,void*)=nullptr;void* context=nullptr;};
static_assert(sizeof(SessionCreateInfo)==32&&sizeof(GraphicsBinding)==32&&
              sizeof(SwapchainCreateInfo)==64&&sizeof(Image)==24);
static_assert(sizeof(acquired_images::ReleaseInfo)==16&&sizeof(xr_read::EndInfo)==40);

class Bridge {
    friend struct LateAttachFixture;
    using CreateSessionFn=Result(__stdcall*)(Instance,const SessionCreateInfo*,Session*);
    using CreateSwapchainFn=Result(__stdcall*)(Session,const SwapchainCreateInfo*,Swapchain*);
    using DestroySwapchainFn=Result(__stdcall*)(Swapchain);
    using EnumFn=Result(__stdcall*)(Swapchain,uint32_t,uint32_t*,Image*);
    using AcquireFn=Result(__stdcall*)(Swapchain,const Base*,uint32_t*);
    using WaitFn=Result(__stdcall*)(Swapchain,const Base*);
    using ReleaseFn=Result(__stdcall*)(Swapchain,const acquired_images::ReleaseInfo*);
    using EndSessionFn=Result(__stdcall*)(Session);
    using BeginFrameFn=Result(__stdcall*)(Session,const Base*);
    using EndFrameFn=Result(__stdcall*)(Session,const xr_read::EndInfo*);
    struct Chain {Swapchain handle=0;Session session=nullptr;uint64_t generation=0,held_frame=0;
        uint32_t count=0;std::array<Microsoft::WRL::ComPtr<ID3D12Resource>,16> images{};
        std::optional<acquired_images::Token> waited,held;};
    inline static std::atomic<Bridge*> active_{nullptr};
    std::recursive_mutex transaction_;
    acquired_images::Bookkeeper images_{release_info_type};
    std::array<Chain,16> chains_{};
    Binding binding_{};Callbacks callbacks_{};
    uint64_t frame_=0;uint32_t observed_sessions_=0;
    bool frame_open_=false,disabled_=false,committing_=false,fatal_frame_=false;
    std::atomic<bool> ready_{false};
    HookApi hooks_{};unsigned char* backend_=nullptr;
    CreateSessionFn create_session_=nullptr;CreateSwapchainFn create_swapchain_=nullptr;
    DestroySwapchainFn destroy_swapchain_=nullptr;EnumFn enumerate_=nullptr;
    AcquireFn acquire_=nullptr;WaitFn wait_=nullptr;ReleaseFn release_=nullptr;
    EndSessionFn end_session_=nullptr;BeginFrameFn begin_frame_=nullptr;EndFrameFn end_frame_=nullptr;
    static void pin_anchor(){}
    static int install_from_api(void* target,void* detour,void** original,void* context){
        const auto* api=static_cast<const UEVR_PluginInitializeParam*>(context);
        return api->functions->register_inline_hook(target,detour,original);
    }
    static bool guarded_image(unsigned char* base){
        if(!boundary::image_matches(base))return false;
        __try{
            for(const auto& entry:xr_dispatch_guards::entries)
                if(std::memcmp(base+entry.rva,entry.bytes,sizeof(entry.bytes)))return false;
            return true;
        }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    template<typename Fn> bool install(size_t entry,void* detour,Fn& original){
        static_assert(sizeof(Fn)==sizeof(void*),"unsupported function pointer ABI");
        if(!hooks_.install)return false;
        auto* target=backend_+xr_dispatch_guards::entries[entry].rva;
        // Installer must publish the trampoline before enabling the detour.
        return hooks_.install(target,detour,reinterpret_cast<void**>(&original),hooks_.context)>=0&&original;
    }
    Chain* chain(Swapchain handle){for(auto& c:chains_)if(c.handle==handle)return &c;return nullptr;}
    Chain* vacant(){for(auto& c:chains_)if(!c.handle)return &c;return nullptr;}
    acquired_images::ReleaseCall actual_release(){return {call_release,this};}
    static Result call_release(Swapchain handle,const acquired_images::ReleaseInfo* info,void* context){
        return static_cast<Bridge*>(context)->release_(handle,info);
    }
    void clear_settled(Chain& c){if(!images_.state(c.handle).pending)c.held.reset();}
    bool flush_chain(Chain& c){
        const bool okay=images_.flush_chain(c.handle,actual_release());clear_settled(c);return okay;
    }
    bool flush_all(){
        const bool okay=images_.flush_all(actual_release());
        for(auto& c:chains_)if(c.handle)clear_settled(c);
        return okay;
    }
    bool effect(Session session){return ready_.load(std::memory_order_acquire)&&!disabled_&&
        binding_&&binding_.session==session&&images_.mutation_enabled();}
    bool disable_effect(){disabled_=true;frame_open_=false;return images_.disable(actual_release());}
    static bool read_binding(const SessionCreateInfo* info,Session* output,GraphicsBinding* binding,Session* session){
        __try{
            if(!output||!*output||!info||info->type!=session_create_type||!info->next)return false;
            *binding=*static_cast<const GraphicsBinding*>(info->next);*session=*output;
            return binding->type==graphics_binding_d3d12&&!binding->next&&binding->device&&binding->queue;
        }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    static bool read_swapchain(const SwapchainCreateInfo* info,Swapchain* output,Swapchain* value){
        __try{
            if(!output||!*output||!info||info->type!=swapchain_create_type||info->next)return false;
            *value=*output;return true;
        }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    static bool read_images(uint32_t capacity,uint32_t* count,Image* output,
                            uint32_t* size,ID3D12Resource* (&raw)[16]){
        __try{
            if(!count||!*count||*count>capacity||*count>16||!output)return false;
            *size=*count;
            for(uint32_t x=0;x<*size;x++){
                if(output[x].type!=image_d3d12||output[x].next||!output[x].texture)return false;
                raw[x]=output[x].texture;
            }
            return true;
        }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    static bool read_index(uint32_t* index,uint32_t* value){
        __try{if(!index)return false;*value=*index;return true;}
        __except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    static bool simple_release(const acquired_images::ReleaseInfo* info){
        __try{return info&&info->type==release_info_type&&!info->next;}
        __except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
    static bool simple_end(const xr_read::EndInfo* info){
        __try{return info&&info->type==xr_read::frame_end_info&&!info->next;}
        __except(EXCEPTION_EXECUTE_HANDLER){return false;}
    }
public:
    Bridge()=default;Bridge(const Bridge&)=delete;Bridge& operator=(const Bridge&)=delete;
    ~Bridge(){if(active_.load()==this)std::terminate();}
    // UEVR initializes plugins after creating its XR session, but before its
    // swapchains. Its public renderer data and XR graphics binding both use
    // the same D3D12 hook device/queue getters (saved PluginLoader.cpp and
    // D3D12Component.cpp). Recover that existing public session; still require
    // fresh observed create/enumerate/acquire/wait/copy/release transactions.
    bool adopt_existing_session(Session session,ID3D12Device* device,ID3D12CommandQueue* queue){
        std::lock_guard<std::recursive_mutex> guard(transaction_);
        if(!ready_.load()||disabled_||!session||!device||!queue||observed_sessions_||binding_||frame_open_)return false;
        for(const auto& c:chains_)if(c.handle)return false;
        Microsoft::WRL::ComPtr<ID3D12Device> actual;
        if(queue->GetDesc().Type!=D3D12_COMMAND_LIST_TYPE_DIRECT||FAILED(queue->GetDevice(IID_PPV_ARGS(&actual)))||actual.Get()!=device)return false;
        binding_.session=session;binding_.device=device;binding_.queue=queue;observed_sessions_=1;return true;
    }
    bool attach(const UEVR_PluginInitializeParam* api,Callbacks callbacks,HookApi injection={}){
        std::lock_guard<std::recursive_mutex> guard(transaction_);
        if(!api||!api->functions||!api->functions->register_inline_hook)return false;
        HMODULE module=GetModuleHandleW(L"UEVRBackend.dll");if(!module)return false;
        wchar_t path[32768]{};std::string hash;
        if(!GetModuleFileNameW(module,path,32768)||!boundary::file_hash(path,hash)||
           hash!=boundary::expected_hash||!guarded_image(reinterpret_cast<unsigned char*>(module)))return false;
        HMODULE own=nullptr;
        if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
              reinterpret_cast<LPCWSTR>(&pin_anchor),&own))return false;
        Bridge* empty=nullptr;if(!active_.compare_exchange_strong(empty,this))return false;
        backend_=reinterpret_cast<unsigned char*>(module);callbacks_=callbacks;
        hooks_=injection.install?injection:HookApi{install_from_api,const_cast<UEVR_PluginInitializeParam*>(api)};
        // Order matches xr_dispatch_guards::entries; all wrappers are guarded.
        const bool okay=
            install(0,reinterpret_cast<void*>(&on_acquire),acquire_)&&
            install(1,reinterpret_cast<void*>(&on_wait),wait_)&&
            install(2,reinterpret_cast<void*>(&on_release),release_)&&
            install(3,reinterpret_cast<void*>(&on_destroy_swapchain),destroy_swapchain_)&&
            install(4,reinterpret_cast<void*>(&on_begin_frame),begin_frame_)&&
            install(5,reinterpret_cast<void*>(&on_end_session),end_session_)&&
            install(6,reinterpret_cast<void*>(&on_create_session),create_session_)&&
            install(7,reinterpret_cast<void*>(&on_end_frame),end_frame_)&&
            install(8,reinterpret_cast<void*>(&on_create_swapchain),create_swapchain_)&&
            install(9,reinterpret_cast<void*>(&on_enumerate),enumerate_);
        ready_.store(okay,std::memory_order_release);
        if(!okay)disabled_=true; // Keep partial hooks and trampolines resident.
        return okay;
    }
    bool enabled(){std::lock_guard<std::recursive_mutex> guard(transaction_);
        return ready_.load()&&!disabled_&&binding_&&images_.mutation_enabled();}
    void disable(){std::lock_guard<std::recursive_mutex> guard(transaction_);disable_effect();}
    bool observed_image(ID3D12Resource* resource,acquired_images::Token& token,
                        uint64_t& frame,Binding& binding){
        std::lock_guard<std::recursive_mutex> guard(transaction_);
        if(!resource||!frame_open_||!frame_||observed_sessions_!=1||
           !effect(binding_.session))return false;
        std::optional<acquired_images::Token> match;
        for(const auto& c:chains_)if(c.handle&&c.session==binding_.session){
            for(const auto& candidate:{c.waited,c.held})if(candidate&&
               candidate->generation==c.generation&&candidate->index<c.count&&
               candidate->resource==resource&&c.images[candidate->index].Get()==resource){
                if(match&&!(*match==*candidate))return false;
                match=candidate;
            }
        }
        if(!match)return false;
        token=*match;frame=frame_;binding=binding_;return true;
    }
    bool pending_exact(const acquired_images::Token& token){
        std::lock_guard<std::recursive_mutex> guard(transaction_);
        if(!token||!committing_||disabled_||!binding_||!frame_)return false;
        const auto* c=chain(token.chain);if(!c||!c->held||!(*c->held==token)||
            c->session!=binding_.session||c->held_frame!=frame_||
            c->generation!=token.generation||token.index>=c->count||
            c->images[token.index].Get()!=token.resource)return false;
        const auto state=images_.state(token.chain);
        return state.pending&&!state.uncertain&&state.generation==token.generation;
    }
    static Result __stdcall on_create_session(Instance i,const SessionCreateInfo* info,Session* output){
        Bridge* b=active_;if(!b||!b->create_session_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        const Result result=b->create_session_(i,info,output);
        if(result!=0||!b->ready_||b->disabled_)return result;
        if(++b->observed_sessions_!=1){b->disable_effect();return result;} // Multiple sessions unsupported.
        GraphicsBinding binding{};Session created=nullptr;
        if(read_binding(info,output,&binding,&created)){
            Microsoft::WRL::ComPtr<ID3D12Device> queue_device;
            if(binding.queue->GetDesc().Type!=D3D12_COMMAND_LIST_TYPE_DIRECT||
               FAILED(binding.queue->GetDevice(IID_PPV_ARGS(&queue_device)))||
               queue_device.Get()!=binding.device){b->disable_effect();return result;}
            b->binding_.session=created;b->binding_.device=binding.device;b->binding_.queue=binding.queue;
        }
        return result;
    }
    static Result __stdcall on_create_swapchain(Session s,const SwapchainCreateInfo* info,Swapchain* output){
        Bridge* b=active_;if(!b||!b->create_swapchain_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        const Result result=b->create_swapchain_(s,info,output);
        if(result!=0||!b->effect(s))return result;
        Swapchain created=0;
        if(read_swapchain(info,output,&created)){
            if(b->chain(created)||!b->vacant()){b->disable_effect();return result;}
            auto* c=b->vacant();c->handle=created;c->session=s;
        }
        return result;
    }
    static Result __stdcall on_enumerate(Swapchain h,uint32_t capacity,uint32_t* count,Image* output){
        Bridge* b=active_;if(!b||!b->enumerate_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        const Result result=b->enumerate_(h,capacity,count,output);
        auto* c=b->chain(h);if(result!=0||!c||!b->effect(c->session)||!capacity)return result;
        ID3D12Resource* values[16]{};uint32_t size=0;
        if(!read_images(capacity,count,output,&size,values)){b->disable_effect();return result;}
        std::array<Microsoft::WRL::ComPtr<ID3D12Resource>,16> retained{};
        for(uint32_t x=0;x<size;x++)retained[x]=values[x];
        std::vector<ID3D12Resource*> raw(values,values+size);
        if(!b->flush_chain(*c)){b->disable_effect();return result;}
        auto generation=b->images_.register_images(h,raw,b->actual_release());
        if(!generation){b->disable_effect();return result;}
        for(auto& ref:c->images)ref.Reset();
        for(uint32_t x=0;x<size;x++)c->images[x]=std::move(retained[x]);
        c->count=size;c->generation=*generation;c->waited.reset();c->held.reset();
        return result;
    }
    static Result __stdcall on_acquire(Swapchain h,const Base* info,uint32_t* index){
        Bridge* b=active_;if(!b||!b->acquire_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        auto* c=b->chain(h);
        if(b->committing_)return runtime_failure;
        if(c&&c->count&&b->images_.state(h).pending&&!b->flush_chain(*c))return runtime_failure;
        const Result result=b->acquire_(h,info,index);
        if(result==0&&c&&c->count&&b->effect(c->session)){
            uint32_t value=0;
            if(!read_index(index,&value)||!b->images_.observe_acquire(h,result,value))b->disable_effect();
        }
        return result;
    }
    static Result __stdcall on_wait(Swapchain h,const Base* info){
        Bridge* b=active_;if(!b||!b->wait_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        auto* c=b->chain(h);
        if(b->committing_)return runtime_failure;
        if(c&&c->count&&!b->images_.before_wait(h,b->actual_release())){
            b->disable_effect();return runtime_failure;
        }
        if(c)b->clear_settled(*c);
        const Result result=b->wait_(h,info);
        if(c&&c->count&&b->effect(c->session)){
            c->waited=b->images_.observe_wait(h,result);
            if(result==0&&!c->waited)b->disable_effect();
        }
        return result;
    }
    static Result __stdcall on_release(Swapchain h,const acquired_images::ReleaseInfo* info){
        Bridge* b=active_;if(!b||!b->release_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        auto* c=b->chain(h);
        if(b->committing_)return runtime_failure;
        if(!c||!c->count)return b->release_(h,info);
        std::optional<acquired_images::Token> selected;
        if(b->effect(c->session)&&b->frame_open_&&b->frame_&&c->waited&&!c->held&&
           b->callbacks_.can_hold&&b->callbacks_.frame_sink&&simple_release(info)){
            try{if(b->callbacks_.can_hold(*c->waited,b->frame_,b->callbacks_.context))selected=c->waited;}
            catch(...){b->disable_effect();}
        }
        const auto outcome=b->images_.release(h,info,selected,b->actual_release());
        if(outcome.action==acquired_images::Action::deferred){
            c->held=selected;c->held_frame=b->frame_;c->waited.reset();return 0;
        }
        if(outcome.action==acquired_images::Action::forwarded){c->waited.reset();b->clear_settled(*c);
            return outcome.actual.value_or(runtime_failure);}
        b->disable_effect();return runtime_failure;
    }
    static Result __stdcall on_destroy_swapchain(Swapchain h){
        Bridge* b=active_;if(!b||!b->destroy_swapchain_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        if(b->committing_)return runtime_failure;
        auto* c=b->chain(h);if(c&&c->count&&!b->flush_chain(*c))return runtime_failure;
        const Result result=b->destroy_swapchain_(h);
        if(c&&(result==0||result==acquired_images::session_loss_pending)){
            if(!b->images_.retire_chain(h,b->actual_release()))b->disable_effect();
            *c={};
        }
        return result;
    }
    static Result __stdcall on_end_session(Session s){
        Bridge* b=active_;if(!b||!b->end_session_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        if(b->committing_||!b->flush_all())return runtime_failure;
        const Result result=b->end_session_(s);
        if(s==b->binding_.session&&(result==0||result==acquired_images::session_loss_pending))b->disable_effect();
        return result;
    }
    static Result __stdcall on_begin_frame(Session s,const Base* info){
        Bridge* b=active_;if(!b||!b->begin_frame_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        if(b->committing_||!b->images_.new_frame(b->actual_release()))return runtime_failure;
        for(auto& c:b->chains_)if(c.handle){
            b->clear_settled(c);
            if(c.waited)b->disable_effect(); // Prior frame left a waited image unsubmitted.
        }
        b->frame_open_=false;
        const Result result=b->begin_frame_(s,info);
        // A new successful frame may use ordinary presentation after disabling
        // the effect. Only retries of the failed frame remain blocked.
        if(result==0){b->fatal_frame_=false;if(b->effect(s)){++b->frame_;b->frame_open_=true;}}
        return result;
    }
    static Result __stdcall on_end_frame(Session s,const xr_read::EndInfo* info){
        Bridge* b=active_;if(!b||!b->end_frame_)return runtime_failure;
        std::lock_guard<std::recursive_mutex> lock(b->transaction_);
        if(b->committing_)return runtime_failure;
        if(b->fatal_frame_){(void)b->flush_all();return runtime_failure;}
        b->committing_=true;
        std::array<Held,16> held{};size_t count=0;
        bool release_failed=false;
        for(auto& c:b->chains_)if(c.handle&&c.held){
            const auto state=b->images_.state(c.handle);
            if(c.held->index>=c.count||!c.images[c.held->index]||c.session!=s||
               c.held_frame!=b->frame_||c.held->generation!=c.generation||
               c.held->resource!=c.images[c.held->index].Get()||!state.pending||
               state.generation!=c.generation||state.uncertain){
                release_failed=!b->disable_effect();break;
            }
            held[count++]={*c.held,c.images[c.held->index]};
        }
        b->frame_open_=false;
        FrameOutcome outcome=FrameOutcome::unchanged;
        if(count&&b->effect(s)&&simple_end(info)&&
           b->callbacks_.frame_sink&&b->images_.claim_end_frame()){
            try{outcome=b->callbacks_.frame_sink(s,info,held.data(),count,b->frame_,
                      b->binding_.device.Get(),b->binding_.queue.Get(),b->callbacks_.context);}
            catch(...){outcome=FrameOutcome::fatal;}
        }
        if(!b->flush_all()||release_failed){
            b->fatal_frame_=true;b->committing_=false;b->disable_effect();return runtime_failure;
        }
        if(outcome==FrameOutcome::fatal){
            // Submission cannot be rolled back. Controller retains resources
            // and fences until its actual queue completion, even on failure.
            b->fatal_frame_=true;b->committing_=false;b->disable_effect();
            return runtime_failure;
        }
        b->committing_=false;
        return b->end_frame_(s,info);
    }
};
} // namespace openxr_handoff
