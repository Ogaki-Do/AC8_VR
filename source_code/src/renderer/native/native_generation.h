// Construct and record the native HUD effect pass graph from bundled assets.
// The caller provides the live source texture and owns command submission and
// fence lifetime. This code does not read back images or write captures.

#pragma once
// Original captured game shaders, samplers, root bindings, and pass order.
// Generation only. The original scene-dependent final BlendPS is still separate.
// Caller owns command-list submission and fenced lifetime. Never run on a host
// command list unless the caller restores its complete graphics state.
#include <d3d12.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <vector>
#include <stdexcept>
#include <cfloat>
namespace native_generation {
using Microsoft::WRL::ComPtr;
static void check(HRESULT hr){if(FAILED(hr))throw std::runtime_error("Native generation D3D12 operation failed");}
#include "original_root_signature.h"
#include "original_root_1022.h"
#include "original_root_4188.h"
#include "native_chain_specs.h"
struct Texture {ComPtr<ID3D12Resource> resource;D3D12_CPU_DESCRIPTOR_HANDLE rtv{};DXGI_FORMAT format=DXGI_FORMAT_R8G8B8A8_UNORM;};
struct Stage {PassSpec spec{};ComPtr<ID3D12PipelineState> pso;ComPtr<ID3D12DescriptorHeap> srvs,samplers;ComPtr<ID3D12Resource> pixel,vertex;ID3D12RootSignature* root=nullptr;};
class Recorder {
    friend class FinalBlend;
    ComPtr<ID3D12Device> device;ComPtr<ID3D12DescriptorHeap> rtvs;
    ComPtr<ID3D12RootSignature> r1033,r1022,r4188;
    ComPtr<ID3D12Resource> vb,view;
    std::map<int,Texture> textures;std::vector<Stage> stages;
    std::filesystem::path assets;UINT next_rtv=0,rt_stride=0,sr_stride=0;
    static std::vector<unsigned char> read(const std::filesystem::path& path){
        std::ifstream f(path,std::ios::binary|std::ios::ate);if(!f)throw std::runtime_error("Missing native shader asset");
        const auto size=f.tellg();if(size<=0||size>16*1024*1024)throw std::runtime_error("Invalid native shader asset size");
        std::vector<unsigned char> data(static_cast<size_t>(size));f.seekg(0);f.read(reinterpret_cast<char*>(data.data()),size);
        if(!f)throw std::runtime_error("Incomplete native shader asset");return data;
    }
    ComPtr<ID3D12Resource> upload(const void* data,size_t size){
        D3D12_HEAP_PROPERTIES heap{};heap.Type=D3D12_HEAP_TYPE_UPLOAD;
        D3D12_RESOURCE_DESC d{};d.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;d.Width=(size+255)&~size_t(255);
        d.Height=1;d.DepthOrArraySize=d.MipLevels=1;d.SampleDesc.Count=1;d.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        ComPtr<ID3D12Resource> r;check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&d,D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&r)));
        void* p=nullptr;const D3D12_RANGE no_read{0,0};check(r->Map(0,&no_read,&p));memset(p,0,static_cast<size_t>(d.Width));memcpy(p,data,size);
        const D3D12_RANGE written{0,size};r->Unmap(0,&written);return r;
    }
    ComPtr<ID3D12Resource> buffer(const wchar_t* suffix,int event){return buffer(L"event-"+std::to_wstring(event)+suffix);}
    ComPtr<ID3D12Resource> buffer(const std::wstring& name){const auto data=read(assets/name);return upload(data.data(),data.size());}
    Texture& texture(int id,UINT width,UINT height,DXGI_FORMAT format){
        auto& t=textures[id];t.format=format;D3D12_RESOURCE_DESC d{};d.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        d.Width=width;d.Height=height;d.DepthOrArraySize=d.MipLevels=1;d.Format=format;d.SampleDesc.Count=1;d.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
        D3D12_HEAP_PROPERTIES heap{};heap.Type=D3D12_HEAP_TYPE_DEFAULT;
        check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&d,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,nullptr,IID_PPV_ARGS(&t.resource)));
        t.rtv.ptr=rtvs->GetCPUDescriptorHandleForHeapStart().ptr+next_rtv++*rt_stride;device->CreateRenderTargetView(t.resource.Get(),nullptr,t.rtv);return t;
    }
    static void transition(ID3D12GraphicsCommandList* list,ID3D12Resource* resource,D3D12_RESOURCE_STATES before,D3D12_RESOURCE_STATES after){
        D3D12_RESOURCE_BARRIER b{};b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;b.Transition={resource,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,before,after};list->ResourceBarrier(1,&b);
    }
public:
    Recorder(ID3D12Device* d,const std::filesystem::path& directory):device(d),assets(directory){
        if(!d)throw std::runtime_error("Missing D3D12 device");r1033=make_root(d);r1022=make_root_1022(d);r4188=make_root_4188(d);
        D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV;hd.NumDescriptors=32;check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&rtvs)));
        rt_stride=d->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);sr_stride=d->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
        texture(421,2560,1338,DXGI_FORMAT_B8G8R8A8_UNORM);texture(317,1,1,DXGI_FORMAT_R8G8B8A8_UNORM);texture(1088,1,1,DXGI_FORMAT_R8G8B8A8_UNORM);
        for(const auto& spec:specs)texture(spec.target,static_cast<UINT>(spec.width),static_cast<UINT>(spec.height),DXGI_FORMAT_R8G8B8A8_UNORM);
        const float vertices[][6]={{0,0,0,1,0,0},{1,0,0,1,1,0},{0,1,0,1,0,1},{0,1,0,1,0,1},{1,0,0,1,1,0},{1,1,0,1,1,1}};
        vb=upload(vertices,sizeof(vertices));view=buffer(L"event-3347-View.bin");
        for(const auto& spec:specs){
            Stage stage{};stage.spec=spec;stage.root=spec.root==1033?r1033.Get():spec.root==1022?r1022.Get():r4188.Get();
            const auto vs=read(assets/(L"pso-"+std::to_wstring(spec.pso)+L"-VS.dxbc"));const auto ps=read(assets/(L"pso-"+std::to_wstring(spec.pso)+L"-PS.dxbc"));
            D3D12_INPUT_ELEMENT_DESC input[]={{"ATTRIBUTE",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,0,D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0},{"ATTRIBUTE",1,DXGI_FORMAT_R32G32_FLOAT,0,16,D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0}};
            D3D12_GRAPHICS_PIPELINE_STATE_DESC pd{};pd.pRootSignature=stage.root;pd.VS={vs.data(),vs.size()};pd.PS={ps.data(),ps.size()};pd.InputLayout={input,2};pd.SampleMask=UINT_MAX;
            pd.PrimitiveTopologyType=D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;pd.NumRenderTargets=1;pd.RTVFormats[0]=DXGI_FORMAT_R8G8B8A8_UNORM;pd.SampleDesc.Count=1;
            pd.RasterizerState.FillMode=D3D12_FILL_MODE_SOLID;pd.RasterizerState.CullMode=D3D12_CULL_MODE_NONE;pd.RasterizerState.FrontCounterClockwise=TRUE;pd.RasterizerState.DepthClipEnable=TRUE;pd.RasterizerState.MultisampleEnable=TRUE;
            pd.DepthStencilState.DepthWriteMask=D3D12_DEPTH_WRITE_MASK_ZERO;pd.DepthStencilState.DepthFunc=D3D12_COMPARISON_FUNC_ALWAYS;
            pd.BlendState.IndependentBlendEnable=TRUE;pd.DepthStencilState.StencilReadMask=pd.DepthStencilState.StencilWriteMask=255;
            pd.DepthStencilState.FrontFace=pd.DepthStencilState.BackFace={D3D12_STENCIL_OP_KEEP,D3D12_STENCIL_OP_KEEP,D3D12_STENCIL_OP_KEEP,D3D12_COMPARISON_FUNC_ALWAYS};
            for(auto& b:pd.BlendState.RenderTarget){b.SrcBlend=b.SrcBlendAlpha=D3D12_BLEND_ONE;b.DestBlend=b.DestBlendAlpha=D3D12_BLEND_ZERO;b.BlendOp=b.BlendOpAlpha=D3D12_BLEND_OP_ADD;b.LogicOp=D3D12_LOGIC_OP_CLEAR;b.RenderTargetWriteMask=D3D12_COLOR_WRITE_ENABLE_ALL;}
            check(d->CreateGraphicsPipelineState(&pd,IID_PPV_ARGS(&stage.pso)));
            hd={};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;hd.NumDescriptors=64;hd.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&stage.srvs)));
            hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER;hd.NumDescriptors=32;check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&stage.samplers)));
            for(unsigned i=0;i<spec.source_count;++i){const auto& t=textures.at(spec.sources[i]);D3D12_SHADER_RESOURCE_VIEW_DESC sv{};sv.Format=t.format;sv.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2D;sv.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;sv.Texture2D.MipLevels=1;
                D3D12_CPU_DESCRIPTOR_HANDLE h{stage.srvs->GetCPUDescriptorHandleForHeapStart().ptr+i*sr_stride};d->CreateShaderResourceView(t.resource.Get(),&sv,h);}
            const auto sampler=native_sampler(spec.event);d->CreateSampler(&sampler,stage.samplers->GetCPUDescriptorHandleForHeapStart());
            stage.pixel=buffer(L"-PS-root-parameters.bin",spec.event);if(spec.vertex_file)stage.vertex=buffer(L"-VS-constants.bin",spec.event);stages.push_back(std::move(stage));
        }
    }
    // Immutable snapshot must be COPY_SOURCE, same device, exact supported extent.
    // All owned textures begin and end PS_RESOURCE. No allocation or file IO here.
    bool record(ID3D12GraphicsCommandList* list,ID3D12Resource* snapshot){
        if(!list||!snapshot)return false;const auto sd=snapshot->GetDesc();
        if(sd.Dimension!=D3D12_RESOURCE_DIMENSION_TEXTURE2D||sd.Width!=2560||sd.Height!=1338||sd.DepthOrArraySize!=1||sd.MipLevels!=1||sd.SampleDesc.Count!=1||
            (sd.Format!=DXGI_FORMAT_B8G8R8A8_UNORM&&sd.Format!=DXGI_FORMAT_B8G8R8A8_TYPELESS&&sd.Format!=DXGI_FORMAT_B8G8R8A8_UNORM_SRGB))return false;
        ComPtr<ID3D12Device> source_device;if(FAILED(snapshot->GetDevice(IID_PPV_ARGS(&source_device)))||source_device.Get()!=device.Get())return false;
        auto* input=textures.at(421).resource.Get();transition(list,input,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_COPY_DEST);list->CopyResource(input,snapshot);transition(list,input,D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
        for(int id:{317,1088}){auto& t=textures.at(id);transition(list,t.resource.Get(),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_RENDER_TARGET);const float zero[4]{};list->ClearRenderTargetView(t.rtv,zero,0,nullptr);transition(list,t.resource.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);}
        const D3D12_VERTEX_BUFFER_VIEW vbv{vb->GetGPUVirtualAddress(),144,24};
        for(const auto& stage:stages){const auto& spec=stage.spec;auto& t=textures.at(spec.target);transition(list,t.resource.Get(),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_RENDER_TARGET);
            ID3D12DescriptorHeap* heaps[]={stage.srvs.Get(),stage.samplers.Get()};list->SetDescriptorHeaps(2,heaps);list->SetPipelineState(stage.pso.Get());list->SetGraphicsRootSignature(stage.root);
            list->SetGraphicsRootDescriptorTable(0,stage.srvs->GetGPUDescriptorHandleForHeapStart());list->SetGraphicsRootDescriptorTable(1,stage.samplers->GetGPUDescriptorHandleForHeapStart());list->SetGraphicsRootConstantBufferView(2,stage.pixel->GetGPUVirtualAddress());
            if(spec.root==1033)list->SetGraphicsRootConstantBufferView(3,view->GetGPUVirtualAddress());if(stage.vertex)list->SetGraphicsRootConstantBufferView(static_cast<UINT>(spec.vertex_index),stage.vertex->GetGPUVirtualAddress());
            const D3D12_VIEWPORT vp{0,0,static_cast<float>(spec.width),static_cast<float>(spec.height),0,1};const D3D12_RECT rect{0,0,spec.width,spec.height};list->RSSetViewports(1,&vp);list->RSSetScissorRects(1,&rect);list->OMSetRenderTargets(1,&t.rtv,FALSE,nullptr);
            list->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);list->IASetVertexBuffers(0,1,&vbv);list->DrawInstanced(6,1,0,0);transition(list,t.resource.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
        }return true;
    }
    ID3D12Resource* output(int id)const{return textures.at(id).resource.Get();}
    ComPtr<ID3DBlob> cache(int event)const{
        for(const auto& stage:stages)if(stage.spec.event==event){ComPtr<ID3DBlob> blob;check(stage.pso->GetCachedBlob(&blob));return blob;}
        throw std::runtime_error("Unknown native pass");
    }
};
// Executes the game's final BlendPS unchanged. Inputs must already be immutable
// PS_RESOURCE snapshots with the original native numeric color domain. This API
// deliberately does not convert an OpenXR eye buffer or invent missing layers.
class FinalBlend {
    Recorder& owner;Stage stage{};ComPtr<ID3D12Resource> view,rectangle;
    std::vector<unsigned char> vertex_code,pixel_code;
    D3D12_GRAPHICS_PIPELINE_STATE_DESC known_description{};
public:
    struct Input {ID3D12Resource* resource=nullptr;DXGI_FORMAT format=DXGI_FORMAT_UNKNOWN;};
    explicit FinalBlend(Recorder& recorder):owner(recorder){
        auto* d=owner.device.Get();stage.root=owner.r1033.Get();
        vertex_code=Recorder::read(owner.assets/L"pso-4278-VS.dxbc");pixel_code=Recorder::read(owner.assets/L"pso-4278-PS.dxbc");
        // Use the same native fullscreen pipeline state as the generation pass,
        // replacing only the captured final shader and its BGRA output format.
        D3D12_GRAPHICS_PIPELINE_STATE_DESC pd{};
        static const D3D12_INPUT_ELEMENT_DESC input[]={{"ATTRIBUTE",0,DXGI_FORMAT_R32G32B32A32_FLOAT,0,0,D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0},{"ATTRIBUTE",1,DXGI_FORMAT_R32G32_FLOAT,0,16,D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,0}};
        pd.pRootSignature=stage.root;pd.VS={vertex_code.data(),vertex_code.size()};pd.PS={pixel_code.data(),pixel_code.size()};pd.InputLayout={input,2};pd.SampleMask=UINT_MAX;
        pd.PrimitiveTopologyType=D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;pd.NumRenderTargets=1;pd.RTVFormats[0]=DXGI_FORMAT_B8G8R8A8_UNORM;pd.SampleDesc.Count=1;
        pd.RasterizerState.FillMode=D3D12_FILL_MODE_SOLID;pd.RasterizerState.CullMode=D3D12_CULL_MODE_NONE;pd.RasterizerState.FrontCounterClockwise=TRUE;pd.RasterizerState.DepthClipEnable=TRUE;pd.RasterizerState.MultisampleEnable=TRUE;
        pd.DepthStencilState.DepthWriteMask=D3D12_DEPTH_WRITE_MASK_ZERO;pd.DepthStencilState.DepthFunc=D3D12_COMPARISON_FUNC_ALWAYS;
        pd.BlendState.IndependentBlendEnable=TRUE;pd.DepthStencilState.StencilReadMask=pd.DepthStencilState.StencilWriteMask=255;
        pd.DepthStencilState.FrontFace=pd.DepthStencilState.BackFace={D3D12_STENCIL_OP_KEEP,D3D12_STENCIL_OP_KEEP,D3D12_STENCIL_OP_KEEP,D3D12_COMPARISON_FUNC_ALWAYS};
        for(auto& b:pd.BlendState.RenderTarget){b.SrcBlend=b.SrcBlendAlpha=D3D12_BLEND_ONE;b.DestBlend=b.DestBlendAlpha=D3D12_BLEND_ZERO;b.BlendOp=b.BlendOpAlpha=D3D12_BLEND_OP_ADD;b.LogicOp=D3D12_LOGIC_OP_CLEAR;b.RenderTargetWriteMask=D3D12_COLOR_WRITE_ENABLE_ALL;}
        known_description=pd;check(d->CreateGraphicsPipelineState(&pd,IID_PPV_ARGS(&stage.pso)));
        D3D12_DESCRIPTOR_HEAP_DESC hd{};hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;hd.NumDescriptors=64;hd.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&stage.srvs)));
        hd.Type=D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER;hd.NumDescriptors=32;check(d->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&stage.samplers)));
        const auto stride=d->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER);
        // Captured sampler heap 1041, slots 669/670/671: clamp, wrap, clamp.
        for(UINT i=0;i<3;i++){D3D12_SAMPLER_DESC sd{};sd.Filter=D3D12_FILTER_MIN_MAG_LINEAR_MIP_POINT;sd.AddressU=sd.AddressV=sd.AddressW=i==1?D3D12_TEXTURE_ADDRESS_MODE_WRAP:D3D12_TEXTURE_ADDRESS_MODE_CLAMP;sd.MaxLOD=FLT_MAX;sd.MaxAnisotropy=1;sd.ComparisonFunc=D3D12_COMPARISON_FUNC_NEVER;
            D3D12_CPU_DESCRIPTOR_HANDLE h{stage.samplers->GetCPUDescriptorHandleForHeapStart().ptr+i*stride};d->CreateSampler(&sd,h);}
        stage.pixel=owner.buffer(L"event-3384-PS-root-parameters.bin");view=owner.buffer(L"event-3384-View.bin");rectangle=owner.buffer(L"event-3384-VS-constants.bin");
        owner.texture(4270,2560,1440,DXGI_FORMAT_B8G8R8A8_UNORM);
    }
    // Caller must fence prior uses before descriptor updates and retain inputs
    // through completion. No blank substitutes or encoding guesses are supplied.
    bool record(ID3D12GraphicsCommandList* list,const Input (&inputs)[13]){
        if(!list||inputs[0].format!=DXGI_FORMAT_R16G16B16A16_FLOAT)return false;
        auto& output=owner.textures.at(4270);
        for(const auto& input:inputs){if(!input.resource||input.resource==output.resource.Get()||input.format==DXGI_FORMAT_UNKNOWN)return false;
            const auto desc=input.resource->GetDesc();if(desc.Dimension!=D3D12_RESOURCE_DIMENSION_TEXTURE2D||desc.SampleDesc.Count!=1||desc.DepthOrArraySize!=1)return false;}
        for(UINT i=0;i<13;i++){D3D12_SHADER_RESOURCE_VIEW_DESC sv{};sv.Format=inputs[i].format;sv.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2D;sv.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;sv.Texture2D.MipLevels=1;
            D3D12_CPU_DESCRIPTOR_HANDLE h{stage.srvs->GetCPUDescriptorHandleForHeapStart().ptr+i*owner.sr_stride};owner.device->CreateShaderResourceView(inputs[i].resource,&sv,h);}
        Recorder::transition(list,output.resource.Get(),D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,D3D12_RESOURCE_STATE_RENDER_TARGET);
        ID3D12DescriptorHeap* heaps[]={stage.srvs.Get(),stage.samplers.Get()};list->SetDescriptorHeaps(2,heaps);list->SetPipelineState(stage.pso.Get());list->SetGraphicsRootSignature(stage.root);
        list->SetGraphicsRootDescriptorTable(0,stage.srvs->GetGPUDescriptorHandleForHeapStart());list->SetGraphicsRootDescriptorTable(1,stage.samplers->GetGPUDescriptorHandleForHeapStart());list->SetGraphicsRootConstantBufferView(2,stage.pixel->GetGPUVirtualAddress());list->SetGraphicsRootConstantBufferView(3,view->GetGPUVirtualAddress());list->SetGraphicsRootConstantBufferView(4,rectangle->GetGPUVirtualAddress());
        const D3D12_VIEWPORT vp{0,0,2560,1440,0,1};const D3D12_RECT rect{0,0,2560,1440};list->RSSetViewports(1,&vp);list->RSSetScissorRects(1,&rect);list->OMSetRenderTargets(1,&output.rtv,FALSE,nullptr);
        const D3D12_VERTEX_BUFFER_VIEW vbv{owner.vb->GetGPUVirtualAddress(),144,24};list->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);list->IASetVertexBuffers(0,1,&vbv);list->DrawInstanced(6,1,0,0);
        Recorder::transition(list,output.resource.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);return true;
    }
    ID3D12Resource* output()const{return owner.output(4270);}
    ComPtr<ID3DBlob> cache()const{ComPtr<ID3DBlob> blob;check(stage.pso->GetCachedBlob(&blob));return blob;}
    HRESULT validate_cache(ID3DBlob* blob)const{
        if(!blob||!blob->GetBufferSize())return E_INVALIDARG;
        auto description=known_description;description.CachedPSO={blob->GetBufferPointer(),blob->GetBufferSize()};
        ComPtr<ID3D12PipelineState> candidate;return owner.device->CreateGraphicsPipelineState(&description,IID_PPV_ARGS(&candidate));
    }
};
}
