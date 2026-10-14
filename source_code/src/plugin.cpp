// UEVR entry point for the single distributed DLL. build.ps1 gives each module
// its own internal initializer name; only this file exports the public API.
// Modules report initialization failures independently so unrelated fixes can run.

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <cstring>
#include "../vendor/uevr/plugin-api.h"
extern "C" bool ac8_cinematic_initialize(const UEVR_PluginInitializeParam*);
extern "C" bool ac8_escort_initialize(const UEVR_PluginInitializeParam*);
extern "C" bool ac8_glow_initialize(const UEVR_PluginInitializeParam*);
extern "C" bool ac8_warning_initialize(const UEVR_PluginInitializeParam*);
extern "C" bool ac8_arrow_initialize(const UEVR_PluginInitializeParam*);
extern "C" bool ac8_lock_initialize(const UEVR_PluginInitializeParam*);

extern "C" __declspec(dllexport) void uevr_plugin_required_version(UEVR_PluginVersion* v){if(v)*v={UEVR_PLUGIN_VERSION_MAJOR,UEVR_PLUGIN_VERSION_MINOR,UEVR_PLUGIN_VERSION_PATCH};}
extern "C" __declspec(dllexport) bool uevr_plugin_initialize(const UEVR_PluginInitializeParam* p){
 if(!p||!p->functions||!p->functions->log_info||!p->callbacks||!p->callbacks->on_custom_event)return false;
 try{const bool ok=ac8_cinematic_initialize(p);p->functions->log_info("[AC8 VR] cinematic initialized=%d",ok);}catch(...){p->functions->log_info("[AC8 VR] cinematic initialization failed");}
 try{const bool ok=ac8_escort_initialize(p);p->functions->log_info("[AC8 VR] escort initialized=%d",ok);}catch(...){p->functions->log_info("[AC8 VR] escort initialization failed");}
 try{const bool ok=ac8_glow_initialize(p);p->functions->log_info("[AC8 VR] glow initialized=%d",ok);}catch(...){p->functions->log_info("[AC8 VR] glow initialization failed");}
 try{const bool ok=ac8_warning_initialize(p);p->functions->log_info("[AC8 VR] warning initialized=%d",ok);}catch(...){p->functions->log_info("[AC8 VR] warning initialization failed");}
 try{const bool ok=ac8_arrow_initialize(p);p->functions->log_info("[AC8 VR] arrow initialized=%d",ok);}catch(...){p->functions->log_info("[AC8 VR] arrow initialization failed");}
 try{const bool ok=ac8_lock_initialize(p);p->functions->log_info("[AC8 VR] lock initialized=%d",ok);}catch(...){p->functions->log_info("[AC8 VR] lock initialization failed");}
 return true;
}
