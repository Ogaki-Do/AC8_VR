# 『ACE COMBAT 8』HUD「いとこ」探索＆深層ダンプツール（Hunter Dumper）解説書

- **スクリプト名**: `ac8_hud_cousin_hunter_dumper.lua`
- **配備先**: `%APPDATA%\UnrealVRMod\AceCombat8\scripts\ac8_hud_cousin_hunter_dumper.lua`
- **出力ファイル**: `data/ac8_hud_cousin_dump.txt`
- **目的**: 
  - 新規自作HUDではなく、**「ゲーム内にすでに眠っている公式の矢印／ロケーター／インジケーター」** を特定する。
  - 特に**ピッチラダーの「いとこ（同一親キャンバス・同一HUD系統に属する親戚パーツ）」** を階層ごと網羅探索し、ファイル出力 ＆ 画面上での即時強制可視化テストを可能にする。

---

## 1. スキャンされる 5大レイヤー

### ① ピッチラダーの「いとこ」（同一親キャンバス配下の全ウィジェット）
ピッチラダーやレティクルが存在する `MainFlight`（`MainCanvas` / `DynamicDrawCanvas` / `WorldToScreenDrawCanvas`）のツリー全体をくまなく走査します。
- `Pitch*`, `Ladder*`, `Horizon*`, `Landing*`
- `Gun*`, `Reticle*`, `Velocity*`, `Whisky*`
- `Locator*`, `Seeker*`, `TargetSelection*`, `WayPoint*`
- `Outer*`, `End0*`, `End4*`, `MAD*`, `Marker*`, `Tachometer*`, `Altimeter*` など
それぞれの **Visibility（表示・非表示フラグ）、RenderTransform（位置・スケール・回転角）、サイズ、親ウィジェット、ブラシ（使用テクスチャ名）** を詳細出力します。

### ② 矢印・ロケーター・ターゲット誘導系キーワードの全網羅
メモリ上の全 UWidget から、以下のキーワードに合致するものを全抽出：
- `locator`, `arrow`, `pointer`, `guide`, `pin`, `indicator`, `direction`, `lead`, `target`, `aim`, `reticle`, `seeker`, `waypoint`, `offscreen`, `chevron`, `triangle`, `compass`, `marker`

### ③ 3D HUDアクター＆コンポーネント（ワールド空間）
- 自機Pawnの全コンポーネント（77個すべてを詳細ダンプ）
- ワールド上の全3D HUDアクター（`LiveMainHUDParent4K_C`, `3DUI`, `AerialRefuel`, `TargetContainer` 等）
- ターゲットアクター（`ChronicleTargetContainerActorBP_C`）の内部ピン（`ClockTargetPinBillboardImage` 等）
- 3D座標（自機からの距離・X, Y, Z）と `bHiddenInGame`

### ④ 眠っている公式テクスチャ（Texture2D）完全カタログ
メモリ上に常駐しているテクスチャから、`HUD`, `Pitch`, `Target`, `Guide`, `Arrow`, `Pin`, `Indicator`, `Marker` を含むものを全列挙。ピッチラダーのときのように「眠っていた公式テクスチャ」を掘り起こします。

---

## 2. インゲームでの使い方（ワンクリックダンプ ＆ 画面上即時テスト）

1. 出撃（または訓練飛行）を開始し、敵機をロックオン（視界内または視界外）します。
2. キーボードの **`Insert`** キーを押し、UEVRメニューを開きます。
3. **`Script UI`** に表示される **`AC8-COUSIN-HUNTER`** パネルを開きます。

### STEP 1: ダンプの実行
- **`>>> RUN FULL DEEP DUMP NOW <<<`** ボタンを押します。
- 一瞬でメモリ全体のスキャンが完了し、`data/ac8_hud_cousin_dump.txt` に詳細ログが出力されます。

### STEP 2: 画面上での即時目視テスト（神機能）
「これかも？」と思う怪しいパーツを、ゲームを止めずにその場で画面上に出現させて確認できます！

1. **`Candidate Widget`** のドロップダウンから、気になるパーツ（`WBP_LocatorWidget`, `LandingGuideVertical`, `OuterTopLine` 等）を選択します。
2. **`Force Visible on Screen`** にチェックを入れます。
3. **`Blink (Flash) to Locate`** にチェックを入れると、パーツがピカピカと点滅するため、画面のどこにあるか一目で分かります！
4. **`Test Scale`**（サイズ拡大）や **`Move X / Y`**（位置移動）スライダーを動かして、ピッチラダーの周りやコックピット正面に引っ張り出せます。
