# 『ACE COMBAT 8』視界外ターゲット誘導矢印（Locator）調査報告 ＆ 実験用Lua (v1)

- **対象タイトル**: 『ACE COMBAT 8』
- **実行環境**: UEVR (Universal Unreal Engine VR Mod) + OpenXR
- **調査日**: 2026年10月9日
- **スクリプト名**: `ac8_locator_experiment_v1.lua`

---

## 1. 調査の総括と判明した事実

### ユーザー様の予想
> **「ロック対象が視界外に出たときに出てくるやじるし！個人的な予想ではピッチラダーと同じように３D描画されて遠くにある気がする」**

この仮説を検証するため、既存の全メモリダンプ（30万行超）、過去の研究ログ、およびゲーム仕様を徹底調査しました。

### ① 矢印の正式名称と2D UMGウィジェットの特定（大発見）
- 通常のフラット画面（2D）でロック対象が視界外に出た際に表示される矢印は、エンジン内部で **`Locator`（ターゲットロケーター）** と呼ばれています。
- メモリダンプ内に、まさにそのものずばり **`WBP_LocatorWidget`**（クラス名: `WBP_HUD_DynamicWidget_Parts_Locator_000_C`）が存在します！
  - **階層**: `WBP_HUD_Chronicle_MainFlight_000_C` $\to$ `DynamicDrawCanvas` 直下
  - **兄弟要素**: `WBP_SeekerWidget`（ミサイルシーカー円）、`WBP_TargetSelectionDraw`（ターゲット枠描画）、`WBP_HUD_Container_WayPoint_000`（ウェイポイント）

### ② なぜVRで見えなくなっていたのか？（3つの有力な原因）
1. **原因1: 既存スクリプトによる強制 (0, 0) 固定（ピン留め干渉）**
   - 現在稼働中の `ac8_hud_inspect_v129.lua` 内の `RESET_LIST` に `Locator` が登録されており、**20フレーム毎に `RenderTranslation = (0, 0)`（原点固定）が強制適用**されていました。
   - ゲーム本体がターゲットの方角（画面端の円周上）に合わせて矢印を動かそうとしても、(0, 0) にピン留めされていたため、画面外や変な場所に固定されていた可能性があります。
2. **原因2: ユーザー様予想の「ピッチラダーと同じテクスチャベイク脱落」説**
   - ピッチラダー（人工水平儀）と同様、`DynamicDrawCanvas` や `Locator` は元々 `LiveWidgetToTextureSystem` によってレンダーターゲットテクスチャにベイクされ、**コックピットのHUDガラス（`MID_MI_IndicatorGlass`）に3D投影**されていました。
   - UEVRのステレオレンダリング適用によって中間テクスチャベイク層が機能停止したため、コックピットHUDガラス上から消滅している可能性が非常に高いです。
3. **原因3: 3Dアクター側（敵機側のピン / ワールド空間）説**
   - ターゲットアクター（`ChronicleTargetContainerActorBP_C`）の内部には、`ClockTargetPinBillboardImage` や `AntiClockTargetPinBillboardImage`（時計回り/反時計回りターゲットピン）というコンポーネントが存在します。
   - これらが視界外時に矢印として表示される想定である場合、敵機が視界外を向いた瞬間に「正面100°カリング」によって消滅してしまっている可能性があります。

---

## 2. 配備した実験用スクリプト（`ac8_locator_experiment_v1.lua`）

上記すべての仮説をインゲームで切り分けてリアルタイム検証できる実験用スクリプトを作成・配備しました。

- **配備先**: `%APPDATA%\UnrealVRMod\AceCombat8\scripts\ac8_locator_experiment_v1.lua`
- **保存先**: `D:\Ogaki\Desktop\Ace-uevr-test\scripts\ac8_locator_experiment_v1.lua`

---

## 3. 実験手順（テストベッドの使い方）

1. ゲームを起動し、出撃（または訓練飛行）を開始します。
2. キーボードの **`Insert`** キーを押し、UEVRメニューを開きます。
3. **`Script UI`** に表示される **`AC8-Locator-Experiment-v1`** パネルを開きます。

### 画面上部のテレメトリ確認
- 現在ロックしている敵機名、距離（m）、自機正面からの相対角度（水平 Azimuth / 垂直 Elevation）が表示されます。
- 機首を敵機から大きく逸らすと、赤文字で **`>>> TARGET IS OFF-SCREEN <<<`** と表示され、視界外判定が機能していることを確認できます。

### 【実験 A: 2D UMG `WBP_LocatorWidget` の検証】
- **[Force Visible & Opacity 1.0]** をONにします。
- **[Widget Scale]** スライダーを 2.0 〜 3.0倍に引き伸ばします。
- **[Unlock & Test Manual Translation]** をONにし、手動オフセットスライダー（または [Center Screen], [Top Edge], [Right Edge] ボタン）を押して、画面上に矢印ウィジェットが現れるか確認します。
  - *もしこれで矢印が現れた場合*: ウィジェット自体は生きており、位置や非表示フラグの制御で復元可能と判明します！

### 【実験 B: 3Dオブジェクト探索（ユーザー様仮説の検証）】
- **[Scan 3D Candidates in World]** を押します。
- ワールド内、自機Pawn、コックピットHUD周りにある `Locator`, `Arrow`, `TargetGuide` などの3Dオブジェクトと、その3D座標をリストアップします。
- 遠くや別深度に配置されているオブジェクトを特定します。

### 【実験 C: ターゲットピン（Billboard Pin）の検証】
- **[Force Clock/AntiClock Pins Visible]** をONにします。
- **[Pin Billboard Scale]** を 5.0 〜 10.0 に拡大し、敵機の周囲にピン/矢印アイコンが出現するか確認します。

### 【実験 D: 視界外矢印の角度シミュレーション】
- 自機から見た敵機の方向角（時計の針でいう何時の方向か）をリアルタイム計算した結果（`ARROW HEADING`）が表示されます。
- ネイティブ表示が難しい場合のJHMCS風ダイナミック矢印復元の基礎データとなります。
