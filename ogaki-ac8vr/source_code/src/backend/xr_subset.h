// Minimal Win64 OpenXR layouts shared by the presentation code. Keep field
// sizes, packing and type IDs ABI-compatible with OpenXR; these are not UObject
// layouts. Consumers validate layer types and counts before interpreting them.

// Minimal Win64 OpenXR ABI declarations used only to read submitted layers.
// Consumers use these declarations at verified OpenXR boundaries.
#pragma once
#include <cstdint>
namespace xr_read {
using Handle=void*;
struct Quaternion {float x,y,z,w;};
struct Vector3 {float x,y,z;};
struct Pose {Quaternion orientation;Vector3 position;};
struct Fov {float angleLeft,angleRight,angleUp,angleDown;};
struct Offset {int32_t x,y;};
struct Extent {int32_t width,height;};
struct Rect {Offset offset;Extent extent;};
struct SubImage {Handle swapchain;Rect imageRect;uint32_t imageArrayIndex;};
struct Layer {int32_t type;const void* next;uint64_t layerFlags;Handle space;};
struct ProjectionView {int32_t type;const void* next;Pose pose;Fov fov;SubImage subImage;};
struct Projection {int32_t type;const void* next;uint64_t layerFlags;Handle space;uint32_t viewCount;const ProjectionView* views;};
struct Quad {int32_t type;const void* next;uint64_t layerFlags;Handle space;int32_t eyeVisibility;SubImage subImage;Pose pose;float width,height;};
struct Cylinder {int32_t type;const void* next;uint64_t layerFlags;Handle space;int32_t eyeVisibility;SubImage subImage;Pose pose;float radius,centralAngle,aspectRatio;};
struct EndInfo {int32_t type;const void* next;int64_t displayTime;int32_t environmentBlendMode;uint32_t layerCount;const Layer* const* layers;};
using EndFn=int32_t(__stdcall*)(Handle,const EndInfo*);
using GetProcFn=int32_t(__stdcall*)(Handle,const char*,void**);
constexpr int32_t frame_end_info=12,projection=35,quad=36;
constexpr int32_t cylinder=1000017000;
static_assert(sizeof(void*)==8 && sizeof(EndInfo)==40 && sizeof(Layer)==32);
static_assert(sizeof(SubImage)==32 && sizeof(ProjectionView)==96 && sizeof(Projection)==48 && sizeof(Quad)==112);
static_assert(sizeof(Cylinder)==112);
}
