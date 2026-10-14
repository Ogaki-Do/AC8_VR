// Compose the HUD against each current eye image using the validated curved
// HUD mapping. Scene backup and output resources belong to this renderer;
// OpenXR image ownership and command submission remain with the host bridge.

#pragma once
#include "hud_route_glow.h"
#include "current_geometry.h"
namespace hud_route_scene {
using Microsoft::WRL::ComPtr;
inline void transition(ID3D12GraphicsCommandList* l,ID3D12Resource* r,D3D12_RESOURCE_STATES a,D3D12_RESOURCE_STATES b){
    D3D12_RESOURCE_BARRIER t{};t.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;t.Transition={r,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,a,b};l->ResourceBarrier(1,&t);
}
class Renderer {
    ComPtr<ID3D12Device> device_;
    ComPtr<ID3D12RootSignature> root_;
    ComPtr<ID3D12PipelineState> pso_;
    ComPtr<ID3D12DescriptorHeap> srv_;
    ComPtr<ID3D12Resource> snapshot_,output_;
    struct Slot {
        ComPtr<ID3D12Resource> mapping,scene,hud;
        ComPtr<ID3D12DescriptorHeap> rtv;
        ComPtr<ID3D12CommandAllocator> allocator;
        ComPtr<ID3D12GraphicsCommandList> list;
        uint64_t consumer=0;
    };
    std::array<Slot,4> slots_{};
    unsigned next_slot_=0,active_slot_=0;
    bool busy_=false;
    UINT width_=0,height_=0;
    static std::vector<unsigned char> bytes(const std::filesystem::path& p){
        std::ifstream f(p,std::ios::binary|std::ios::ate);if(!f)throw std::runtime_error("Missing scene shader");
        const auto n=f.tellg();if(n<=0||n>1024*1024)throw std::runtime_error("Scene shader size");std::vector<unsigned char> b(static_cast<size_t>(n));f.seekg(0);
        if(!f.read(reinterpret_cast<char*>(b.data()),n))throw std::runtime_error("Scene shader read");return b;
    }
public:
    static bool supported(ID3D12Resource* r){if(!r)return false;const auto d=r->GetDesc();return d.Dimension==D3D12_RESOURCE_DIMENSION_TEXTURE2D&&d.Width<=8192&&d.Height<=8192&&d.DepthOrArraySize==1&&d.MipLevels==1&&d.SampleDesc.Count==1&&
        (d.Flags&D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET)&&!(d.Flags&D3D12_RESOURCE_FLAG_DENY_SHADER_RESOURCE)&&
        (d.Format==DXGI_FORMAT_B8G8R8A8_UNORM||d.Format==DXGI_FORMAT_B8G8R8A8_TYPELESS||d.Format==DXGI_FORMAT_B8G8R8A8_UNORM_SRGB);}
    Renderer(ID3D12Device* d,const std::filesystem::path& assets,hud_route_glow::Renderer& glow,ID3D12Resource* scene):device_(d){
        if(!supported(scene))throw std::runtime_error("Unsupported scene format");const auto desc=scene->GetDesc();width_=static_cast<UINT>(desc.Width);height_=desc.Height;
        D3D12_DESCRIPTOR_RANGE range{};range.RangeType=D3D12_DESCRIPTOR_RANGE_TYPE_SRV;range.NumDescriptors=10;
        D3D12_ROOT_PARAMETER p[4]{};p[0].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;p[0].DescriptorTable={1,&range};p[0].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
        for(UINT i=1;i<4;++i){p[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_CBV;p[i].Descriptor.ShaderRegister=i-1;p[i].ShaderVisibility=D3D12_SHADER_VISIBILITY_PIXEL;}
        D3D12_STATIC_SAMPLER_DESC s[2]{};
        for(UINT i=0;i<2;++i){s[i].Filter=D3D12_FILTER_MIN_MAG_LINEAR_MIP_POINT;s[i].AddressU=s[i].AddressV=s[i].AddressW=i?D3D12_TEXTURE_ADDRESS_MODE_WRAP:D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
            s[i].MaxAnisotropy=1;s[i].ComparisonFunc=D3D12_COMPARISON_FUNC_ALWAYS;s[i].MaxLOD=D3D12_FLOAT32_MAX;s[i].ShaderRegister=i;s[i].ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;}
        D3D12_ROOT_SIGNATURE_DESC rd{};rd.NumParameters=4;rd.pParameters=p;rd.NumStaticSamplers=2;rd.pStaticSamplers=s;ComPtr<ID3DBlob> code,error;
        native_generation::check(D3D12SerializeRootSignature(&rd,D3D_ROOT_SIGNATURE_VERSION_1,&code,&error));native_generation::check(d->CreateRootSignature(0,code->GetBufferPointer(),code->GetBufferSize(),IID_PPV_ARGS(&root_)));
        const auto vs=bytes(assets/L"hud-scene-VS.dxbc"),ps=bytes(assets/L"hud-scene-PS.dxbc");
        D3D12_GRAPHICS_PIPELINE_STATE_DESC pd{};pd.pRootSignature=root_.Get();pd.VS={vs.data(),vs.size()};pd.PS={ps.data(),ps.size()};pd.SampleMask=UINT_MAX;pd.PrimitiveTopologyType=D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        pd.NumRenderTargets=1;pd.RTVFormats[0]=DXGI_FORMAT_B8G8R8A8_UNORM;pd.SampleDesc.Count=1;pd.RasterizerState.FillMode=D3D12_FILL_MODE_SOLID;pd.RasterizerState.CullMode=D3D12_CULL_MODE_NONE;pd.RasterizerState.DepthClipEnable=TRUE;pd.DepthStencilState.DepthFunc=D3D12_COMPARISON_FUNC_ALWAYS;
        auto& blend=pd.BlendState.RenderTarget[0];blend.SrcBlend=blend.SrcBlendAlpha=D3D12_BLEND_ONE;blend.DestBlend=blend.DestBlendAlpha=D3D12_BLEND_ZERO;blend.BlendOp=blend.BlendOpAlpha=D3D12_BLEND_OP_ADD;blend.RenderTargetWriteMask=15;
        native_generation::check(d->CreateGraphicsPipelineState(&pd,IID_PPV_ARGS(&pso_)));
        auto td=desc;td.Format=DXGI_FORMAT_B8G8R8A8_UNORM;td.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;D3D12_HEAP_PROPERTIES heap{};heap.Type=D3D12_HEAP_TYPE_DEFAULT;
        native_generation::check(d->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&td,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,nullptr,IID_PPV_ARGS(&snapshot_)));
        native_generation::check(d->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&td,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,nullptr,IID_PPV_ARGS(&output_)));
        D3D12_RESOURCE_DESC buffer{};buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;buffer.Width=1024;buffer.Height=1;buffer.DepthOrArraySize=buffer.MipLevels=1;buffer.SampleDesc.Count=1;buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;heap.Type=D3D12_HEAP_TYPE_UPLOAD;
        for(auto& slot:slots_)native_generation::check(d->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&slot.mapping)));
        D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;hd.NumDescriptors=10;hd.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;native_generation::check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&srv_)));
        const UINT stride=d->GetDescriptorHandleIncrementSize(hd.Type);
        for(UINT i=0;i<10;++i){D3D12_SHADER_RESOURCE_VIEW_DESC view{};view.Format=i==6?DXGI_FORMAT_BC7_UNORM_SRGB:i==9?DXGI_FORMAT_R16G16B16A16_FLOAT:(i==0||i==8)?DXGI_FORMAT_B8G8R8A8_UNORM:DXGI_FORMAT_R8G8B8A8_UNORM;
            view.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2D;view.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;view.Texture2D.MipLevels=i==6?8:1;d->CreateShaderResourceView(i==8?snapshot_.Get():glow.input(i),&view,{srv_->GetCPUDescriptorHandleForHeapStart().ptr+size_t(i)*stride});}
        hd={};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;hd.NumDescriptors=2;
        for(auto& slot:slots_){
            native_generation::check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&slot.rtv)));d->CreateRenderTargetView(output_.Get(),nullptr,slot.rtv->GetCPUDescriptorHandleForHeapStart());
            native_generation::check(d->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&slot.allocator)));
            native_generation::check(d->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,slot.allocator.Get(),nullptr,IID_PPV_ARGS(&slot.list)));native_generation::check(slot.list->Close());
        }
    }
    // Four bounded CPU recording slots share queue-serialized GPU textures. Each
    // allocator, geometry upload, HUD descriptor and image pin has its own fence.
    bool record(hud_route_glow::Renderer& glow,ID3D12Resource* scene,ID3D12Resource* hud,const current_geometry::Snapshot& g,ID3D12Fence* fence=nullptr){
        if(!supported(scene)||!supported(hud)||scene==hud||scene->GetDesc().Width!=width_||scene->GetDesc().Height!=height_||hud->GetDesc().Width!=g.hud_width||hud->GetDesc().Height!=g.hud_height)return false;
        busy_=false;const uint64_t completed=fence?fence->GetCompletedValue():0;
        if(completed==UINT64_MAX)return false;
        unsigned chosen=static_cast<unsigned>(slots_.size());
        for(unsigned n=0;n<slots_.size();++n){const unsigned i=(next_slot_+n)%static_cast<unsigned>(slots_.size());if(!slots_[i].consumer||(fence&&slots_[i].consumer<=completed)){chosen=i;break;}}
        if(chosen==slots_.size()){busy_=true;return false;}
        active_slot_=chosen;next_slot_=(chosen+1)%static_cast<unsigned>(slots_.size());auto& slot=slots_[chosen];
        slot.scene=scene;slot.hud=hud;
        current_geometry::Constants constants[2]{};const float bounds[4]{0,0,1,1};
        for(unsigned eye=0;eye<2;++eye){if(!current_geometry::constants(g,eye,g.frame,g.layout,bounds,constants[eye]))return false;
            constants[eye].eye_rectangle[0]=float(g.eyes[eye].subImage.imageRect.offset.x);constants[eye].eye_rectangle[1]=float(g.eyes[eye].subImage.imageRect.offset.y);}
        void* data=nullptr;D3D12_RANGE no_read{0,0};native_generation::check(slot.mapping->Map(0,&no_read,&data));std::memset(data,0,1024);
        for(unsigned eye=0;eye<2;++eye){std::memcpy(static_cast<unsigned char*>(data)+eye*512,&constants[eye],112);std::memcpy(static_cast<unsigned char*>(data)+eye*512+256,constants[eye].source_scale_bias,32);}slot.mapping->Unmap(0,nullptr);
        D3D12_RENDER_TARGET_VIEW_DESC view{};view.Format=DXGI_FORMAT_B8G8R8A8_UNORM;view.ViewDimension=D3D12_RTV_DIMENSION_TEXTURE2D;
        const auto base=slot.rtv->GetCPUDescriptorHandleForHeapStart();const D3D12_CPU_DESCRIPTOR_HANDLE hud_handle{base.ptr+device_->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV)};device_->CreateRenderTargetView(hud,&view,hud_handle);
        native_generation::check(slot.allocator->Reset());native_generation::check(slot.list->Reset(slot.allocator.Get(),nullptr));auto* l=slot.list.Get();
        transition(l,scene,D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_COPY_SOURCE);transition(l,snapshot_.Get(),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_COPY_DEST);l->CopyResource(snapshot_.Get(),scene);
        transition(l,snapshot_.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_COPY_SOURCE);transition(l,output_.Get(),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_COPY_DEST);l->CopyResource(output_.Get(),snapshot_.Get());
        transition(l,snapshot_.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);transition(l,output_.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_RENDER_TARGET);
        transition(l,glow.input(0),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE|D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        ID3D12DescriptorHeap* descriptor=srv_.Get();l->SetDescriptorHeaps(1,&descriptor);l->SetGraphicsRootSignature(root_.Get());l->SetPipelineState(pso_.Get());l->SetGraphicsRootDescriptorTable(0,srv_->GetGPUDescriptorHandleForHeapStart());l->SetGraphicsRootConstantBufferView(1,glow.parameters()->GetGPUVirtualAddress());l->OMSetRenderTargets(1,&base,FALSE,nullptr);l->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
        for(unsigned eye=0;eye<2;++eye){const auto& r=g.eyes[eye].subImage.imageRect;const D3D12_VIEWPORT viewport{float(r.offset.x),float(r.offset.y),float(r.extent.width),float(r.extent.height),0,1};const D3D12_RECT scissor{r.offset.x,r.offset.y,r.offset.x+r.extent.width,r.offset.y+r.extent.height};l->RSSetViewports(1,&viewport);l->RSSetScissorRects(1,&scissor);l->SetGraphicsRootConstantBufferView(2,slot.mapping->GetGPUVirtualAddress()+eye*512);l->SetGraphicsRootConstantBufferView(3,slot.mapping->GetGPUVirtualAddress()+eye*512+256);l->DrawInstanced(3,1,0,0);}
        transition(l,output_.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_COPY_SOURCE);transition(l,scene,D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_COPY_DEST);l->CopyResource(scene,output_.Get());transition(l,scene,D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_RENDER_TARGET);transition(l,output_.Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
        transition(l,glow.input(0),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE|D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
        // Couple replacement and duplicate suppression in this one submission.
        const float zero[4]{};l->ClearRenderTargetView(hud_handle,zero,0,nullptr);
        native_generation::check(l->Close());return true;
    }
    ID3D12CommandList* commands(){return slots_[active_slot_].list.Get();}
    void submitted(uint64_t ticket){slots_[active_slot_].consumer=ticket;}
    bool busy()const{return busy_;}
};
}

