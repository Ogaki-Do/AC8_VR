# ogaki-ac8vr 実装リバースエンジニアリング詳細分析書

## 1. 概要と背景

本ドキュメントは、ACE COMBAT 8（AC8）を UEVR（Universal Unreal Engine VR Mod）および OpenXR（DirectX 12 / Native Stereo）環境で快適にプレイするために開発されたプロファイル＆コンパニオン・ネイティブプラグイン **`ogaki-ac8vr`** の実装状態、実現手法、アーキテクチャをソースコードからリバースエンジニアリングして詳細に解明したものです。

### 1.1 背景と開発の歴史（`before_mankeroo` からの進化）

リポジトリ内の過去の検証記録（`before_mankeroo` 配下のポストモーテム群）から、以下の苦闘と技術的ブレークスルーが確認できます：

1. **初期の挫折（自前UI描画の失敗）**:
   - 当初、消えたHUDやターゲット枠を補うため「自前でUIを作って描画しよう」と試みられたが、UEVR/Lua環境には実行時に新規Slateウィジェットを作成する機能がなく、DirectXオーバーレイ（ImGui等）はVRビューポート空間に正しく固定されない上、出撃時・マップ切り替え時にレンダラースレッド側でヌルポインタ参照クラッシュ（Error 0）を引き起こし完全断念された。
   - **真実の教訓**: *「ゲーム内に元々存在している公式ネイティブHUDアセットを発掘・流用・外科手術的に補正することだけが、VR内に確実かつ美麗にUIを表示させる唯一の方法である」*。

2. **人工水平儀（ピッチラダー）の復元成功**:
   - ゲーム本体は `LiveWidgetToTextureSystem`（中間レンダーターゲット）で姿勢計をコックピットガラスに投影していたが、UEVRのステレオ描画フック時にこの中間層が脱落して水平線が消失していた。
   - `WBP_HUD_Chronicle_MainFlight_000_C` の深層に眠る公式ウィジェット `LandingGuide` を発掘し、公式テクスチャ `T_HUD_PitchMeter_MarkCenter_001` を流し込んで姿勢角追従させることで、自前UIを一切作らずに完全復元を達成した。

3. **ビルボード（3Dターゲット枠）サイズ変更の壁と突破**:
   - 敵味方の四角枠（`ChronicleTargetContainerActorBP_C` の `ContainerBox`）は `UMaterialBillboardComponent` で描画される。Unreal Engine の C++ `FMaterialBillboardSceneProxy` はカメラ正対クアッドを生成する際、**トランスフォームのスケール値を内部で意図的に破棄・無視する仕様**になっていた。そのため、Luaから `SetActorScale3D` や `SetRelativeScale3D` を呼んでもサイズは1ミリも変わらなかった。
   - これに対し、`ogaki-ac8vr` では **C++ ネイティブプラグインから UEVR のリフレクションAPIを駆使して内部構造体配列 `Elements` の `BaseSizeX/Y` を直接操作し、`SetElements` メソッドを呼ぶ** という離れ業で、長年「不可能」とされていたビルボードのリサイズを完全に実現した。

---

## 2. 全体アーキテクチャ

`ogaki-ac8vr` は、**「C++ ネイティブプラグイン（`AC8_VR-Runtime.dll`）」** と **「9つの協調動作型 Lua スクリプト」**、および **「カスタム HLSL シェーダー」** による高度なハイブリッド構造を採用しています。

```
[ ACE COMBAT 8 Game Engine (UE / DX12) ]
                   │
    ┌──────────────┴──────────────┐
    ▼                             ▼
[ UEVR Core / OpenXR Hook ]   [ Game Binary / Memory ]
    │                             │ (Inline Hooks: RVA)
    │ (C API Callbacks)           ▼
    ├──────────────────► [ AC8_VR-Runtime.dll ]
    │                     ├─ backend_boundary.h (PE / SHA256 / Sig Guard)
    │                     ├─ escort-billboard-scale.h (SetElements Hack)
    │                     ├─ offscreen-indicators.cpp (Locator Vertex Shift)
    │                     ├─ target-lock-reticle.cpp (Seeker 0.25 Scale)
    │                     ├─ hud-tick-guards.cpp (Stack BackTrace Double-Tick Guard)
    │                     ├─ cinematic-game-hooks.cpp (F7 Hook / Pause / Mask)
    │                     └─ hud-renderer.cpp + HLSL (D3D12 Copy / Glow / Ray-Cylinder)
    │
    ▼ (Lua Callbacks)
[ Lua Script Layer (AC8_VR-Core.lua) ]
    ├─ Presentation Domain: AC8_VR-CinematicPresentation.lua
    ├─ Layout Domain:       AC8_VR-HUDLayout.lua, AC8_VR-InheritedHUD.lua
    ├─ Utility Domain:      AC8_VR-WorldTargets.lua, AC8_VR-PlaneCamera.lua,
    │                       AC8_VR-LoadingTransitions.lua, AC8_VR-UIRendering.lua
    └─ Intro Domain:        AC8_VR-StartupMovies.lua
```

---

## 3. C++ ネイティブプラグインの実装詳細

単一の DLL（`AC8_VR-Runtime.dll`、約556KB）に以下の6つのモジュールがコンパイル・リンクされています。各モジュールは独立して初期化され、1つが失敗しても他を巻き込まない耐障害性を持っています。

### 3.1 バイナリガードと整合性検証（`backend_boundary.h`）

メモリへの固定アドレス・インラインフックを行う前に、実行中プロセスの安全性を厳格に保証します。

```cpp
namespace boundary {
constexpr DWORD wrapper_rva=0x352a50, expected_timestamp=1790232505, expected_size=12853248;
constexpr char expected_hash[]="70CCBAAF4C357DEAACC3990FD01A911A029D31DCCF0E5ABC01C7A9073E4F50C1";
constexpr unsigned char signature[]={0x48,0x89,0x5c,0x24,0x18,0x57,0x48,0x81,0xec,0xb0, ...};
```

- **PEヘッダー検査**: `TimeDateStamp`, `SizeOfImage`, マシンアーキテクチャ（x64）を検査。
- **SHA-256 ファイルハッシュ検証**: `BCrypt` API を使用してファイルのハッシュ値を計算・照合。
- **命令シグネチャ一致確認**: フック先のアセンブリ命令バイト列を事前比較。
- **効果**: ゲームのアップデートや異なるUEVRバージョンでクラッシュするのを未然に防ぎ、不一致時は安全にフックをスキップ。

### 3.2 ワールドターゲット・ビルボードサイズ制御（`escort-billboard-scale.h`）

Unreal Engine の `UMaterialBillboardComponent` はトランスフォームの `Scale3D` を無視するため、内部データ構造に直接介入します。

```cpp
// 1. UEVR のリフレクションから Elements プロパティを走査
auto p = property(cls, L"Elements");
// 2. StructProperty 内の BaseSizeX / BaseSizeY オフセットを特定
for(auto spec : {std::pair(L"BaseSizeX", &v.x), {L"BaseSizeY", &v.y}}) ...
// 3. 元のサイズを退避・保持し、要求倍率 (pin_scale) を乗算
std::memcpy(entries.data() + i*stride + v.x, &desired[i].x, 4);
std::memcpy(entries.data() + i*stride + v.y, &desired[i].y, 4);
// 4. Unreal Engine の内部関数 SetElements を process_event で呼び出す！
host->sdk->uobject->process_event(o, fn, params.data());
```

- **可逆性の確保**: ゲーム側がサイズを変更した際も差分を検知し、前回のスケール値に重複して乗算される（極小化する）事故を防止。
- **成果**: 敵・味方・エスコート対象のビルボード枠を、VRで見やすいサイズに自由自在にスケーリング可能にした。

### 3.3 画面外ロケーター矢印の頂点シフト（`offscreen-indicators.cpp`）

画面外の敵を示すロケーター矢印は、ゲームバイナリ内の描画関数（RVA `119793440`）をインラインフックして制御します。

- 描画関数呼び出し直前の頂点バッファの生成開始位置を記録。
- 当該関数が放出した頂点座標（Point X, Y）のみを特定し、指定のオフセットおよびスケール値で変形。
- 他のHUD描画や中心座標には一切干渉しないスコープ付き変更を実現。

### 3.4 シーカー（ロックオン枠）アートワークの縮小（`seeker-auto.h`）

ゲームバイナリの RVA `0x72a3f00` をインラインフック。

- 対象アクターが `BP_ChronicleTexture3DUIActor_C` かつテクスチャが `T_HUD_Seeker01_...` / `02_...` であることを厳格に判定。
- 引数のサイズ構造体を `0.25` 倍に縮小。
- フック適用前に、ゲーム側のリードバック値と一致するかを自動テストし、整合性が確認された場合のみスケーリングを有効化（自己検証機構）。

### 3.5 二重ティック防止ガード（`hud-tick-guards.cpp`）

UEVR で VR レンダリングを行う際、通常のビューポート更新と VR 用テクスチャ更新の双方からウィジェットの `Tick` が呼ばれてしまう **Double Tick（二重ティック）問題** が発生します。これにより、ミサイル接近警告の点滅やタイマー、メッセージの表示時間が2倍速で消費されてしまうバグが生じていました。

```cpp
enum class Route:unsigned {Unknown=0, ExtraViewport=1, NativeTexture=2, Mixed=3};
static Route currentRoute(){
    std::array<void*,48> stack{};
    USHORT count = CaptureStackBackTrace(0, (DWORD)stack.size(), stack.data(), nullptr);
    return classify(stack.data(), count, (uintptr_t)GetModuleHandleW(nullptr));
}
```

- `CaptureStackBackTrace` を使用して呼び出し元のコールスタック（リターンアドレス）を瞬時に解析。
- `ExtraViewport`（重複した余分なビューポート呼び出し）と判定された場合のみティックを抑制し、正規の `NativeTexture` 呼び出しは完全に通過させる。
- これにより、警告表示・HUD点滅・メッセージタイマーの正常化を達成。

### 3.6 D3D12 コマンドリスト監視と OpenXR レイヤ合成（`hud-renderer.cpp`）

- D3D12 の `CopyTextureRegion`, `ResourceBarrier`, `ExecuteCommandLists` をフック。
- ゲームエンジンがレンダリングした UI レンダーターゲットを監視。
- レンダリング完了フェンス（`ID3D12Fence`）でリソースの競合を完全に排除した上で、OpenXR のスワップチェーンイメージへカスタムシェーダー経由で合成。

---

## 4. カスタム HLSL シェーダーの実装詳細

`source_code/src/renderer/` に含まれる HLSL シェーダーは、ゲーム本来の描画パイプラインを忠実に再現・拡張しています。

### 4.1 パレット混合の連立方程式解決（`hud_route_preview.hlsl`）

HUDの警告赤色と通常緑色が重なった際、単なる最大輝度計算では誤って「不透明な暗いパネル」と誤認され、グロー（発光）が消えてしまう問題がありました。
シェーダー内で赤・緑のパレットウェイト連立方程式をリアルタイムに解くことで、正確なブレンドを実現しています：

```hlsl
const float3 red = float3(137.0/140, 27.0/140, 19.0/140);
const float3 green = float3(44.0/140, 1, 35.0/140);
float redWeight = (source.r - green.r * source.g) / (red.r - green.r * red.g);
float greenWeight = source.g - red.g * redWeight;
float predictedBlue = red.b * redWeight + green.b * greenWeight;
```

### 4.2 レイ・シリンダー交差判定による逆写像（`scene_mapping.hlsli`）

VR空間における円筒曲面UI（シリンダーHUD）と、各目の視錐台（OpenXR FOV tangents）との幾何学的な対応関係を、レイトレーシング（Ray-Cylinder Intersection）の数式を解いてピクセル単位で正確に逆写像しています：

```hlsl
// 目から出るレイと円筒の交差方程式 a*t^2 + b*t + c = 0
float a = dot(direction.xz, direction.xz);
float b = 2 * dot(origin.xz, direction.xz);
float c = dot(origin.xz, origin.xz) - radius * radius;
float disc = b * b - 4 * a * c;
// 解 t から円筒表面の UV 座標 (角度と高さ) を逆算
float2 uv = float2(0.5 + atan2(p.x, -p.z) / angle,
                   0.5 - p.y / (radius * angle / SceneSizeAspect.z));
```

これにより、曲面HUDの歪みと背景シーンが完全に一致し、VR酔いや表示ズレのない美麗なコックピットHUD描画を実現しています。

---

## 5. Lua スクリプト群の実装詳細

配布される9つの Lua スクリプトは、以下のような責務分担と徹底的な防御的プログラミングで構築されています。

| スクリプト | 責務と実装手法 |
|---|---|
| `AC8_VR-Core.lua` | **中核オーケストレーター**。<br>・`AC8VRModules` グローバルレジストリによる動的セクション管理（17セクション）。<br>・ファイル名プレフィックス（`01_`, `02_` 等）への依存を排除し、依存順序（Presentation → Layout → Utility → Intro）で確実起動。<br>・`UObjectHook.exists` によるオブジェクト生存確認（Dangling Pointer参照クラッシュの完全防止）。<br>・同一フレーム＆同一HUDエポック内でのウィジェットツリー走査キャッシュ。 |
| `AC8_VR-HUDLayout.lua` | **HUDレイアウト＆UI設定**。<br>・起動時に1回だけ曲面シリンダーHUD（奥行き1.0m, スケール1.0, 曲率113.625°）をトランザクション適用。<br>・ユーザーが後からUEVRメニューで手動調整した値を上書きし続けない配慮。<br>・僚機ステータスの配置とレーダーモード切り替え追従（3ティック周期更新）。 |
| `AC8_VR-InheritedHUD.lua` | **計器・ピッチラダー調整**。<br>・旧世代の成果を統合。Slateウィジェットの発掘とリフレクションによるトランスフォーム適用。<br>・HUDLayout が有効化されるまで初期化を遅延待機。 |
| `AC8_VR-WorldTargets.lua` | **ワールドターゲット＆アニメーション保護**。<br>・ターゲット出現時の「大→小」に縮小する公式アニメーションを壊さないよう、`ContainerBoxImageSize` と `SelectTargetAddContainerBoxSize` をポストティックでスケール調整・ロールバック管理。<br>・C++プラグインへのパケット送信（`AC8_WorldTargetLayout`, `AC8_WorldPipScale`）。<br>・シアン色動的マテリアルの彩度調整。 |
| `AC8_VR-PlaneCamera.lua` | **機体別カメラ位置オフセット**。<br>・`data/AC8_VR-PerPlaneCameraOffsets.lua` を安全なサンドボックス（`load(text, ..., 't', {})`）でパース。<br>・機体の `LiveFirstPersonCameraComponent` を厳格に特定し、機体ごとに絶対UEVRカメラオフセット（F/A-18C: -18/0/5, F-4E: -10/0/5）を適用。<br>・シネマティックや格納庫がカメラを所有している間は干渉を自動抑制。 |
| `AC8_VR-CinematicPresentation.lua` | **シネマティック＆格納庫制御**。<br>・レンダリングハートビート監視（`cutscene_guard`）：描画停止時に一時的に `VR_2DScreenMode = true` へ退避しクラッシュ・暗転フリーズを防止。<br>・F7キー入力による手動切り替え。<br>・シネマティック用カメラ／レターボックスマスク制御と、終了時の完全復元ジャーナル。 |
| `AC8_VR-LoadingTransitions.lua` | **ロード画面＆フェード管理**。<br>・単なる固定タイマーではなく、`GameInstance` から `LiveLoadingScreenSubsystem` および `WBP_MissionLoad_ManagerWidget_000_C` の階層を辿って、真のロード中状態を正確に判定。<br>・黒画面フェードとの同期で、VR空間でのマップチラ見えを防止。 |
| `AC8_VR-UIRendering.lua` | **発光ライフサイクル＆ウィジェットポリシー**。<br>・フライト開始／終了／ポーズの遷移を監視し、`AC8_HUD_GlowLifecycle` イベントをC++へ通知。<br>・全ウィジェットのペイント空間ジオメトリから矩形ポリシーパケット（`AC8_HUD_PolicyV50`）を構築し、C++のグローシェーダーへ提供。<br>・ポーズメニュー操作の1入力1ステップ化（二重入力スキップ防止）。 |
| `AC8_VR-StartupMovies.lua` | **起動ロゴ・ムービースキップ**。<br>・起動時の各種ロゴムービー（AcesLogo等）や注意画面の待ち時間を自動短縮・シーク。<br>・起動後90秒で自動的に監視を終了し、ゲーム本来の設定に完全復元。 |

---

## 6. まとめ

`ogaki-ac8vr` は、単なる UEVR の設定プリセットや単純な Lua スクリプトの域を遥かに超え、**「Unreal Engine 内部構造体のメモリリフレクション操作」**、**「実行時バイナリのインラインアセンブリフック」**、**「コールスタック解析による二重ティック抑制」**、**「D3D12コマンドリスト監視とOpenXR直結のカスタムHLSLシェーダー」** を融合させた、極めて高度かつ洗練されたエンジニアリングの結晶です。
これまでの数多くの試行錯誤（`before_mankeroo`）の知見がすべて活かされ、VR空間での安定性と公式クオリティを極限まで両立させた見事なアーキテクチャとなっています。
