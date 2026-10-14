# ogaki-ac8vr スクリプト全般の関数・実行タイミング・作用 完全解説書

本ドキュメントでは、`ogaki-ac8vr` を構成する全 Lua スクリプト（9 つの配布スクリプト＋1 つの機体設定スクリプト）について、**「どのような関数が存在するか」**、**「どのタイミング（コールバック・ライフサイクル）で実行されるか」**、**「ゲームエンジンや VR 空間にどのように作用するか」** を徹底的に解説します。

---

## 1. ライフサイクルとコールバックの全体像

UEVR とゲームエンジン（Unreal Engine）の間で、スクリプトは以下のタイミング（フェーズ）で駆動されます：

```
[ Engine Tick Start ]
   │
   ├─► on_pre_engine_tick (最重要・高頻度)
   │     ├─ AC8_VR-Core: コンテキスト更新 (PlayerController, HUD, Flight状態, Epoch)
   │     ├─ AC8_VR-CinematicPresentation: F7キー判定, レンダリングストール監視, 2Dスクリーンモード制御
   │     ├─ AC8_VR-LoadingTransitions: GameInstance/LoadingSubsystem 探索・ロード画面判定
   │     ├─ AC8_VR-WorldTargets: ネイティブパケット送信 (AC8_WorldTargetLayout)
   │     └─ AC8_VR-UIRendering: グローライフサイクル判定 (AC8_HUD_GlowLifecycle)
   │
   ├─► [ Game Logic / Actor Updates / Physics ]
   │
   ├─► on_post_engine_tick (事後処理・サイズ適用)
   │     ├─ AC8_VR-HUDLayout: HUD初期設定適用 (起動時1回トランザクション), 僚機ステータス追従
   │     ├─ AC8_VR-PlaneCamera: 搭乗機体の検出と絶対カメラオフセット適用 (60tick周期)
   │     ├─ AC8_VR-WorldTargets: ターゲット枠サイズ変更 (ContainerBoxImageSize) とアニメーション保護
   │     ├─ AC8_VR-StartupMovies: 告知画面・ロゴムービーの待機時間短縮・シークスキップ (90秒限定)
   │     └─ AC8_VR-InheritedHUD: 人工水平儀・計器・レティクルのトランスフォーム更新
   │
   ├─► on_pre_viewport_client_draw (描画直前)
   │     └─ AC8_VR-UIRendering: ウィジェットのペイント空間ジオメトリ計算とポリシーパケット送信
   │
   └─► on_custom_event / on_message (イベント・入力)
         ├─ AC8_VR-CinematicPresentation: F7ホットキーイベント受信 (AC8_CinematicIntent_F7)
         └─ 各種 C++ ネイティブプラグインとの双方向通信
```

---

## 2. 各スクリプトの詳細解説

---

### 2.1 `AC8_VR-Core.lua`

**役割**: 全スクリプトの中核基盤。ライフサイクル管理、オブジェクト生存確認、キャッシュ、順序ディスパッチ。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `rawget(_G, 'AC8VRModules')` | スクリプト読込時 | グローバルなモジュールレジストリを作成・取得。 |
| `R.isLiveObject(o)` | 各関数内（随時） | `UObjectHook.exists` を呼び出し、UObject がメモリ上に生存しているか検証。解放済みポインタ（Dangling Pointer）参照によるクラッシュを根絶。 |
| `R.objectCall(o, k, ...)` | 各関数内（随時） | `isLiveObject` で生存確認を行った上で安全にメソッドを呼び出すラッパー。 |
| `R.ownedWidgets(root)` | UI探索時 | 指定ルートウィジェット配下のツリー（`WidgetTree` / `RootWidget`）を走査。**同一エンジンティックかつ同一HUDエポック（世代）内では走査結果をキャッシュ**し、毎フレームの無駄な再探索を防止。 |
| `R.contextTick(advance)` | `on_pre_engine_tick`, `on_post_engine_tick` | `PlayerController`、`GetHUD`、`HudWidget` を取得。HUD 名が `LiveMainHUDParent4K_C` かどうかでフライト中（`R.context.flight`）を判定。HUD オブジェクトが変わると `epoch` を加算してキャッシュを全破棄。 |
| `R.connect(key)` | セクション登録時 | UEVR のエンジンコールバック（`on_pre_engine_tick` 等）を購読し、登録されたセクションを明示的な順序（`presentation` $\to$ `layout` $\to$ `utility` $\to$ `intro`）で呼び出す。 |
| `R.host(domain, name)` | 各モジュール初期化時 | 各モジュールにスコープ付きの仮想ホスト環境（安全なコールバック登録機構）を提供。 |
| `R.read(name)` / `R.json` | 設定読込時 | JSON ファイルを 30 ティック間キャッシュして読み出す。書き込みは許可された復元ジャーナルファイルのみに限定。 |
| `registry.start()` | 全セクション登録完了時 | 17 個の全セクションが揃った瞬間に、依存関係順に一括初期化を実行。 |

---

### 2.2 `AC8_VR-HUDLayout.lua`

**役割**: VR HUD の初期配置、円筒曲面 UI 設定、僚機（Wingman）ステータス追従、キャンペーンターゲット行。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `applyPresentationDefaults()` | 起動直後および `on_post_engine_tick` | `HUD_PRESENTATION`（depth: 1.0, scale: 1.0, curvature: 113.625, enabled: true）を UEVR 設定（`UI_Distance`, `UI_Size`, `UI_Cylinder_Angle`, `UI_OverlayType`）に**1度だけトランザクション適用**。書き込み失敗時はロールバック。ユーザーが後から UEVR メニューで手動調整した値を上書きし続けない。 |
| `AC8_CampaignTargetRow` | `on_post_engine_tick` | キャンペーンモードにおけるターゲット行ウィジェットの位置と表示を最適化。 |
| 僚機ステータス制御ループ | 3 エンジンティック周期 | レーダー表示モード（広域／近接／OFF等）の切り替えを検知し、僚機（Wingman）ステータス表示がレーダー外周に重ならず正しく追従するように Slate オフセットを更新。 |
| 爆撃照準アタッチ | フライト中随時 | 爆撃・投下照準（Bomb Landing Indicator）の座標を HUD キャンバスにアタッチ。 |

---

### 2.3 `AC8_VR-InheritedHUD.lua`

**役割**: 人工水平儀（ピッチラダー）、速度計、高度計、速度ベクトルの位置補正と姿勢角同期。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `AC8Runtime.inheritedSetup` | `HUDLayout` 完了後に遅延実行 | `HUDLayout` によるプレゼンテーション初期化が完了するまで実行を待機し、競合を防止。 |
| `find_flight_canvases()` | HUD エポック変更時 | `WBP_HUD_Chronicle_MainFlight_000_C` 配下の `MainCanvas`, `DynamicDrawCanvas`, `WorldToScreenDrawCanvas` などの主要キャンバスを探索。 |
| 水平儀・姿勢計更新ループ | `on_post_engine_tick` | 自機 Pawn のピッチ・ロール姿勢角を取得し、発掘した公式ウィジェット `LandingGuide`（`LandingGuideHorizontal`/`Vertical`）に対して `SetRenderTranslation` および `SetRenderTransformAngle` を呼び出して姿勢角を完全同期描画。 |
| 計器・レティクル補正 | `on_post_engine_tick` | 対気速度計、高度計、タコメーター、ガンレティクルを VR コックピット視界に合わせてキャリブレーション補正（`data/ac8_ladder.json` に設定を永続化）。 |

---

### 2.4 `AC8_VR-PlaneCamera.lua`

**役割**: 搭乗機体の検出と機体別カメラオフセットの適用。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `readConfig()` | 60 エンジンティック周期 | `data/AC8_VR-PerPlaneCameraOffsets.lua` を `load(text, ..., 't', {})` による空のサンドボックス環境で安全にパース。構文エラー時は前回正常値を維持。 |
| `firstPersonCamera(target)` | 機体変更時 | 現在のビューターゲット（自機 Pawn）から `LiveFirstPersonCameraComponent` を厳格に特定。第三者カメラや他アクターのカメラと誤認しないよう所有権を検証。 |
| `apply(value)` | 機体／構成／所有権変更時 | UEVR の `VR_CameraForwardOffset`, `VR_CameraRightOffset`, `VR_CameraUpOffset` に対し、Read-before-write トランザクションで安全に書き込み。書き込み後に値を読み返して検証し、不一致時は即座に元の値へロールバック。 |
| `presentationOwns(ci)` | 毎フレーム | シネマティック（カットシーン）や格納庫がカメラ演出を所有している間は、機体カメラのオフセット適用を一時休止（演出カメラを最優先）。 |

---

### 2.5 `AC8_VR-WorldTargets.lua`

**役割**: 3D ワールドターゲット（敵味方四角枠）のサイズ制御、出現アニメーション保護、マテリアル彩度。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `target_labels: update()` | `on_pre_engine_tick` | `ac8_workshop_target_controls.json` と `ac8_world_target_controls.json` を読み込み、C++ プラグインへカスタムイベント `AC8_WorldTargetLayout`（パケット文字列 `address|enabled|boxScale|labelScale|...`）を送信。 |
| `target_animation: restore()` | HUD エポック変更時 / リセット時 | アクターに適用したサイズ変更を退避していたオリジナルの値へ復元。 |
| `target_animation: post_tick` | `on_post_engine_tick` | ターゲット出現時の「大→小」に縮小する公式アニメーションを破壊しないよう、アクターの初期サイズを取得した上で、倍率を乗算して `ContainerBoxImageSize` および `SelectTargetAddContainerBoxSize` を更新。 |
| `target_pins` | 15 ビューポート描画周期 | ターゲットピン（`ClockTargetPinBillboardImage` 等）を検知し、C++ 側へ `AC8_WorldPipScale` を送信してネイティブ側でビルボードの `SetElements` を実行させる。 |
| `target_materials` | フライト中随時 | 現在のワールドに存在する動的マテリアルインスタンス（MID）からシアン色のカラーパラメータを特定し、彩度（Saturation）を調整（全画面の青ピクセルを一括置換するような乱暴な処理は行わない）。 |

---

### 2.6 `AC8_VR-CinematicPresentation.lua`

**役割**: カットシーン・格納庫の自動検出、レンダリング停止時の 2D 退避、F7 キー手動切替、復帰ジャーナル。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `enter_2d(reason)` | レンダリングストール検知時 | ゲームのレンダリングハートビートが停止（2.5秒以上ストール）した際、クラッシュやフリーズを防ぐため一時的に UEVR の `VR_2DScreenMode = true` に切り替えて退避（格納庫内は除外）。現在の設定を保存。 |
| `exit_2d(reason)` | レンダリング復帰時 | 描画が正常再開（3.0秒以上安定）した際、退避前の 3D VR 設定へ自動復帰。 |
| `applyMask()` / `clearMask()` | シネマティック開始／終了時 | シネマスコープや上下黒帯（レターボックス）マスクを適用／解除。C++ 側の `cinema_mask` と連携。 |
| `on_custom_event` | F7 キー押下時 | C++ の Win32 メッセージフックから送られる `AC8_CinematicIntent_F7` を受信し、エンジンメインスレッド上で安全に 2D/3D シネマティック表示をトグル切り替え。 |
| `saveUI()` / `restoreUI()` | シネマティック出入り時 | シネマティック突入前のカメラ位置・UI設定を `ac8_cinematic_ui_restore.json` に保存し、終了時に完全復元。 |

---

### 2.7 `AC8_VR-LoadingTransitions.lua`

**役割**: ミッションロード画面の正確な判定と、画面暗転フェードの同期。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `mission_loading: update()` | `on_pre_engine_tick`, `on_post_engine_tick` | 単なるタイマーではなく、`GameInstance` $\to$ `LiveLoadingScreenSubsystem` $\to$ `WBP_Loading_Root_000_C` $\to$ `WBP_MissionLoad_ManagerWidget_000_C` という UE のウィジェット階層の可視性・所属を追跡して、**真のミッションロード中であるかを判定**。 |
| `clear(reason)` | ロード終了時 | ロード画面オブジェクトが非表示または破棄された際、ロード状態を解除。 |
| `transitions: update()` | `on_pre_engine_tick` | ロード時やシーン切替時の黒画面フェード（Fade Opacity）を監視し、C++ の `native_fade` と連携して VR 空間でマップのチラ見えを防止。 |

---

### 2.8 `AC8_VR-UIRendering.lua`

**役割**: HUD 発光（Glow）ライフサイクル管理、ウィジェット矩形ポリシーパケット生成、ポーズ操作正常化。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `glow_lifecycle: update()` | `on_pre_engine_tick`, `on_post_engine_tick` | プレイヤーコントローラーとゲーム状態を監視し、フライト突入（`flight` / `mission_entry`）、フライト離脱（`outside_flight`）、ポーズ出入り（`pause_enter` / `pause_exit`）を検知して C++ へ `AC8_HUD_GlowLifecycle` イベントをディスパッチ。 |
| `hud_policy: update()` | `on_pre_viewport_client_draw` | 描画直前の各ウィジェットのペイント空間ジオメトリ（`GetPaintSpaceGeometry` / `GetCachedGeometry`）を計算し、どの領域にどの強度でグローをかけるかを定義したポリシーパケット（`AC8_HUD_PolicyV50`）を C++ へ送信。 |
| `pause_attachment` | ポーズ画面表示時 | ポーズメニューの Slate ウィジェットを VR の HMD 正面の見やすい位置にアタッチし、コントローラー／キーボードの 1 入力で 1 項目ずつ進むよう制御（二重入力スキップを防止）。 |

---

### 2.9 `AC8_VR-StartupMovies.lua`

**役割**: 起動時ロゴムービー・告知画面の待ち時間短縮、シークスキップ。

| 関数名 | 実行タイミング | 作用と詳細 |
|---|---|---|
| `scan()` | 起動後 90 秒間（0.05秒間隔） | `DA_LiveMenuNoticeScreenSetting` および `LiveMenuNoticeScreenContentWidget` を走査し、`FadeInTime`, `FadedInWaitTime` などの待機時間を最小値（0.05秒）に短縮。 |
| `scanMovies()` | 起動後 90 秒間 | `LiveManaMovieViewer` から再生中の Sofdec ムービー（`MS_Title_AcesLogo` 等）を特定し、再生開始から 0.5 秒後に `ManaPlayer:Seek(duration)` を呼んで即座に末尾へシークスキップ。 |
| `restoreOne(n)` | 起動から 90 秒経過時 | 変更していたプロパティをすべて元の値へ復元し、以降のミッション中ムービーやチュートリアルに干渉しないよう自己終了。 |

---

### 2.10 `data/AC8_VR-PerPlaneCameraOffsets.lua`

**役割**: 機体別絶対カメラオフセットのデータ定義テーブル。

```lua
return {
    mode = 'uevr_absolute',
    enabled = true,
    default = { forward = -18, right = 0, up = 5 },
    planes = {
        ['BP_PlayerPlane_F18C_C'] = { forward = -18, right = 0, up = 5 },
        ['BP_PlayerPlane_F4E_C']  = { forward = -10, right = 0, up = 5 },
        -- 他の機体は必要に応じてコメント解除して調整
    }
}
```
- `AC8_VR-PlaneCamera.lua` によって読み込まれ、ゲームプレイ中に外部編集しても 60 ティック周期で動的に再読み込みされます。
