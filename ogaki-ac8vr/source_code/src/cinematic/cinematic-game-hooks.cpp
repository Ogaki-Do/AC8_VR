// Register presentation, pause navigation, world-label and bomb-render hooks.
// Window input only queues F7; Lua dispatch occurs on the engine callback.
// Ready/failure events let Lua avoid taking UI ownership without native support.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <atomic>
#include <sstream>
#include <Xinput.h>
#include "../../vendor/uevr/plugin-api.h"
#include "mask.h"
#include "camera_lock.h"
#include "projection_hook.h"
#include "object-access.h"
#include "world_target_layout.h"
#include "pause-navigation.h"
#include "bomb_render.h"

static const UEVR_PluginInitializeParam* api=nullptr;
static std::atomic<bool> was_down{false};
static std::atomic<bool> pending{false};


static bool camera_available=false;
static bool message(void* window,unsigned int msg,unsigned long long key,long long flags) {

    if(key!=VK_F7) return true;
    DWORD process=0;
    GetWindowThreadProcessId(static_cast<HWND>(window),&process);
    if(process!=GetCurrentProcessId()) return true;

    if(msg==WM_KEYDOWN || msg==WM_SYSKEYDOWN) {
        // Bit30 marks OS auto-repeat. Queue work without calling Lua on the window thread.
        if((flags & (1LL<<30))==0 && !was_down.exchange(true)) pending=true;
    } else if(msg==WM_KEYUP || msg==WM_SYSKEYUP) {
        was_down=false;
    }
    return true; // Preserve the game's input handling.
}
static void tick(UEVR_UGameEngineHandle,float) {
    static ULONGLONG next_mask_check=0;
    if(cinema_mask::host && GetTickCount64()>=next_mask_check) {
        next_mask_check=GetTickCount64()+2000;
        cinema_mask::attach();
        if(cinematic_projection::installed)api->functions->dispatch_lua_event("AC8_CinematicProjection_Ready","ready");

        if(cinema_mask::attached && !cinema_mask::failed) {
            if(camera_available)api->functions->dispatch_lua_event("AC8_CinematicCamera_Ready","ready");
            api->functions->dispatch_lua_event("AC8_CinematicMask_Ready","ready");
        }
        if(cinema_mask::failed) api->functions->dispatch_lua_event("AC8_CinematicMask_Failed","failed");
    }
    const bool down=(GetAsyncKeyState(VK_F7)&0x8000)!=0;
    const bool previous=was_down.exchange(down);
    if(down && !previous) {
        const auto foreground=GetForegroundWindow();
        DWORD process=0;
        GetWindowThreadProcessId(foreground,&process);
        if(process==GetCurrentProcessId()) {
            pending=true;
        }
    }
    if(pending.exchange(false)) {
        api->functions->dispatch_lua_event("AC8_CinematicIntent_F7", "toggle");
    }


}
extern "C"  void uevr_plugin_required_version(UEVR_PluginVersion* version) {
    version->major=UEVR_PLUGIN_VERSION_MAJOR;
    version->minor=UEVR_PLUGIN_VERSION_MINOR;
    version->patch=UEVR_PLUGIN_VERSION_PATCH;
}
extern "C"  bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* param) {
    if(!param || !param->version || param->version->major!=UEVR_PLUGIN_VERSION_MAJOR ||
       param->version->minor<UEVR_PLUGIN_VERSION_MINOR || !param->functions || !param->functions->log_info || !param->functions->dispatch_lua_event ||
       !param->functions->register_inline_hook || !param->callbacks || !param->callbacks->on_message || !param->callbacks->on_custom_event ||
       !param->sdk || !param->sdk->callbacks || !param->sdk->callbacks->on_pre_engine_tick) return false;
    api=param;
    cinema_mask::host=param;
    cinematic_camera::host=param;
    auto sdk=param->sdk;
    if(sdk->uobject&&sdk->uobject->get_bool_property&&sdk->ustruct&&sdk->fname&&sdk->ffield&&sdk->ffield_class&&sdk->fproperty&&sdk->farrayproperty&&sdk->fstructproperty&&sdk->uscriptstruct&&sdk->uobject_array&&sdk->uobject_hook&&sdk->functions&&sdk->callbacks->on_post_engine_tick){
        object_access::host=param;
        pause_navigation::host=param;param->callbacks->on_custom_event(pause_navigation::control);sdk->callbacks->on_pre_engine_tick(pause_navigation::tick);
    }
    was_down=(GetAsyncKeyState(VK_F7)&0x8000)!=0;
    const bool registered=api->sdk->callbacks->on_pre_engine_tick(tick);
    const bool input_registered=api->callbacks->on_message(message);
    const bool mask_registered=api->callbacks->on_custom_event(cinema_mask::control);
    const bool camera_control=api->callbacks->on_custom_event(cinematic_camera::control);
    const bool camera_early=api->sdk->callbacks->on_early_calculate_stereo_view_offset&&api->sdk->callbacks->on_early_calculate_stereo_view_offset(cinematic_camera::early);
    const bool camera_post=api->sdk->callbacks->on_post_calculate_stereo_view_offset&&api->sdk->callbacks->on_post_calculate_stereo_view_offset(cinematic_camera::post);
    camera_available=camera_control&&camera_early&&camera_post;
    cinematic_projection::verify();
    if(!world_target_layout::initialize(param))param->functions->log_error("[AC8] World target layout build/schema guards failed; native metrics forwarded unchanged");
    bomb_projection::initialize(param);
    bomb_circle::initialize(param);
    if(!bomb_render::initialize(param))param->functions->log_error("[AC8] Accepted bomb rendering support could not initialize");
    native_fade::initialize();api->callbacks->on_custom_event(native_fade::control);
    const bool projection_control=api->callbacks->on_custom_event(cinematic_projection::control);
    const bool projection_callback=api->sdk->callbacks->on_early_calculate_stereo_view_offset(cinematic_projection::early);
    if(!projection_control||!projection_callback)cinematic_projection::allowed=false;
    api->functions->log_info("[Cinematic Hotkey] Initialization; engine=%d keyboard messages=%d",registered,input_registered);
    return registered && input_registered && mask_registered;
}
