# AGDocs: ogaki-ac8vr 技術ドキュメント＆リバースエンジニアリング検証集

本フォルダ（`AGDocs/`）は、ACE COMBAT 8（AC8）向け UEVR / OpenXR プロファイルおよびコンパニオン・ネイティブプラグイン **`ogaki-ac8vr`** のソースコード・バイナリ・ログを徹底的にリバースエンジニアリングし、そのファイル構造、実装状態、実現手法、関数ライフサイクル、技術的ブレークスルー、ビルド＆リリース手順、および検証結果を体系的にまとめた技術資料集です。

---

## 📚 ドキュメント構成（全6巻）

### 0. [総合タスクリスト ＆ リファクタリング計画書 (TASK_LIST.md)](TASK_LIST.md)
- **インクリメンタル検証の原則**: 「1手ずつ変更 ➔ sync-to-game ➔ 壊れたら即ロールバック」。
- **アーキテクチャ・リファクタリング計画**: 11fps 激減の真因（毎フレーム4,000個ウィジェット走査・先祖32階層計算）のキャッシュ化。
- **優先順位別タスク詳細**: P0（負荷削減・統廃合）〜 P5（JHMCS棚上げ検討）。
- **HUDカスタム仕様**: `CustomHUDPosition.json`、-1.0〜+1.0比率スライダー。

---

### 1. [ファイル構造と各ファイル群の役割 完全解説書 (FILE_STRUCTURE_AND_ROLES.md)](FILE_STRUCTURE_AND_ROLES.md)
- **全体ディレクトリ構造**: `ogaki-ac8vr` の全ツリー構造と構成要素。
- **ファイル群の役割**: `data/`（10個のJSON、カメラ設定Lua、フラグ）、`plugins/`（DLLと44個のアセット）、`scripts/`（9つの協調Lua）、`source_code/`（C++とHLSL）。
- **設定ファイル群の責務**: `config.txt`, `cvars_data.txt`, `VERSION`, `features.txt`。
- **過去アーカイブとの関係性**: `before_mankeroo` の試行錯誤（人工水平儀復元、3Dターゲットマーカー検証、ロケーター矢印テスト）から完成版への発展の系譜。

---

### 2. [スクリプト全般の関数・実行タイミング・作用 完全解説書 (SCRIPT_FUNCTIONS_AND_LIFECYCLE.md)](SCRIPT_FUNCTIONS_AND_LIFECYCLE.md)
- **ライフサイクルとコールバック**: UEVR エンジンフェーズ（`on_pre_engine_tick`, `on_post_engine_tick`, `on_pre_viewport_client_draw`, `on_custom_event`）の完全マップ。
- **スクリプト全般の関数・作用リファレンス**:
  - `AC8_VR-Core.lua`: 生存確認（`isLiveObject`）、ウィジェット走査キャッシュ、順序ディスパッチ。
  - `AC8_VR-HUDLayout.lua`: 曲面シリンダーHUD初期化トランザクション、僚機ステータス追従、爆撃照準アタッチ。
  - `AC8_VR-InheritedHUD.lua`: 人工水平儀・計器・レティクルの姿勢角同期トランスフォーム。
  - `AC8_VR-PlaneCamera.lua`: `LiveFirstPersonCameraComponent` 検出と機体別絶対カメラオフセット適用。
  - `AC8_VR-WorldTargets.lua`: ターゲット出現アニメーション保護、ポストティックスケール調整、マテリアル彩度制御。
  - `AC8_VR-CinematicPresentation.lua`: レンダリング停止検知（`cutscene_guard`）、2D退避、F7キー手動切替、復帰ジャーナル。
  - `AC8_VR-LoadingTransitions.lua`: サブシステム監視による正確なロード画面判定、フェード同期。
  - `AC8_VR-UIRendering.lua`: グローライフサイクル判定、ペイント空間ジオメトリ計算、ポーズメニュー操作正常化。
  - `AC8_VR-StartupMovies.lua`: ロゴムービーの短縮・シークスキップと自動終了。
  - `data/AC8_VR-PerPlaneCameraOffsets.lua`: 機体別カメラオフセットデータ。

---

### 3. [リバースエンジニアリング詳細分析書 (REVERSE_ENGINEERING_ANALYSIS.md)](REVERSE_ENGINEERING_ANALYSIS.md)
- **開発の歴史的経緯**: 自前UI作成の挫折から、ネイティブ発掘＋外科手術的フックへの転換。
- **全体アーキテクチャ**: C++ ネイティブプラグイン、9つの協調Lua、カスタムHLSLのハイブリッド構造。
- **C++ ネイティブプラグイン詳解**:
  - `backend_boundary.h`: PEヘッダー・SHA256・命令シグネチャによるバイナリガード。
  - `escort-billboard-scale.h`: `SetElements` を呼んでビルボード枠のサイズ変更を可能にするメモリリフレクション操作。
  - `offscreen-indicators.cpp`: 画面外ロケーター矢印の頂点バッファ座標シフト・スケーリング（RVAインラインフック）。
  - `seeker-auto.h`: シーカーアートワークの縮小と自己検証。
  - `hud-tick-guards.cpp`: `CaptureStackBackTrace` を用いた二重ティック（Double Tick）抑制。
  - `hud-renderer.cpp`: D3D12 コマンドリスト監視と OpenXR レイヤ合成。
- **カスタム HLSL シェーダー詳解**:
  - `hud_route_preview.hlsl`: 赤・緑パレット混合の連立方程式解決によるHUD発光（Glow）の復元。
  - `scene_mapping.hlsli`: レイ・シリンダー交差判定（レイトレーシング）による円筒曲面UIと視錐台のピクセル単位逆写像。

---

### 4. [実装検証・ログ分析・技術考察書 (VERIFICATION_AND_INSIGHTS.md)](VERIFICATION_AND_INSIGHTS.md)
- **検証マトリクス**:
  - 全10個のデータ JSON の構文検証（全合格）
  - 44個のレンダリングアセットの完全性検証（全合格）
  - 配布DLLと実機 `%APPDATA%` DLLの SHA-256 バイナリ一致検証（完全一致）
  - 全9個の Lua スクリプトの内容一致検証（完全一致）
  - 実機ログでの6大ネイティブモジュール初期化確認（`initialized=1`）
- **トラブルシューティングとログ分析**:
  - **事象①**: `ac8_cinematic_intent_control.json` 等の JSON パースエラーログ多発の原因分析と対策。
  - **事象②**: 14:04 の `crash.dmp`（`VirtualDesktop.LibOVRRT64_1.dll` での `c0000005`）の分析と OpenXR (VDXR) 推奨設定。
- **技術的考察（Deep Insights）**:
  - なぜ「自前UI作成」ではなく「公式ネイティブ発掘＋C++フック」が正解だったのか。
  - エンジン仕様でスケールが無視される `UMaterialBillboardComponent` のサイズ変更を突破した意義。
  - OSレベルのコールスタック解析による二重ティック問題の根本解決。
  - 数学的アプローチによる曲面UIの逆写像と赤緑パレット分離の美しさ。

---

### 5. [ビルド・パッケージング・リリース手順書＆チェックリスト (BUILD_AND_RELEASE_PROCEDURE.md)](BUILD_AND_RELEASE_PROCEDURE.md)
- **ビルド環境の前提条件**: MSVC（`cl.exe`）、Windows SDK（`fxc.exe`）。
- **コンパイル手順**: `source_code/build.ps1`（通常ビルドおよび `-SkipShaders` 高速ビルド）。
- **実機環境への同期**: `sync-to-game.ps1` の仕様と手順。
- **配布用 ZIP アーカイブ作成手順**:
  - 配布物ホワイトリスト（44アセット、DLL、Lua、データ、ドキュメント）。
  - 除外ブラックリスト（`source_code/`、キャッシュ、個人パス等）。
- **バージョニング規則**: `VERSION` ファイルとドキュメントの一貫性維持。
- **リリース前 実機検証チェックリスト**: 起動・ポーズ・機体切替・戦闘・カットシーン・終了の確認項目。

---

## 🛠️ クイックリファレンス

- **プロジェクトルート**: `d:\Ogaki\Desktop\Ace-uevr-test\ogaki-ac8vr`
- **実機プロファイル先**: `%APPDATA%\UnrealVRMod\AceCombat8`
- **実機同期スクリプト**: `d:\Ogaki\Desktop\Ace-uevr-test\sync-to-game.ps1`
- **NASバックアップスクリプト**: `d:\Ogaki\Desktop\Ace-uevr-test\backup-to-nas.ps1`
