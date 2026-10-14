// Track OpenXR acquire/wait/release ownership and generation tokens.
// This bookkeeping does not itself grant a GPU write lease. The bridge must
// serialize validation, submission and release against lifecycle changes.

#pragma once
// Narrow bookkeeping for observed OpenXR swapchain image transactions. The
// host chooses the candidate and calls lifecycle flushes; no hooks or GPU work.
// The host must serialize its whole validation -> GPU submission -> release
// transaction against before_acquire, before_wait, disable, and lifecycle
// flushes. Per-method locking here is not a composition ownership lease.
#include <d3d12.h>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <limits>
#include <map>
#include <mutex>
#include <optional>
#include <vector>

namespace acquired_images {
using Swapchain = uint64_t; // OpenXR non-dispatchable XrSwapchain ABI.
using Result = int32_t;    // OpenXR XrResult ABI; only zero is success here.
constexpr Result success = 0;
constexpr Result session_loss_pending = 3;
struct ReleaseInfo { int32_t type = 0; const void* next = nullptr; };
static_assert(sizeof(ReleaseInfo)==16 && offsetof(ReleaseInfo,next)==8,"OpenXR release-info ABI mismatch");
struct ReleaseCall {
    Result (*function)(Swapchain,const ReleaseInfo*,void*) = nullptr;
    void* context = nullptr;
    explicit operator bool() const { return function!=nullptr; }
};
struct Token {
    Swapchain chain=0;
    uint64_t generation=0,serial=0;
    uint32_t index=0;
    ID3D12Resource* resource=nullptr; // weak; enumeration owner retains it.
    explicit operator bool() const { return chain&&generation&&serial&&resource; }
    bool operator==(const Token& rhs) const {
        return chain==rhs.chain&&generation==rhs.generation&&serial==rhs.serial&&
               index==rhs.index&&resource==rhs.resource;
    }
};
enum class Action { forwarded,deferred,blocked };
struct ReleaseOutcome { Action action=Action::blocked; std::optional<Result> actual; };
struct State { uint64_t generation=0;size_t outstanding=0;bool pending=false,uncertain=false,in_flight=false; };

class Bookkeeper {
    struct Entry { Token token{}; bool waited=false; };
    struct Chain {
        uint64_t generation=0;
        std::vector<ID3D12Resource*> images; // weak enumeration snapshot
        std::deque<Entry> fifo;
        std::optional<Token> pending;
        ReleaseInfo pending_info{};
        bool uncertain=false,in_flight=false;
    };
    static constexpr size_t max_chains=16,max_images=64,max_acquisitions=32;
    std::mutex mutex_;
    std::map<Swapchain,Chain> chains_;
    uint64_t next_generation_=0,next_serial_=0;
    int32_t release_type_;
    bool mutation_enabled_=true;
    bool frame_consumed_=false;
    static bool succeeded(Result result){return result==success;}
    static bool release_completed(Result result){return result==success||result==session_loss_pending;}
    bool valid_front(const Chain& chain,const Token& token) const {
        return !chain.fifo.empty()&&chain.fifo.front().token==token;
    }
    void uncertain(Chain& chain){chain.uncertain=true;mutation_enabled_=false;}
public:
    explicit Bookkeeper(int32_t release_structure_type):release_type_(release_structure_type){}
    Bookkeeper(const Bookkeeper&)=delete;Bookkeeper& operator=(const Bookkeeper&)=delete;

    // Register the exact indexed resources returned by image enumeration.
    // Recreating the same handle flushes a pending actual release first.
    std::optional<uint64_t> register_images(Swapchain chain,const std::vector<ID3D12Resource*>& images,
                                            ReleaseCall original){
        if(!chain||images.empty()||images.size()>max_images||
           std::any_of(images.begin(),images.end(),[](auto* p){return p==nullptr;})){
            std::lock_guard<std::mutex> guard(mutex_);mutation_enabled_=false;
            return std::nullopt;
        }
        if(!flush_chain(chain,original))return std::nullopt;
        std::lock_guard<std::mutex> guard(mutex_);
        if(!mutation_enabled_)return std::nullopt;
        auto it=chains_.find(chain);
        if(it!=chains_.end()&&(it->second.in_flight||it->second.pending||!it->second.fifo.empty())){
            uncertain(it->second);return std::nullopt;
        }
        if(it==chains_.end()&&chains_.size()>=max_chains){mutation_enabled_=false;return std::nullopt;}
        Chain replacement{};replacement.generation=++next_generation_;replacement.images=images;
        chains_[chain]=std::move(replacement);return next_generation_;
    }
    std::optional<Token> observe_acquire(Swapchain chain,Result result,uint32_t index){
        if(!succeeded(result))return std::nullopt;
        std::lock_guard<std::mutex> guard(mutex_);
        auto it=chains_.find(chain);
        if(it==chains_.end()){mutation_enabled_=false;return std::nullopt;}
        auto& c=it->second;
        if(!mutation_enabled_||c.uncertain||c.in_flight||c.pending||
           c.fifo.size()>=max_acquisitions||index>=c.images.size()||
           std::any_of(c.fifo.begin(),c.fifo.end(),[index](const Entry& e){return e.token.index==index;})||
           !c.images[index]||next_serial_==(std::numeric_limits<uint64_t>::max)()){
            uncertain(c);return std::nullopt;
        }
        Token token{chain,c.generation,++next_serial_,index,c.images[index]};
        c.fifo.push_back({token,false});return token;
    }
    std::optional<Token> observe_wait(Swapchain chain,Result result){
        std::lock_guard<std::mutex> guard(mutex_);
        auto it=chains_.find(chain);
        if(it==chains_.end()){mutation_enabled_=false;return std::nullopt;}
        auto& c=it->second;
        if(!succeeded(result)){uncertain(c);return std::nullopt;} // Includes XR_TIMEOUT_EXPIRED.
        if(!mutation_enabled_||c.uncertain||c.in_flight||
           std::any_of(c.fifo.begin(),c.fifo.end(),[](const Entry& e){return e.waited;})){
            uncertain(c);return std::nullopt;
        }
        for(auto& entry:c.fifo)if(!entry.waited){entry.waited=true;return entry.token;}
        uncertain(c);return std::nullopt;
    }
    // Explicit host-selected token must be the waited FIFO head. A deferred
    // outcome is provisional to the caller; actual completion occurs at flush.
    ReleaseOutcome release(Swapchain chain,const ReleaseInfo* info,
                           std::optional<Token> candidate,ReleaseCall original){
        if(!original)return {};
        {
            std::lock_guard<std::mutex> guard(mutex_);
            const auto it=chains_.find(chain);
            if(it!=chains_.end()&&it->second.pending&&candidate&&
               *it->second.pending==*candidate)return {}; // Duplicate selected call.
        }
        if(!flush_chain(chain,original))return {};
        Token front{};bool tracked=false;
        {
            std::lock_guard<std::mutex> guard(mutex_);
            auto it=chains_.find(chain);
            if(it!=chains_.end()){
                auto& c=it->second;
                if(c.in_flight||c.pending)return {};
                if(!c.fifo.empty()){front=c.fifo.front().token;tracked=true;}
                const bool eligible=candidate&&tracked&&valid_front(c,*candidate)&&c.fifo.front().waited&&
                    mutation_enabled_&&!c.uncertain&&info&&info->type==release_type_&&info->next==nullptr;
                if(eligible){
                    c.pending=*candidate;c.pending_info={info->type,nullptr};
                    return {Action::deferred,std::nullopt};
                }
                c.in_flight=true;
            }else mutation_enabled_=false; // Unknown chain: forward unchanged, never defer.
        }
        // Forward the exact caller pointer once and outside the lock.
        std::optional<Result> actual;
        try{actual=original.function(chain,info,original.context);}catch(...){actual.reset();}
        {
            std::lock_guard<std::mutex> guard(mutex_);
            auto it=chains_.find(chain);
            if(it!=chains_.end()){
                auto& c=it->second;c.in_flight=false;
                if(actual&&release_completed(*actual)&&tracked&&valid_front(c,front)){
                    c.fifo.pop_front();
                    if(*actual==session_loss_pending)uncertain(c);
                }else uncertain(c);
            }
        }
        return {Action::forwarded,actual};
    }
    bool flush_chain(Swapchain chain,ReleaseCall original){
        ReleaseInfo info{};Token token{};
        {
            std::lock_guard<std::mutex> guard(mutex_);
            auto it=chains_.find(chain);if(it==chains_.end()||!it->second.pending)return true;
            auto& c=it->second;
            if(c.in_flight||!original){uncertain(c);return false;}
            token=*c.pending;info=c.pending_info;c.in_flight=true;
        }
        std::optional<Result> actual;
        try{actual=original.function(chain,&info,original.context);}catch(...){actual.reset();}
        std::lock_guard<std::mutex> guard(mutex_);
        auto it=chains_.find(chain);if(it==chains_.end())return false;
        auto& c=it->second;c.in_flight=false;
        if(actual&&release_completed(*actual)&&c.pending&&*c.pending==token&&valid_front(c,token)){
            c.fifo.pop_front();c.pending.reset();
            if(*actual==session_loss_pending)uncertain(c);
            return true;
        }
        uncertain(c);return false; // Never claim completion after failed actual release.
    }
    bool flush_all(ReleaseCall original){
        std::vector<Swapchain> keys;
        {std::lock_guard<std::mutex> guard(mutex_);for(const auto& pair:chains_)if(pair.second.pending)keys.push_back(pair.first);}
        bool okay=true;for(auto chain:keys)if(!flush_chain(chain,original))okay=false;return okay;
    }
    bool before_acquire(Swapchain chain,ReleaseCall original){return flush_chain(chain,original);}
    // OpenXR requires the previous waited image released before another wait.
    bool before_wait(Swapchain chain,ReleaseCall original){
        if(!flush_chain(chain,original))return false;
        std::lock_guard<std::mutex> guard(mutex_);
        const auto it=chains_.find(chain);if(it==chains_.end())return true;
        return std::none_of(it->second.fifo.begin(),it->second.fifo.end(),
                            [](const Entry& e){return e.waited;});
    }
    // Claim once before optional owned composition at xrEndFrame entry. A
    // repeated xrEndFrame attempt cannot perform that composition twice.
    bool claim_end_frame(){
        std::lock_guard<std::mutex> guard(mutex_);
        if(frame_consumed_||!mutation_enabled_)return false;
        frame_consumed_=true;return true;
    }
    bool at_end_frame(ReleaseCall original){return flush_all(original);}
    bool new_frame(ReleaseCall original){
        if(!flush_all(original))return false;
        std::lock_guard<std::mutex> guard(mutex_);
        frame_consumed_=false;return true;
    }
    bool session_stop(ReleaseCall original){
        {std::lock_guard<std::mutex> guard(mutex_);mutation_enabled_=false;}
        return flush_all(original);
    }
    bool disable(ReleaseCall original){
        {std::lock_guard<std::mutex> guard(mutex_);mutation_enabled_=false;}
        return flush_all(original);
    }
    bool retire_chain(Swapchain chain,ReleaseCall original){
        if(!flush_chain(chain,original))return false;
        std::lock_guard<std::mutex> guard(mutex_);
        auto it=chains_.find(chain);if(it==chains_.end())return true;
        if(it->second.in_flight||it->second.pending||!it->second.fifo.empty()){
            uncertain(it->second);return false;
        }
        chains_.erase(it);return true;
    }
    State state(Swapchain chain){
        std::lock_guard<std::mutex> guard(mutex_);State s{};
        const auto it=chains_.find(chain);if(it==chains_.end())return s;
        const auto& c=it->second;s.generation=c.generation;s.outstanding=c.fifo.size();
        s.pending=c.pending.has_value();s.uncertain=c.uncertain;s.in_flight=c.in_flight;return s;
    }
    bool mutation_enabled(){std::lock_guard<std::mutex> guard(mutex_);return mutation_enabled_;}
};
} // namespace acquired_images
