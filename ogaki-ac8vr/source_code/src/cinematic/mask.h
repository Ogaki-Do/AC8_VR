// OpenXR presentation and transition compositor. Owns auxiliary images for
// cinematic windows, hangar coverage and loading/fade cover. Image acquisition,
// GPU completion and release must stay paired, including failure paths.
// Lua supplies intent; native code uses the current submission geometry.

#pragma once
#include <d3d12.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <array>
#include <mutex>
#include <fstream>
#include <filesystem>
#include <cstdlib>
#include "mask_geometry.h"
#include "native_fade.h"
#include "movie_window.h"
#include "lens_projection.h"
#include "../backend/backend_boundary.h"
namespace cinema_mask {
using Microsoft::WRL::ComPtr;
using Result=int32_t;using Handle=void*;
struct Base {int32_t type;const void* next;};
struct Create {int32_t type;const void* next;uint64_t flags,usage;int64_t format;uint32_t samples,width,height,faces,arrays,mips;};
struct Image {int32_t type;void* next;ID3D12Resource* resource;};
struct Wait {int32_t type;const void* next;int64_t timeout;};
static_assert(sizeof(Create)==64 && sizeof(Image)==24 && sizeof(Wait)==24);
inline const UEVR_PluginInitializeParam* host=nullptr;
inline std::atomic<bool> requested=false;
inline std::atomic<bool> full_view=false;
inline std::atomic<bool> hangar_crop=false;
inline std::atomic<float> full_view_coverage=2.0f;
inline std::atomic<float> full_view_vertical=1.25f;
inline std::atomic<uint64_t> full_view_frames=0;
inline std::atomic<const char*> state="waiting_session";
inline std::atomic<uint64_t> frames=0,masked=0,skipped=0;
inline std::atomic<uint64_t> activation=0;
inline uint64_t anchored_activation=0;
inline Window anchored_window{};
inline std::array<xr_read::ProjectionView,2> movie_reference{};
inline float anchored_distance=0;
inline std::atomic<float> shown_width=0,shown_height=0,shown_distance=0;
inline std::atomic<float> frame_size_override=0,frame_distance_override=0;
inline std::recursive_mutex lock;
inline xr_read::EndFn original_end=nullptr;
inline Result(__stdcall* create_chain)(Handle,const Create*,Handle*)=nullptr;
inline Result(__stdcall* enumerate_images)(Handle,uint32_t,uint32_t*,Image*)=nullptr;
inline Result(__stdcall* acquire)(Handle,const Base*,uint32_t*)=nullptr;
inline Result(__stdcall* wait_image)(Handle,const Wait*)=nullptr;
inline Result(__stdcall* release)(Handle,const Base*)=nullptr;
inline Result(__stdcall* formats)(Handle,uint32_t,uint32_t*,int64_t*)=nullptr;
inline Handle session=nullptr,chain=nullptr;
inline ComPtr<ID3D12Device> device;
inline ComPtr<ID3D12CommandQueue> queue;
inline ComPtr<ID3D12DescriptorHeap> rtvs;
inline ComPtr<ID3D12Fence> fence;
inline ComPtr<ID3D12RootSignature> root;
inline ComPtr<ID3D12PipelineState> pipeline;
struct Slot {ID3D12Resource* resource=nullptr;ComPtr<ID3D12CommandAllocator> allocator;ComPtr<ID3D12GraphicsCommandList> commands;ComPtr<ID3D12Resource> vertices;uint64_t fence_value=0;};
inline std::array<Slot,16> slots;
inline uint32_t image_count=0,rtv_stride=0,index=0;
inline bool acquired=false,waited=false,attempted=false;
inline std::atomic<bool> failed=false,attached=false;
inline uint64_t serial=0;
struct Transition {float opacity=0;bool loading=false;std::array<float,3> color{};std::array<float,4> bounds{{0,0,1,1}};};
inline Transition transition{};
inline std::atomic<uint64_t> transition_frames=0;
constexpr int pixels=1024;
inline void check(HRESULT r){if(FAILED(r))throw r;}
inline float ui_distance() {
    if(!host->vr||!host->vr->get_mod_value)return 0;
    char text[128]{};host->vr->get_mod_value("UI_Distance",text,128);const float v=static_cast<float>(std::strtod(text,nullptr));
    return std::isfinite(v)&&v>0?v:0;
}
inline void fail(const char* why){failed=true;state=why;requested=false;host->functions->log_error("[Cinematic Mask] %s",why);}
inline void create_pipeline(DXGI_FORMAT format) {
    D3D12_ROOT_PARAMETER parameter{};parameter.ParameterType=D3D12_ROOT_PARAMETER_TYPE_CBV;parameter.ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
    D3D12_ROOT_SIGNATURE_DESC rd{};rd.NumParameters=1;rd.pParameters=&parameter;
    ComPtr<ID3DBlob> blob,error,vs,ps;check(D3D12SerializeRootSignature(&rd,D3D_ROOT_SIGNATURE_VERSION_1,&blob,&error));check(device->CreateRootSignature(0,blob->GetBufferPointer(),blob->GetBufferSize(),IID_PPV_ARGS(&root)));
    const char* source=
        "cbuffer C:register(b0){float4 c[6];}"
        "float4 vertex(uint id:SV_VertexID):SV_Position{float2 p=float2((id<<1)&2,id&2);return float4(p*float2(2,-2)+float2(-1,1),0,1);}"
        "float4 pixel(float4 p:SV_Position):SV_Target{if(c[4].y>1.5)return float4(0,0,0,c[4].x);float2 uv=p.xy/c[2].w;float3 ray=c[3].xyz+c[1].xyz*uv.x+c[2].xyz*uv.y;"
        "float t=-c[0].z/(abs(ray.z)>1e-8?ray.z:1e-8);float2 hit=c[0].xy+t*ray.xy;float2 edge=float2(c[0].w,c[1].w)-abs(hit);"
        "if(c[4].z>0.5){float A=dot(ray.xz,ray.xz),B=2*dot(c[0].xz,ray.xz),C=dot(c[0].xz,c[0].xz)-c[4].w*c[4].w;float D=B*B-4*A*C;"
        "if(A<1e-12||D<0)t=-1;else{float2 roots=float2(-B-sqrt(D),-B+sqrt(D))/(2*A);t=roots.x>0?roots.x:roots.y;}"
        "float3 cp=c[0].xyz+t*ray;hit=float2(c[4].w*atan2(cp.x,-cp.z)-c[3].w,cp.y-c[5].w);edge=float2(c[0].w,c[1].w)-abs(hit);}"
        "float2 slope=max(fwidth(hit)*1,float2(1e-6,1e-6));edge-=slope*(c[4].y>0.5?0:4);float coverage=saturate(min(edge.x/slope.x,edge.y/slope.y)+0.5);"
        "if(t<=0||abs(ray.z)<=1e-8)coverage=0;float a=(1-coverage)*(c[4].y>0.5?c[4].x:1);return float4(0,0,0,a);}";
    check(D3DCompile(source,std::strlen(source),nullptr,nullptr,nullptr,"vertex","vs_5_0",D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS,0,&vs,&error));check(D3DCompile(source,std::strlen(source),nullptr,nullptr,nullptr,"pixel","ps_5_0",D3DCOMPILE_ENABLE_STRICTNESS|D3DCOMPILE_WARNINGS_ARE_ERRORS,0,&ps,&error));
    D3D12_GRAPHICS_PIPELINE_STATE_DESC p{};p.pRootSignature=root.Get();p.VS={vs->GetBufferPointer(),vs->GetBufferSize()};p.PS={ps->GetBufferPointer(),ps->GetBufferSize()};
    auto& blend=p.BlendState.RenderTarget[0];blend.RenderTargetWriteMask=D3D12_COLOR_WRITE_ENABLE_ALL;blend.SrcBlend=blend.SrcBlendAlpha=D3D12_BLEND_ONE;blend.DestBlend=blend.DestBlendAlpha=D3D12_BLEND_ZERO;blend.BlendOp=blend.BlendOpAlpha=D3D12_BLEND_OP_ADD;blend.LogicOp=D3D12_LOGIC_OP_NOOP;
    p.RasterizerState.FillMode=D3D12_FILL_MODE_SOLID;p.RasterizerState.CullMode=D3D12_CULL_MODE_NONE;p.RasterizerState.DepthClipEnable=TRUE;
    p.DepthStencilState.DepthEnable=FALSE;p.DepthStencilState.DepthFunc=D3D12_COMPARISON_FUNC_LESS;p.DepthStencilState.StencilEnable=FALSE;p.SampleMask=UINT_MAX;p.PrimitiveTopologyType=D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;p.NumRenderTargets=1;p.RTVFormats[0]=format;p.SampleDesc.Count=1;
    check(device->CreateGraphicsPipelineState(&p,IID_PPV_ARGS(&pipeline)));
}
inline bool initialize_images(Handle s) {
    session=s;
    device=static_cast<ID3D12Device*>(host->renderer->device);
    queue=static_cast<ID3D12CommandQueue*>(host->renderer->command_queue);
    if(!device||!queue||queue->GetDesc().Type!=D3D12_COMMAND_LIST_TYPE_DIRECT)return false;
    ComPtr<ID3D12Device> actual;check(queue->GetDevice(IID_PPV_ARGS(&actual)));if(actual.Get()!=device.Get())return false;
    std::array<int64_t,64> supported{};uint32_t n=0;
    if(formats(s,0,&n,nullptr)!=0||!n||n>supported.size()||formats(s,n,&n,supported.data())!=0)return false;
    DXGI_FORMAT fmt=DXGI_FORMAT_UNKNOWN;
    for(auto candidate:{DXGI_FORMAT_R8G8B8A8_UNORM_SRGB,DXGI_FORMAT_B8G8R8A8_UNORM_SRGB,DXGI_FORMAT_R8G8B8A8_UNORM,DXGI_FORMAT_B8G8R8A8_UNORM})
        if(std::find(supported.begin(),supported.begin()+n,static_cast<int64_t>(candidate))!=supported.begin()+n){fmt=candidate;break;}
    if(fmt==DXGI_FORMAT_UNKNOWN)return false;
    const Create c{9,nullptr,0,1|32,fmt,1,pixels,pixels,1,2,1};
    if(create_chain(s,&c,&chain)!=0||!chain||enumerate_images(chain,0,&image_count,nullptr)!=0||!image_count||image_count>slots.size())return false;
    std::array<Image,16> images{};for(auto& image:images)image.type=1000028001;
    if(enumerate_images(chain,image_count,&image_count,images.data())!=0)return false;
    D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;hd.NumDescriptors=image_count*2;
    check(device->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&rtvs)));rtv_stride=device->GetDescriptorHandleIncrementSize(hd.Type);
    check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)));
    create_pipeline(fmt);
    for(unsigned i=0;i<image_count;++i) {
        auto& slot=slots[i];slot.resource=images[i].resource;if(!slot.resource)return false;
        const auto desc=slot.resource->GetDesc();
        if(desc.Width!=pixels||desc.Height!=pixels||desc.DepthOrArraySize!=2||desc.SampleDesc.Count!=1)return false;
        check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&slot.allocator)));
        check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,slot.allocator.Get(),nullptr,IID_PPV_ARGS(&slot.commands)));check(slot.commands->Close());
        for(unsigned eye=0;eye<2;++eye){D3D12_RENDER_TARGET_VIEW_DESC v{};v.Format=fmt;v.ViewDimension=D3D12_RTV_DIMENSION_TEXTURE2DARRAY;v.Texture2DArray.FirstArraySlice=eye;v.Texture2DArray.ArraySize=1;
            device->CreateRenderTargetView(slot.resource,&v,{rtvs->GetCPUDescriptorHandleForHeapStart().ptr+size_t(i*2+eye)*rtv_stride});}
    }
    state="ready";return true;
}
inline bool draw(const std::array<Aperture,2>& holes,const std::array<std::array<Clip,6>,2>* vertices=nullptr) {
    if(!acquired){const Base a{55,nullptr};if(acquire(chain,&a,&index)!=0||index>=image_count){fail("acquire_failed");return false;}acquired=true;}
    const Wait w{56,nullptr,0};const auto wr=wait_image(chain,&w);
    if(wr==1){state="waiting_mask_image";return false;}
    if(wr!=0){fail("wait_failed");return false;}
    waited=true;
    const Base r{57,nullptr};auto& slot=slots[index];
    if(fence->GetCompletedValue()==UINT64_MAX){fail("device_removed");return false;}
    if(fence->GetCompletedValue()<slot.fence_value){if(release(chain,&r)!=0)fail("busy_release_failed");acquired=waited=false;state="gpu_busy_skipped";return false;}
    if(vertices) {
        if(!slot.vertices){D3D12_HEAP_PROPERTIES hp{};hp.Type=D3D12_HEAP_TYPE_UPLOAD;D3D12_RESOURCE_DESC desc{};desc.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;desc.Width=512;desc.Height=1;desc.DepthOrArraySize=1;desc.MipLevels=1;desc.SampleDesc.Count=1;desc.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
            check(device->CreateCommittedResource(&hp,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&slot.vertices)));}
        unsigned char* data=nullptr;check(slot.vertices->Map(0,nullptr,reinterpret_cast<void**>(&data)));for(unsigned eye=0;eye<2;++eye)std::memcpy(data+eye*256,(*vertices)[eye].data(),sizeof(Clip)*6);slot.vertices->Unmap(0,nullptr);
    }
    check(slot.allocator->Reset());check(slot.commands->Reset(slot.allocator.Get(),nullptr));
    // OpenXR D3D12 guarantees RENDER_TARGET after wait and requires it at release.
    constexpr float black[4]={0,0,0,1},transparent[4]={0,0,0,0};
    for(unsigned eye=0;eye<2;++eye){const D3D12_CPU_DESCRIPTOR_HANDLE target{rtvs->GetCPUDescriptorHandleForHeapStart().ptr+size_t(index*2+eye)*rtv_stride};
        slot.commands->ClearRenderTargetView(target,black,0,nullptr);
        if(vertices){const D3D12_VIEWPORT viewport{0,0,float(pixels),float(pixels),0,1};const D3D12_RECT scissor{0,0,pixels,pixels};slot.commands->SetPipelineState(pipeline.Get());slot.commands->SetGraphicsRootSignature(root.Get());slot.commands->SetGraphicsRootConstantBufferView(0,slot.vertices->GetGPUVirtualAddress()+eye*256);slot.commands->RSSetViewports(1,&viewport);slot.commands->RSSetScissorRects(1,&scissor);slot.commands->OMSetRenderTargets(1,&target,FALSE,nullptr);slot.commands->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);slot.commands->DrawInstanced(3,1,0,0);}
        else{const auto& h=holes[eye];const D3D12_RECT rect{h.left,h.top,h.right,h.bottom};slot.commands->ClearRenderTargetView(target,transparent,1,&rect);}}
    check(slot.commands->Close());ID3D12CommandList* list=slot.commands.Get();queue->ExecuteCommandLists(1,&list);
    check(queue->Signal(fence.Get(),++serial));slot.fence_value=serial;
    const auto result=release(chain,&r);acquired=waited=false;if(result!=0){fail("release_failed");return false;}return true;
}
inline Result transition_frame(Handle s,const xr_read::EndInfo* info,const xr_read::Projection* source_override=nullptr){
    const xr_read::Projection* source=source_override;unsigned source_index=0;
    if(!source)for(unsigned i=0;i<info->layerCount;++i)if(info->layers[i]&&info->layers[i]->type==35){if(source)return original_end(s,info);source=reinterpret_cast<const xr_read::Projection*>(info->layers[i]);source_index=i;}
    if(!source||!source->space||source->viewCount!=2||!source->views)return original_end(s,info);
    Window window{};bool found=false,curved=false;xr_read::Cylinder cylinder{};
    if(!transition.loading){
        for(unsigned i=0;i<info->layerCount;++i){const auto* layer=info->layers[i];if(!layer||layer->space!=source->space||(layer->type!=xr_read::quad&&layer->type!=xr_read::cylinder))continue;
            const auto& sub=layer->type==xr_read::cylinder?reinterpret_cast<const xr_read::Cylinder*>(layer)->subImage:reinterpret_cast<const xr_read::Quad*>(layer)->subImage;
            if(host->vr&&host->vr->get_ui_width&&host->vr->get_ui_height&&(sub.imageRect.extent.width!=static_cast<int>(host->vr->get_ui_width())||sub.imageRect.extent.height!=static_cast<int>(host->vr->get_ui_height())))continue;
            if(flat_window(layer,window)){found=true;if(layer->type==xr_read::cylinder){curved=true;cylinder=*reinterpret_cast<const xr_read::Cylinder*>(layer);}break;}}
        // Refuse unknown mapping instead of darkening the original fade twice.
        if(!found)return original_end(s,info);
        const auto& b=transition.bounds;
        if(curved)window.pose=cylinder.pose;
        else{const auto offset=rotate(window.pose.orientation,{((b[0]+b[2])*0.5f-0.5f)*window.width,(0.5f-(b[1]+b[3])*0.5f)*window.height,0});
            window.pose.position.x+=offset.x;window.pose.position.y+=offset.y;window.pose.position.z+=offset.z;}
        window.width*=b[2]-b[0];window.height*=b[3]-b[1];
    }
    std::array<Aperture,2> holes{};
    std::array<std::array<Clip,6>,2> parameters{};
    for(unsigned eye=0;eye<2;++eye){
        if(!aperture(source->views[eye].fov,pixels,holes[eye]))return original_end(s,info);
        parameters[eye]=window_parameters(window,source->views[eye],pixels);
        parameters[eye][4]={transition.opacity,transition.loading?2.0f:1.0f,0,0};
        parameters[eye][5]={transition.color[0],transition.color[1],transition.color[2],0};
        if(curved){const float width=cylinder.radius*cylinder.centralAngle,height=width/cylinder.aspectRatio;
            parameters[eye][4].z=1;parameters[eye][4].w=cylinder.radius;
            parameters[eye][3].w=((transition.bounds[0]+transition.bounds[2])*0.5f-0.5f)*width;
            parameters[eye][5].w=(0.5f-(transition.bounds[1]+transition.bounds[3])*0.5f)*height;}
    }
    try{if(!chain&&!initialize_images(s)){fail("transition_initialization_failed");return original_end(s,info);}if(!draw(holes,&parameters))return original_end(s,info);}catch(...){fail("transition_gpu_failed");return original_end(s,info);}
    std::array<xr_read::ProjectionView,2> views{mask_view(source->views[0],chain,0,pixels),mask_view(source->views[1],chain,1,pixels)};
    const xr_read::Projection cover{35,nullptr,2,source->space,2,views.data()};std::array<const xr_read::Layer*,16> layers{};unsigned count=0;
    for(unsigned i=0;i<info->layerCount;++i){layers[count++]=info->layers[i];if(transition.loading&&i==source_index)layers[count++]=reinterpret_cast<const xr_read::Layer*>(&cover);}
    // Loading hides the scene below its UI. Fade extension lies outside the
    // existing UI frame, so the center keeps precisely the authored opacity.
    if(!transition.loading)layers[count++]=reinterpret_cast<const xr_read::Layer*>(&cover);
    auto output=*info;output.layerCount=count;output.layers=layers.data();const auto result=original_end(s,&output);if(result>=0)++transition_frames;return result;
}
// Reuse the working stereo movie presentation, with each complete eye image
// expanded to its original FOV. Original curved UI layers pass through intact.
inline Result full_view_frame(Handle s,const xr_read::EndInfo* info){
    const xr_read::Projection* source=nullptr;
    for(unsigned i=0;i<info->layerCount;++i)if(info->layers[i]&&info->layers[i]->type==35){if(source)return original_end(s,info);source=reinterpret_cast<const xr_read::Projection*>(info->layers[i]);}
    if(!source||!source->space||source->viewCount!=2||!source->views)return original_end(s,info);
    const auto epoch=activation.load();
    if(anchored_activation!=epoch||anchored_window.space!=source->space){
        Window frame{};bool found=false;
        for(unsigned i=0;i<info->layerCount;++i){const auto* layer=info->layers[i];if(!layer||layer->space!=source->space||(layer->type!=xr_read::quad&&layer->type!=xr_read::cylinder))continue;
            const auto& sub=layer->type==xr_read::quad?reinterpret_cast<const xr_read::Quad*>(layer)->subImage:reinterpret_cast<const xr_read::Cylinder*>(layer)->subImage;
            if(host->vr&&host->vr->get_ui_width&&host->vr->get_ui_height&&(sub.imageRect.extent.width!=static_cast<int>(host->vr->get_ui_width())||sub.imageRect.extent.height!=static_cast<int>(host->vr->get_ui_height())))continue;
            if(flat_window(layer,frame)){found=true;break;}}
        if(!found)return original_end(s,info);anchored_window=frame;anchored_activation=epoch;anchored_distance=ui_distance();
        if(!(anchored_distance>0))anchored_distance=1;
    }
    std::array<xr_read::Quad,2> images{};
    for(unsigned eye=0;eye<2;++eye){const auto& view=source->views[eye];const auto& f=view.fov;
        const float l=std::tan(f.angleLeft),r=std::tan(f.angleRight),u=std::tan(f.angleUp),d=std::tan(f.angleDown);
        if(!std::isfinite(l+r+u+d)||l>=0||r<=0||u<=0||d>=0)return original_end(s,info);
        const float coverage=full_view_coverage.load();
        Window frame=anchored_window;frame.width=(r-l)*anchored_distance*coverage;frame.height=(u-d)*anchored_distance*full_view_vertical.load();
        const auto shift=rotate(frame.pose.orientation,{(l+r)*anchored_distance*coverage/2,(u+d)*anchored_distance*full_view_vertical.load()/2,0});
        frame.pose.position.x+=shift.x;frame.pose.position.y+=shift.y;frame.pose.position.z+=shift.z;
        if(!movie_quad(frame,view,{0,0,1,1},eye,images[eye]))return original_end(s,info);
    }
    std::array<const xr_read::Layer*,16> layers{};unsigned count=0;
    for(unsigned i=0;i<info->layerCount;++i){if(info->layers[i]==reinterpret_cast<const xr_read::Layer*>(source)){layers[count++]=reinterpret_cast<const xr_read::Layer*>(&images[0]);layers[count++]=reinterpret_cast<const xr_read::Layer*>(&images[1]);}else layers[count++]=info->layers[i];}
    auto output=*info;output.layerCount=count;output.layers=layers.data();++full_view_frames;state="hangar_full_view_movie";
    return transition.opacity>0?transition_frame(s,&output,source):original_end(s,&output);
}
inline Result __stdcall end_frame(Handle s,const xr_read::EndInfo* info) {
    std::lock_guard<std::recursive_mutex> guard(lock);++frames;
    const auto baseTransition=transition;
    struct RestoreTransition{Transition value;~RestoreTransition(){transition=value;}}restoreTransition{baseTransition};
    float authoredOpacity=0;
    if(native_fade::opacity(authoredOpacity)){transition.opacity=authoredOpacity;if(authoredOpacity<.9999f)transition.loading=false;}
    // A nonblocking wait can straddle the user switching OFF. Settle only our image.
    if(acquired && ((!requested&&transition.opacity<=0)||failed) && s==session) {
        if(!waited){const Wait w{56,nullptr,0};waited=wait_image(chain,&w)==0;}
        if(waited){const Base r{57,nullptr};if(release(chain,&r)!=0)fail("off_release_failed");acquired=waited=false;}
    }
    if((!requested&&!full_view&&transition.opacity<=0)||failed||!info||info->type!=12||!info->layers||!info->layerCount||info->layerCount>13)return original_end(s,info);
    if(host->openxr->get_xr_session()!=s||(session&&session!=s)){state="session_changed_skipped";++skipped;return original_end(s,info);}
    if(transition.opacity>0&&transition.loading)return transition_frame(s,info);
    if(full_view&&!requested)return full_view_frame(s,info);
    if(transition.opacity>0&&!requested)return transition_frame(s,info);
    const xr_read::Projection* source=nullptr;
    for(unsigned i=0;i<info->layerCount;++i)if(info->layers[i]&&info->layers[i]->type==35){if(source){source=nullptr;break;}source=reinterpret_cast<const xr_read::Projection*>(info->layers[i]);}
    std::array<Aperture,2> holes{};
    if(!source||!source->space||source->viewCount!=2||!source->views||!aperture(source->views[0].fov,pixels,holes[0])||!aperture(source->views[1].fov,pixels,holes[1])){
        state="projection_layout_skipped";++skipped;return original_end(s,info);}
    const auto epoch=activation.load();
    {
        Window candidate{};bool found=false;
        // The native HUD layer carries live UI Size, Distance, offsets and recenter pose.
        // Flatten its cylinder mathematically instead of writing the user's curve option.
        for(unsigned i=0;i<info->layerCount;++i)if(info->layers[i]&&info->layers[i]->space==source->space){
            if(info->layers[i]->type!=xr_read::cylinder&&info->layers[i]->type!=xr_read::quad)continue;
            const auto* sub=info->layers[i]->type==xr_read::cylinder?&reinterpret_cast<const xr_read::Cylinder*>(info->layers[i])->subImage:&reinterpret_cast<const xr_read::Quad*>(info->layers[i])->subImage;
            if(host->vr && host->vr->get_ui_width && host->vr->get_ui_height &&
               (sub->imageRect.extent.width!=static_cast<int>(host->vr->get_ui_width())||sub->imageRect.extent.height!=static_cast<int>(host->vr->get_ui_height())))continue;
            if(flat_window(info->layers[i],candidate)){found=true;break;}
        }
        const float actual_distance=ui_distance();
        const float distance=frame_distance_override>0?frame_distance_override.load():actual_distance;
        if(found&&frame_size_override>0){const float ratio=frame_size_override.load()/candidate.height;candidate.width*=ratio;candidate.height*=ratio;}
        if(anchored_activation!=epoch || !anchored_window.space){
            if(!found){state="waiting_window_anchor";++skipped;return original_end(s,info);}
            anchored_window=candidate;anchored_activation=epoch;anchored_distance=distance;
            std::copy_n(source->views,2,movie_reference.begin());
            if(distance>0&&actual_distance>0)resize_window(anchored_window,candidate,actual_distance,distance);
        }else if(found){
            resize_window(anchored_window,candidate,anchored_distance>0?anchored_distance:distance,distance>0?distance:anchored_distance);
            if(distance>0)anchored_distance=distance;
        }
        shown_width=anchored_window.width;shown_height=anchored_window.height;shown_distance=anchored_distance;
    }
    if(anchored_window.space!=source->space){state="anchor_space_changed_skipped";++skipped;return original_end(s,info);}
    std::array<xr_read::Quad,2> movies{};
    std::array<MovieCrop,2> movie_bounds{};
    double limit_x=1e6,limit_y=1e6;
    for(unsigned eye=0;eye<2;++eye){const auto& f=source->views[eye].fov;limit_x=std::min(limit_x,static_cast<double>(std::min(-std::tan(f.angleLeft),std::tan(f.angleRight))));limit_y=std::min(limit_y,static_cast<double>(std::min(std::tan(f.angleUp),-std::tan(f.angleDown))));}
    {std::lock_guard<std::mutex> lens_guard(cinematic_lens::mutex);cinematic_lens::view={anchored_window.width,anchored_window.height,anchored_distance,limit_x,limit_y};}
    Window movie_window=anchored_window;cinematic_lens::Fit lens_fit{};
    if(cinematic_lens::current(lens_fit)){movie_window.width=static_cast<float>(lens_fit.width);movie_window.height=static_cast<float>(lens_fit.height);}
    if(!movie_crops(movie_window,anchored_distance,source->views,movie_bounds)){state="movie_crop_skipped";++skipped;return original_end(s,info);}
    for(unsigned eye=0;eye<2;++eye){
        if(!movie_quad(movie_window,source->views[eye],movie_bounds[eye],eye,movies[eye])){
            state="movie_window_layout_skipped";++skipped;return original_end(s,info);}}
    const std::array<std::array<Clip,6>,2> vertices{window_parameters(anchored_window,source->views[0],pixels),window_parameters(anchored_window,source->views[1],pixels)};
    bool ready=false;
    try{if(!chain&&!initialize_images(s)){fail("mask_initialization_failed");}if(!failed)ready=draw(holes,&vertices);}catch(...){fail("mask_gpu_failed");}
    if(!ready){++skipped;return original_end(s,info);}
    std::array<xr_read::ProjectionView,2> views{mask_view(source->views[0],chain,0,pixels),mask_view(source->views[1],chain,1,pixels)};
    const xr_read::Projection border{35,nullptr,2,source->space,2,views.data()};
    std::array<const xr_read::Layer*,16> layers{};unsigned layer_count=0;
    for(unsigned i=0;i<info->layerCount;++i){
        if(info->layers[i]==reinterpret_cast<const xr_read::Layer*>(source)){
            layers[layer_count++]=reinterpret_cast<const xr_read::Layer*>(&movies[0]);
            layers[layer_count++]=reinterpret_cast<const xr_read::Layer*>(&movies[1]);
            if(hangar_crop)layers[layer_count++]=reinterpret_cast<const xr_read::Layer*>(&border);
        }else layers[layer_count++]=info->layers[i];}
    if(!hangar_crop)layers[layer_count++]=reinterpret_cast<const xr_read::Layer*>(&border);
    auto output=*info;output.layerCount=layer_count;output.layers=layers.data();
    const auto result=original_end(s,&output);if(result<0)fail("masked_submission_failed");else{++masked;state="mask_active";}return result;
}
// SHA-pinned loader internals, independently below the existing HUD wrapper hook.
// Disassembly: wrapper352A8F reads LoaderInstance+48, then dispatch+118 (xrEndFrame).
inline void* lower_end(unsigned char* base) {
    __try {void* loader=nullptr;using Lookup=Result(__fastcall*)(void**,const char*);
        if(reinterpret_cast<Lookup>(base+0x35af80)(&loader,"xrEndFrame")!=0||!loader)return nullptr;
        auto* table=*reinterpret_cast<unsigned char**>(static_cast<unsigned char*>(loader)+0x48);
        return table?*reinterpret_cast<void**>(table+0x118):nullptr;
    }__except(EXCEPTION_EXECUTE_HANDLER){return nullptr;}
}
template<class T> inline bool get(xr_read::GetProcFn proc,Handle instance,const char* name,T& output){return proc(instance,name,reinterpret_cast<void**>(&output))==0&&output;}
inline void attach() {
    if(attempted||!host||!host->openxr||!host->openxr->get_xr_session||!host->openxr->get_xr_session()||!host->renderer||!host->renderer->device||!host->renderer->command_queue)return;
    attempted=true;auto module=GetModuleHandleW(L"UEVRBackend.dll");wchar_t path[32768]{};std::string hash;
    if(!module||!GetModuleFileNameW(module,path,32768)||!boundary::file_hash(path,hash)||hash!=boundary::expected_hash){state="unsupported_backend";return;}
    auto* base=reinterpret_cast<unsigned char*>(module);
    const unsigned char lookup_bytes[]={0x48,0x89,0x5c,0x24,0x18,0x55,0x56,0x57,0x48,0x8d,0x6c,0x24,0xb9};
    if(std::memcmp(base+0x35af80,lookup_bytes,sizeof(lookup_bytes))){state="loader_guard_failed";return;}
    auto proc=reinterpret_cast<xr_read::GetProcFn>(base+0x34fa70);auto instance=host->openxr->get_xr_instance();
    if(!get(proc,instance,"xrCreateSwapchain",create_chain)||!get(proc,instance,"xrEnumerateSwapchainImages",enumerate_images)||
       !get(proc,instance,"xrAcquireSwapchainImage",acquire)||!get(proc,instance,"xrWaitSwapchainImage",wait_image)||
       !get(proc,instance,"xrReleaseSwapchainImage",release)||!get(proc,instance,"xrEnumerateSwapchainFormats",formats)){state="resolver_failed";return;}
    auto* target=lower_end(base);MEMORY_BASIC_INFORMATION memory{};
    if(!target||!VirtualQuery(target,&memory,sizeof(memory))||!(memory.Protect&(PAGE_EXECUTE|PAGE_EXECUTE_READ|PAGE_EXECUTE_READWRITE|PAGE_EXECUTE_WRITECOPY))){state="dispatch_guard_failed";return;}
    HMODULE own=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,reinterpret_cast<LPCWSTR>(&end_frame),&own)){state="pin_failed";return;}
    const auto id=host->functions->register_inline_hook(target,reinterpret_cast<void*>(&end_frame),reinterpret_cast<void**>(&original_end));
    attached=id>=0&&original_end;state=attached?"attached":"hook_failed";host->functions->log_info("[Cinematic Mask] %s",state.load());
}
inline void control(const char* event,const char* data){
if(event&&data&&!std::strcmp(event,"AC8_HangarCrop")){
    std::lock_guard<std::recursive_mutex> guard(lock);
    control("AC8_CinematicMask",data);full_view=false;hangar_crop=requested.load();return;
}
if(event&&data&&!std::strcmp(event,"AC8_HangarCoverage")){float x=0,y=0;char trailing=0;const int n=sscanf_s(data,"%f|%f%c",&x,&y,&trailing,1u);if(n==2&&std::isfinite(x)&&std::isfinite(y)&&x>=1&&x<=3&&y>=1&&y<=2){full_view_coverage=x;full_view_vertical=y;}return;}
if(event&&data&&!std::strcmp(event,"AC8_CinematicFullView")){std::lock_guard<std::recursive_mutex> guard(lock);const bool on=!std::strcmp(data,"on");if(on&&!full_view)++activation;full_view=on;return;}
if(event&&data&&!std::strcmp(event,"AC8_TransitionCover")){
    Transition candidate{};unsigned loading=0;char trailing=0;
    const int parsed=sscanf_s(data,"%f|%u|%f|%f|%f|%f|%f|%f|%f%c",&candidate.opacity,&loading,&candidate.color[0],&candidate.color[1],&candidate.color[2],&candidate.bounds[0],&candidate.bounds[1],&candidate.bounds[2],&candidate.bounds[3],&trailing,1u);
    bool valid=parsed==9&&loading<=1&&std::isfinite(candidate.opacity)&&candidate.opacity>=0&&candidate.opacity<=1;
    for(float value:candidate.color)valid=valid&&std::isfinite(value)&&value>=0&&value<=1;
    for(float value:candidate.bounds)valid=valid&&std::isfinite(value)&&value>=0&&value<=1;
    valid=valid&&candidate.bounds[0]<candidate.bounds[2]&&candidate.bounds[1]<candidate.bounds[3];candidate.loading=loading==1;
    candidate.color={0,0,0}; // Loading, menu surround and fade cover are always black.
    std::lock_guard<std::recursive_mutex> guard(lock);transition=valid?candidate:Transition{};return;
}
if(event&&data&&!std::strcmp(event,"AC8_CinematicMask")){
    hangar_crop=false;
    const bool on=!std::strcmp(data,"on")||!std::strncmp(data,"on|",3);float size=0,distance=0;
    if(on&&sscanf_s(data,"on|%f|%f",&size,&distance)==2&&std::isfinite(size+distance)&&size>0&&distance>0){frame_size_override=size;frame_distance_override=distance;}
    else{frame_size_override=0;frame_distance_override=0;}
    if(on&&!requested)++activation;requested=on;
}}

}
