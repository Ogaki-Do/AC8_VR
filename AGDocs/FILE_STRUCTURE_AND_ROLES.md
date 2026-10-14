# ogaki-ac8vr ファイル構造と各ファイル群の役割 完全解説書

本ドキュメントでは、ACE COMBAT 8 向け UEVR プロファイルおよびコンパニオン・プラグインプロジェクト **`ogaki-ac8vr`** のディレクトリ構造、各ファイル群の責務、データ設定ファイル、バイナリアセット、および過去アーカイブ（`before_mankeroo`）との関係性について網羅的に解説します。

---

## 1. プロジェクト全体ツリー構造

```
Ace-uevr-test/
├── AGDocs/                         # [分析資料] リバースエンジニアリング・技術解説ドキュメント
├── backup-to-nas.ps1               # [運用] NASへのワークスペース一括バックアップスクリプト
├── sync-to-game.ps1                # [運用] %APPDATA% (実機UEVRプロファイル) への同期スクリプト
│
├── before_mankeroo/                # [過去アーカイブ] 初期の試行錯誤・テストスクリプト・調査ログ
│   ├── ac8_target_3d_test_v*.lua   # 3Dターゲットマーカー検証用テストスクリプト群
│   ├── TARGET_MARKER_*.md          # ポストモーテム・検証総括技術録
│   ├── TARGET_LOCATOR_*.md         # ロケーター矢印復帰ガイド
│   ├── scripts_archive/            # 旧世代の完成版・計画アーカイブ
│   └── logs_archive/               # 詳細ダンプ・検証ログ一覧
│
└── ogaki-ac8vr/                    # [本番リポジトリ] AC8 VR v0.1.0 配布・ソースコード一式
    ├── config.txt                  # UEVR Core 設定ファイル (VR描画・カメラ・UI初期設定)
    ├── cvars_data.txt              # ゲームエンジン CVar 適用設定
    ├── features.txt / _ja.txt      # 実装機能一覧 (英/日)
    ├── INSTALLATION.md / _ja.md    # インストール・更新・アンインストール手順書 (英/日)
    ├── README.md / _ja.md          # プロジェクト概要・主要機能・既知の制限 (英/日)
    ├── CHANGELOG.md / _ja.md       # バージョン履歴 (英/日)
    ├── CONTRIBUTING.md / _ja.md    # 開発・コントリビューション規約 (英/日)
    ├── THIRD_PARTY_NOTICES.md/_ja  # サードパーティライセンス・著作権表記 (英/日)
    ├── PROFILE-FILES.txt           # 配布物ファイル構成リスト
    ├── VERSION                     # 公式バージョン番号 (0.1.0)
    │
    ├── data/                       # [設定データ] JSON / Lua による詳細な挙動制御
    │   ├── AC8_VR-PerPlaneCameraOffsets.lua  # 機体別絶対カメラオフセット定義テーブル
    │   ├── ac8_bomb_landing_controls.json    # 爆撃・投下照準投影パラメータ
    │   ├── ac8_escort_draw_scale_enabled.flag# ネイティブビルボードスケール有効フラグ
    │   ├── ac8_hangar_coverage_controls.json # 格納庫・シネマティックカバレッジ制御
    │   ├── ac8_offscreen_group_controls.json # 画面外ロケーター全体オフセット
    │   ├── ac8_pause_controls.json           # ポーズ画面重複ティックガード設定
    │   ├── ac8_target_arrow_shift_controls.json # ロケーター矢印シフト・スケール
    │   ├── ac8_tutorial_fill_controls.json   # チュートリアル背景・枠制御
    │   ├── ac8_wingman_status_controls.json  # 僚機ステータス・レーダー追従間隔
    │   ├── ac8_workshop_target_controls.json # ワールドターゲット枠・ラベルフォント
    │   ├── ac8_workshop_v2_controls.json     # 個別ウィジェット配置・スケール調整
    │   └── ac8_world_target_controls.json    # フラットラベルオフセット・シアン彩度
    │
    ├── docs/                       # [仕様書] 互換性および設定仕様書
    │   ├── COMPATIBILITY.md / _ja.md         # 動作検証済みUEVRビルド・ハードウェア互換性
    │   └── CONFIGURATION.md / _ja.md         # 設定項目・ファイル責務一覧
    │
    ├── plugins/                    # [実行時プラグイン] UEVRが読み込むネイティブDLLとアセット
    │   ├── AC8_VR-Runtime.dll                # 6つのネイティブモジュールを統合した単一DLL
    │   └── ac8-hud-assets/                   # ランタイムHUDレンダリングアセット (44ファイル)
    │
    ├── scripts/                    # [実行時Lua] UEVRが実行する9つの協調動作型スクリプト
    │   ├── AC8_VR-Core.lua                   # ライフサイクル管理・生存確認・順序ディスパッチ
    │   ├── AC8_VR-CinematicPresentation.lua  # カットシーン・格納庫制御・2D退避・F7キー
    │   ├── AC8_VR-HUDLayout.lua              # UI初期化・僚機追従・キャンペーンターゲット
    │   ├── AC8_VR-InheritedHUD.lua           # 計器・人工水平儀・Slateウィジェット調整
    │   ├── AC8_VR-LoadingTransitions.lua     # サブシステム監視ロード画面判定・フェード同期
    │   ├── AC8_VR-PlaneCamera.lua            # 機体検出・一人称カメラオフセット適用
    │   ├── AC8_VR-StartupMovies.lua          # 起動ロゴ・告知画面短縮・シークスキップ
    │   ├── AC8_VR-UIRendering.lua            # 発光ライフサイクル・HUDポリシー・ポーズ操作
    │   └── AC8_VR-WorldTargets.lua           # ターゲット枠スケール・出現アニメーション保護
    │
    └── source_code/                # [ビルドソース] C++ / HLSL ソースコードとビルドスクリプト
        ├── build.ps1                         # MSVC / fxc を自動検出してコンパイルするスクリプト
        ├── modules.json                      # C++ モジュールビルドマニフェスト (6モジュール)
        ├── runtime-assets.txt                # 配布に必須の44アセット一覧リスト
        ├── MAINTAINERS.md / _ja.md           # メンテナー・開発者向け詳細アーキテクチャガイド
        ├── README.md / _ja.md                # ソースコード概要ガイド
        │
        ├── vendor/uevr/                      # praydog UEVR C API ヘッダーファイル群
        │   ├── plugin-api.h                  # UEVR プラグイン API 定義
        │   └── backend-api.h                 # UEVR バックエンド API 定義
        │
        └── src/                              # C++ / HLSL ソースコード
            ├── plugin.cpp                    # UEVR エントリーポイント (6モジュール初期化)
            ├── backend/                      # バイナリガード・OpenXR ABI 宣言
            ├── cinematic/                    # シネマティックカメラ・マスク・ポーズフック
            ├── hud/                          # ビルボード操作・二重ティックガード・シーカー縮小
            └── renderer/                     # D3D12監視・OpenXR合成・カスタムHLSL
```

---

## 2. 各ディレクトリと主要ファイル群の役割

### 2.1 トップレベル設定ファイル群

- **`config.txt`**:
  UEVR Core の設定ファイルです。以下の重要な設定を保持します：
  - `Frontend_RequestedRuntime=openxr_loader.dll`: OpenXR を使用。
  - `UI_Cylinder_Angle=113.625`: HUD を円弧角 113.625 度の円筒曲面 UI としてレンダリング。
  - `UI_Distance=1.0`, `UI_Size=1.0`: HUD の距離 1m、スケール 1.0。
  - `VR_CameraForwardOffset=-18.0`, `VR_CameraUpOffset=5.0`: デフォルトカメラ位置。
  - `VR_NativeStereoFix=true`: ネイティブステレオ修正を有効化。
  - `VR_AFW_UltraResponsive=true`, `VR_AFW_FramewarpMode=3`: 高応答フレームワープ。
- **`cvars_data.txt`**:
  UE のコンソール変数（CVar）を指定し、ゲームエンジン側の不要なエフェクトやカリングを抑制。
- **`VERSION`**:
  プロジェクトの公式バージョン文字列（`0.1.0`）を保持。すべてのドキュメント・ZIP名と厳密に同期されます。

---

### 2.2 `data/` フォルダ（設定データ）

ユーザーまたは開発者が挙動を微調整するための設定ファイル群です。

| ファイル名 | フォーマット | 役割と詳細 |
|---|:---:|---|
| `AC8_VR-PerPlaneCameraOffsets.lua` | Lua | **機体別のカメラ位置オフセットテーブル**。`BP_PlayerPlane_..._C` ごとに `forward`, `right`, `up`（-100〜100）を絶対値で指定。F/A-18C（-18, 0, 5）や F-4E（-10, 0, 5）が設定済み。 |
| `ac8_workshop_v2_controls.json` | JSON | Slate ウィジェットパスごとの位置（X, Y）、スケール（X, Y）、不透明度（Opacity）、表示フラグ。 |
| `ac8_workshop_target_controls.json` | JSON | ワールドターゲット枠の `boxScale`, `labelScale`, `fontScale`, `lineSpacing` の調整。 |
| `ac8_world_target_controls.json` | JSON | フラットスタイルラベルのオフセット、左ラベルのドロップ位置、シアン色マテリアルの彩度。 |
| `ac8_offscreen_group_controls.json` | JSON | 画面外ロケーター矢印グループ全体のオフセットとスケール。 |
| `ac8_target_arrow_shift_controls.json` | JSON | ネイティブロケーター矢印の頂点シフト量（`offsetX`, `offsetY`）と共通スケール。 |
| `ac8_wingman_status_controls.json` | JSON | 僚機ステータス表示の基準位置、レーダーモード追従時の間隔。 |
| `ac8_bomb_landing_controls.json` | JSON | 爆撃・投下照準予測の投影 FOV 補正パラメータ。 |
| `ac8_hangar_coverage_controls.json` | JSON | 格納庫およびカットシーンにおける水平・垂直カバレッジ範囲。 |
| `ac8_pause_controls.json` | JSON | ポーズメニューの重複入力・重複ティック防止ガード範囲。 |
| `ac8_tutorial_fill_controls.json` | JSON | チュートリアル枠・背景のスケール、透明度（Alpha）、インセット。 |
| `ac8_escort_draw_scale_enabled.flag` | Text | ネイティブビルボードのスケール機能を有効化するスイッチフラグ。 |

---

### 2.3 `scripts/` フォルダ（実行時 Lua スクリプト群）

UEVR の Lua エンジンによって読み込まれる 9 つのコンパニオンスクリプトです。
すべて `AC8_VR-` プレフィックスを持ち、ファイル名に依存しない明示的な順序で協調動作します。

- **`AC8_VR-Core.lua`**:
  すべてのスクリプトの土台。グローバルレジストリ `AC8VRModules` を通じて 17 セクションの準備を待機し、依存関係順（Presentation → Layout → Utility → Intro）で確実に起動。`UObjectHook.exists` によるオブジェクト生存確認（Dangling Pointer防止）と、同一ティック内ウィジェット探索キャッシュを提供。
- **`AC8_VR-HUDLayout.lua`**:
  起動時に 1 回だけ UEVR の曲面シリンダー HUD 設定をトランザクション適用。僚機ステータスとレーダーモード切り替えへの追従（3 ティック間隔）、キャンペーンターゲット行の配置。
- **`AC8_VR-InheritedHUD.lua`**:
  人工水平儀、対気速度計、高度計、速度ベクトルの位置補正と姿勢角同期。旧世代の知見を集約し、Slate ウィジェットのリフレクション更新を実行。
- **`AC8_VR-WorldTargets.lua`**:
  ターゲット出現時の「大→小」アニメーションを破壊しないようポストティックでターゲット枠をスケール。C++ へのパケット送信とマテリアル彩度制御。
- **`AC8_VR-PlaneCamera.lua`**:
  現在搭乗している機体のアセット名を識別し、`AC8_VR-PerPlaneCameraOffsets.lua` のオフセットを自動適用。手動微調整値の保持とシネマティック優先制御。
- **`AC8_VR-CinematicPresentation.lua`**:
  レンダリングストール監視（`cutscene_guard`）による 2D スクリーンモード自動退避、F7 キー手動オーバーライド、シネマティックカメラ・マスク制御と復帰ジャーナル。
- **`AC8_VR-LoadingTransitions.lua`**:
  `LiveLoadingScreenSubsystem` を階層追跡し、真のミッションロード画面を正確に判定。暗転フェードとの同期。
- **`AC8_VR-UIRendering.lua`**:
  フライト/メニュー/ポーズ状態を C++ へ通知（`AC8_HUD_GlowLifecycle`）。全ウィジェットの矩形ジオメトリポリシー（`AC8_HUD_PolicyV50`）を送信。ポーズメニューの 1 入力 1 ステップ化。
- **`AC8_VR-StartupMovies.lua`**:
  起動ロゴムービー（AcesLogo 等）や注意画面の待ち時間を短縮・シークスキップ。起動後 90 秒で自己終了。

---

### 2.4 `plugins/` フォルダ（ネイティブバイナリ＆アセット）

- **`AC8_VR-Runtime.dll`**:
  C++17、MSVC `/O2 /MT` でコンパイルされた 64-bit ネイティブ DLL。UEVR のプラグイン API をエクスポートし、D3D12/OpenXR フック、インラインフック、二重ティックガード、リフレクション操作を実行。
- **`ac8-hud-assets/`**:
  HUD レンダリングチェーンに必要な 44 個のアセットファイル群：
  - `hud-*.dxbc` (6ファイル): MOD 独自のカスタム HLSL からコンパイルされたシェーダーバイトコード。
  - `pso-*.dxbc` (16ファイル): ゲーム本体のレンダリングパイプラインから抽出・特定されたシェーダーバイトコード。
  - `event-*.bin` (21ファイル): 定数バッファ（Constant Buffer）データ。
  - `menu-deco-BC7.bin` (1ファイル): 装飾用 BC7 テクスチャデータ。

---

### 2.5 `source_code/` フォルダ（ビルド環境＆ソースコード）

- **`build.ps1`**:
  MSVC（`cl.exe`）および Windows SDK（`fxc.exe`）を自動検出し、C++ モジュール群と HLSL シェーダーをビルドして `build/AC8_VR-Runtime.dll` を生成するスクリプト。
- **`modules.json`**:
  ビルド対象の 6 つの C++ モジュール（`cinematic`, `escort`, `glow`, `warning`, `arrow`, `lock`）のソースパス定義。
- **`runtime-assets.txt`**:
  配布時に `plugins/ac8-hud-assets` へコピーすべき 44 アセットのホワイトリスト。
- **`src/` 配下**:
  - `plugin.cpp`: 単一 DLL のエントリーポイント。
  - `backend/`: `backend_boundary.h`（PE/SHA256ハッシュ/命令シグネチャ検証）、`xr_subset.h`。
  - `cinematic/`: `cinematic-game-hooks.cpp`, `mask.h`, `camera_lock.h`, `pause-navigation.h`, `bomb_render.h` 等。
  - `hud/`: `world-targets.cpp`, `escort-billboard-scale.h`, `hud-tick-guards.cpp`, `offscreen-indicators.cpp`, `target-lock-reticle.cpp`, `seeker-auto.h` 等。
  - `renderer/`: `hud-renderer.cpp`, `openxr_handoff.h`, `hud_route_preview.hlsl`, `hud_policy_pass.hlsl`, `scene_mapping.hlsli` 等。

---

## 3. `before_mankeroo`（過去アーカイブ）との関係性

`before_mankeroo` フォルダは、`ogaki-ac8vr` に至るまでの **開発の歴史・試行錯誤・実験スクリプト・調査ログの宝庫** です。

1. **歴史的系譜**:
   - **フェーズ 1 (2026-10-04 前後)**:
     人工水平儀（ピッチラダー）の消失原因調査と復元。`LandingGuide` の発掘とテクスチャ注入による成功（`scripts_archive/2026-10-04_ac8_uevr_hud_release_v1`）。
   - **フェーズ 2 (2026-10-07 前後)**:
     3D ターゲットマーカー（四角枠）のサイズ変更の試行（v13 〜 v22）。
     トランスフォーム（`Scale3D`）や動的マテリアルの変更が効かず、自前 UI 描画がクラッシュを引き起こしたため、「自前UI作成は永久撤退、公式パーツ操作を継続追求」とするポストモーテムが残される。
   - **フェーズ 3 (2026-10-09 前後)**:
     ターゲットロケーター（画面外矢印）の特定とテスト（v1 〜 v9）。
     `MissileRangeIndicator` や `LandingGuideVertical` を用いた極座標投影のテスト手順（`TARGET_LOCATOR_POSTMORTEM_AND_V8_GUIDE.md`）。
   - **フェーズ 4 (2026-10-13 〜 14: `ogaki-ac8vr` の誕生)**:
     すべての知見が統合され、C++ ネイティブプラグイン（メモリリフレクションによる `SetElements` 呼び出し、インラインフック、二重ティックガード、D3D12/OpenXR シェーダー合成）と、洗練された 9 つの Lua スクリプトによる完成版アーキテクチャへと昇華。
