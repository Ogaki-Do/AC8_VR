// Recognize UEVR-owned command lists by their established D3D12 object names.
// This ownership filter prevents the renderer from altering arbitrary game lists;
// the name lookup is part of rendering validation, not debug output.

#pragma once
#include <d3d12.h>
#include <string>
namespace destination {
inline bool isolated_list(ID3D12GraphicsCommandList* list, std::wstring& name) {
    if (list->GetType() != D3D12_COMMAND_LIST_TYPE_DIRECT) return false;
    wchar_t buffer[192]{}; UINT n = sizeof(buffer) - sizeof(wchar_t);
    if (FAILED(list->GetPrivateData(WKPDID_D3DDebugObjectNameW, &n, buffer))) return false;
    buffer[191] = 0; name = buffer;
    return name.rfind(L"OpenXR commands ", 0) == 0 || name == L"OpenVR UI";
}
}
