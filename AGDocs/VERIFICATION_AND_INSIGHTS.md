# ogaki-ac8vr 実装検証・ログ分析・技術考察書

## 1. 検証結果サマリー

プロジェクト `ogaki-ac8vr` のソースコード、アセット、実機プロファイル（`%APPDATA%\UnrealVRMod\AceCombat8`）、および実行ログ（`log.txt`）を対象に総合的な検証を実施しました。

### 1.1 検証マトリクス

| 検証項目 | 対象 | 結果 | 詳細・補足 |
|---|---|:---:|---|
| **JSON 構文整合性** | `ogaki-ac8vr/data/` 内の全10ファイル、`modules.json` | **合格** | 全ファイルが標準 JSON 規格に準拠。構文エラーなし。 |
| **レンダリングアセット** | `runtime-assets.txt` にリストされた44ファイル | **合格** | ソースおよび `plugins/ac8-hud-assets/` の全44ファイルが欠落なく完全一致。 |
| **DLL バイナリ整合性** | `plugins/AC8_VR-Runtime.dll` | **合格** | リポジトリ版と実機 `%APPDATA%` 版の SHA-256（`b9fa1866...`）およびサイズ（556,032 bytes）が完全一致。 |
| **Lua スクリプト整合性** | `scripts/` 配下の全9スクリプト | **合格** | 改行コード（LF vs CRLF）の正規化後、内容が完全一致。 |
| **ネイティブフック初期化** | 実機実行ログ（`log.txt`） | **合格** | 6つの全モジュール（cinematic, escort, glow, warning, arrow, lock）が `initialized=1` で正常起動。 |
| **Lua システム初期化** | 実機実行ログ（`log.txt`） | **合格** | 全9スクリプトがエラーなく起動し、17セクションが完全登録・起動。 |

---

## 2. 実機ログ（`log.txt`）の精査とトラブルシューティング

直近の実行ログ（`log.txt`）を精査した結果、以下の2つの重要事象が確認されました。

### 2.1 事象①: JSON パースエラーログの多発

#### ログ内容
```
[UnrealVR] [error] [JSON] Failed to load file ac8_cinematic_intent_control.json: 
[json.exception.parse_error.101] parse error at line 1, column 1: 
syntax error while parsing value - unexpected end of input; expected '[', '{', or a literal
```

#### 原因分析
- `AC8_VR-CinematicPresentation.lua` 内の以下のコードが約0.25秒間隔でポーリング実行されています：
  ```lua
  local function command()
      local ok, row = pcall(function() return json.load_file('ac8_cinematic_intent_control.json') end)
      if ok and type(row) == 'table' then return row end
  end
  ```
- UEVR の `json.load_file`（C++ の nlohmann::json 実装）は、ファイルが存在しない場合や空ファイルの場合、例外を捕捉して UEVR ログに `[error] [JSON] Failed to load file...` を出力します。
- Lua 側では `pcall` で保護されているため**スクリプト自体のクラッシュには至っていません**が、ログが急速に肥大化する原因となっています。
- 同様に `ac8_cinematic_ui_restore.json`, `ac8_hangar_restore_v48.json`, `ac8_workshop_effect_controls.json` も起動直後に存在しないために初回エラーが出力されています。

#### 推奨対策
1. `data/ac8_cinematic_intent_control.json` として、デフォルトの空JSONオブジェクト `{}` を配置しておく。
2. または、Lua 側で `fs.read` 等の存在チェックを先に行い、ファイルが存在しない場合は `json.load_file` を呼ばないガードを追加する。

---

### 2.2 事象②: 14:04 のクラッシュログ（`crash.dmp`）の解析

#### ログ内容
```
[2026-10-14 14:04:23.373] [UnrealVR] [warning] [FFakeStereoRenderingHook.cpp:2903] Something strange is going on, the vtable is already hooked, maybe previous frame was not rendered?
...
[2026-10-14 14:04:43.948] [UnrealVR] [error] Exception occurred: c0000005
[2026-10-14 14:04:43.948] [UnrealVR] [error] RIP: 7ff82424fcb2
[2026-10-14 14:04:43.948] [UnrealVR] [error] Module: 7ff824240000 C:\Program Files\Virtual Desktop Streamer\VirtualDesktop.LibOVRRT64_1.dll
[2026-10-14 14:04:43.949] [UnrealVR] [error] Attempting to write dump to ...\crash.dmp
```

#### 原因分析
- クラッシュのアドレスは MOD 自体（`AC8_VR-Runtime.dll`）ではなく、**Virtual Desktop のランタイムモジュール `VirtualDesktop.LibOVRRT64_1.dll` 内部** で発生したアクセス違反（`c0000005`）です。
- 直前に `[FFakeStereoRenderingHook.cpp:2903] Something strange is going on, the vtable is already hooked, maybe previous frame was not rendered?` が頻発しています。これは、ゲーム描画フレームの提出（Submit）と OpenXR のフレーム同期（WaitFrame / BeginFrame）のタイミングが外れ、フレーム落ちや描画ストールが発生していたことを示しています。
- Virtual Desktop Streamer が LibOVR 互換レイヤー経由で OpenXR スワップチェーンを処理する際、ゲーム終了時またはフォーカス喪失／HMDスリープ時に不正ポインタを参照した可能性が高いです。

#### 推奨対策
1. **ランタイムの推奨設定**: Virtual Desktop 利用時は、OpenXR ランタイムとして **VDXR (Virtual Desktop OpenXR)** をネイティブ選択し、Oculus/LibOVR 互換モードを介さない設定にする。
2. **UEVR の設定**: `config.txt` にある `OpenXR_IgnoreVirtualDesktopChecks=false` や `VR_AFW_UltraResponsive=true` が適切に機能しているか確認し、フレーム遅延補償を見直す。

---

## 3. 技術的考察（Deep Insights）

### 3.1 「自前UI作成」の失敗と「ネイティブ発掘＋外科手術的フック」の勝利

UEVR 開発において最も陥りやすい罠は、*「ゲームのUIがVRで狂っているなら、それを非表示にして自前でUIを作ってしまえばいい」* という発想です。
本プロジェクトの初期（`before_mankeroo`）でもこの試行が行われましたが、以下の致命的な壁に衝突しました：

1. **スレッド安全性と同期の壁**:
   Unreal Engine はゲームロジックスレッド（GameThread）、スレート描画スレッド（Slate/Viewport）、DirectX レンダラースレッド（RHIThread）が厳格に分離されています。Luaから新規アクターやUIを即時生成して毎フレーム描画しようとすると、出撃時やマップロード時のスレッド競合で確実にヌルポインタ参照クラッシュ（c0000005）を引き起こします。
2. **アセット品質とゲーム連携の壁**:
   自前UIは、ゲーム本体が持つ動的アニメーション（敵ロック時のシーカー回転、ターゲット出現時の大→小アニメーション、パレット変化、ダメージ警告連動）を再現できません。

`ogaki-ac8vr` が採用した **「ゲーム本体のネイティブウィジェットを発掘し、UEVRリフレクションやインラインフックで外科手術的に補正する」** アプローチは、以下の決定的なメリットをもたらしました：
- **クラッシュフリー**: ゲームエンジンの既存ライフサイクルに乗っかるため、スレッド競合が発生しない。
- **完全な公式ルック＆フィール**: 公式テクスチャ、フォント、マテリアル、アニメーションが100%維持される。
- **超軽量**: 描画負荷はゲーム本来のものとほぼ同等。

---

### 3.2 ビルボードスケーリング（`UMaterialBillboardComponent`）突破の歴史的意義

UE4/UE5 を用いたフライトシミュレーターや戦闘機ゲームをVR化する際、世界中のMOD開発者が頭を抱えてきたのが **「3Dターゲットマーカー（四角枠）がコックピット正面で巨大すぎて前が見えない」** という問題です。

Unreal Engine の `UMaterialBillboardComponent` は、エンジンの C++ ソースコード（`FMaterialBillboardSceneProxy::GetDynamicMeshElements`）内で、アクターやコンポーネントの `Scale3D` を意図的に破棄し、固定ピクセルサイズで板ポリゴンを生成します。そのため、BlueprintやLuaからいくら `SetWorldScale3D` を呼んでもサイズは絶対に変わりません。

`ogaki-ac8vr` は、以下の手法でこれを打ち破りました：
1. UEVR の低レイヤーリフレクションでコンポーネント内部の `Elements` 配列を特定。
2. `BaseSizeX` / `BaseSizeY` の浮動小数点オフセットを直接書き換え。
3. `process_event` 経由で C++ の `SetElements` 関数を呼び出す。
4. これにより、エンジンがプロキシを再構築し、**公式仕様の壁を越えてビルボードのサイズ変更に成功した**。

このアプローチは、AC8 だけでなく、他のあらゆる Unreal Engine 製ゲームのVR化にも応用可能な極めて価値の高い技術的ブレークスルーです。

---

### 3.3 コールスタック解析（`CaptureStackBackTrace`）による二重ティック抑制

VR化MODにおいて、ゲームの「警告音」や「ミサイルアラートの点滅周期」が2倍速になってしまうというバグは、非常に気づきにくく、かつ原因究明が難しい問題です。

UEVR が Native Stereo モードで動作する場合、ゲーム本来のビューポート描画パイプラインと、VR用テクスチャコピーのパスの双方がウィジェットの `Tick` をトリガーしてしまうケースがあります。
本実装では、`CaptureStackBackTrace` で呼び出し元のリターンアドレスを取得し、**「正規のテクスチャ更新ルートからの呼び出しのみを通し、余分なビューポート呼び出しのみを破棄する」** という、OSレベルのデバッグ技術を応用した完璧なフィルタリングを実現しています。

---

### 3.4 シェーダーでの赤緑パレット分離とレイトレーシング逆写像

HUDレンダラー（`hud_route_preview.hlsl`）における **「赤・緑パレットの連立方程式解決」** は、画像処理・リバースエンジニアリングとして極めて秀逸です。
警告色（赤）と通常色（緑）が重なったピクセルは、RGB値が単純に加算されて中間色になります。単純なしきい値判定（Thresholding）を行うと「暗い半透明パネル」と誤認されてブルーム（発光）が削ぎ落とされてしまいます。
これを連立方程式として解くことで、ピクセル本来のエミッション強度を復元し、VR内でも眩しいHUD発光を完全に再現しています。

さらに、`scene_mapping.hlsli` において、円筒シリンダーHUDとHMD両眼の視錐台の交差を **レイ・円筒交差判定（$a t^2 + b t + c = 0$）** で数学的に解き、ピクセル単位の逆写像テーブルを生成している点は、商用VRタイトルと同等以上の幾何学処理レベルに達しています。

---

## 4. 今後の推奨改善点とロードマップ

1. **JSON エラーの沈静化**:
   - `data/ac8_cinematic_intent_control.json` などの初期ファイルを同梱し、`log.txt` をクリーンにする。
2. **機体別カメラオフセットの拡充**:
   - 現状は F/A-18C と F-4E のみが実測調整済み（`data/AC8_VR-PerPlaneCameraOffsets.lua`）。F-15C, Su-37, F-22A などの人気機体のカメラ位置を計測・追加していく。
3. **VR ランタイムの安定性向上**:
   - Virtual Desktop 利用者向けに、VDXR ランタイムの推奨設定をドキュメント（`COMPATIBILITY_ja.md` 等）に追記する。
