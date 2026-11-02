// Version boundary for UEVR's private OpenXR wrapper. The file hash, PE metadata
// and instruction signature must agree before any fixed address is hooked.
// These constants identify a supported binary; they are not user data.

#pragma once
#include <bcrypt.h>
#include <vector>
#include <string>

namespace boundary {
constexpr DWORD wrapper_rva=0x2ba0b0, expected_timestamp=1788064879, expected_size=11649024;
constexpr char expected_hash[]="1A34CF65E4C12002EC967ED167DDDA4E1CC7AE1DA82157D0E279597BEDDEED75";
constexpr unsigned char signature[]={0x48,0x89,0x5c,0x24,0x18,0x57,0x48,0x81,0xec,0xb0,0,0,0,0x48,0x8b,0x05,0x7c,0x3e,0x7c,0,0x48,0x33,0xc4,0x48,0x89,0x84,0x24,0xa8,0,0,0,0x48};

// Hash a file without loading or executing it. This protects the private RVA.
inline bool file_hash(const wchar_t* path,std::string& result) {
    BCRYPT_ALG_HANDLE alg=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
    HANDLE file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE)return false;
    DWORD bytes=0,object_size=0;bool ok=false;
    std::vector<unsigned char> object,chunk(65536);unsigned char digest[32]{};
    if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)>=0 &&
       BCryptGetProperty(alg,BCRYPT_OBJECT_LENGTH,reinterpret_cast<PUCHAR>(&object_size),sizeof(object_size),&bytes,0)>=0) {
        object.resize(object_size);
        if(BCryptCreateHash(alg,&hash,object.data(),object_size,nullptr,0,0)>=0) {
            ok=true;
            for(;;) {
                if(!ReadFile(file,chunk.data(),static_cast<DWORD>(chunk.size()),&bytes,nullptr)){ok=false;break;}
                if(!bytes)break;
                if(BCryptHashData(hash,chunk.data(),bytes,0)<0){ok=false;break;}
            }
            if(ok)ok=BCryptFinishHash(hash,digest,sizeof(digest),0)>=0;
        }
    }
    if(hash)BCryptDestroyHash(hash);if(alg)BCryptCloseAlgorithmProvider(alg,0);CloseHandle(file);
    if(ok){static const char hex[]="0123456789ABCDEF";result.clear();for(auto byte:digest){result+=hex[byte>>4];result+=hex[byte&15];}}
    return ok;
}
inline bool image_matches(const unsigned char* base) {
    __try {
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE||dos->e_lfanew<0||dos->e_lfanew>4096)return false;
        const auto* nt=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        return nt->Signature==IMAGE_NT_SIGNATURE && nt->FileHeader.Machine==IMAGE_FILE_MACHINE_AMD64 &&
            nt->FileHeader.TimeDateStamp==expected_timestamp && nt->OptionalHeader.SizeOfImage==expected_size &&
            memcmp(base+wrapper_rva,signature,sizeof(signature))==0;
    }__except(EXCEPTION_EXECUTE_HANDLER){return false;}
}
inline bool confirm_force_glow(const wchar_t* reason) {
    static int cached_choice = 0;
    if (cached_choice != 0) return cached_choice == IDYES;
    wchar_t msg[512]{};
    wsprintfW(msg,
        L"UEVRBackend.dll の検証チェックで不一致が検出されました。\n"
        L"理由: %s\n\n"
        L"[はい (Yes)] Glowを強制実行する\n"
        L"[いいえ (No)] 安全のためGlowを停止する",
        reason ? reason : L"Hash / Signature mismatch");
    const int ret = MessageBoxW(nullptr, msg, L"AC8 VR - Glow Security Guard", MB_YESNO | MB_ICONWARNING | MB_TOPMOST | MB_SETFOREGROUND);
    cached_choice = ret;
    return ret == IDYES;
}
}
