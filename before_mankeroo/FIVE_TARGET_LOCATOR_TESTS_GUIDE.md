# 『ACE COMBAT 8』ターゲットロケーター特定・5大テストスクリプト手順書

- **目的**: 
  「新規HUD作成は棄却、すでにあるものを持ってくる」方針のもと、ダンプ解析で浮上した最有力候補5要素を個別に検証する。
- **絶対ルール**: 
  **全スクリプトはデフォルトでは何もしません（完全休止・負荷ゼロ）。**
  UEVRメニュー（`Insert` キー）の **`Script UI`** からチェックボックスをONにしたものだけが動作します。

---

## 1. 配備ファイル一覧

| テスト番号 | ファイル名 | 検証対象 | 期待される挙動 |
| :---: | :--- | :--- | :--- |
| **TEST 1** | `ac8_test1_gunreticle_opacity.lua` | ガンレティクル不透明度 | スライダーでガンレティクルの濃さ（透過度）が変化するか確認 |
| **TEST 2** | `ac8_test2_locator_wingman.lua` | `WBP_HUD_Locator_Wingman_000_C` | 僚機ロケーター（公式矢印画像）が画面上に出現するか確認 |
| **TEST 3** | `ac8_test3_locator_widget_scale.lua` | `WBP_LocatorWidget` | ピッチラダー中央（0,0）で敵ロケーターのサイズが拡大して見えるか確認 |
| **TEST 4** | `ac8_test4_missile_range_indicator.lua` | `MissileRangeIndicator` (矢印) | 公式矢印テクスチャ（T_HUD_UIArrow_001）をピッチラダー中央に表示 |
| **TEST 5** | `ac8_test5_live_main_hud_probe.lua` | `LiveMainHUDParent4K_C` | 3D空間のHUD親玉アクターの全コンポーネント・プロパティをリアルタイム調査 |

- **配備先**: `%APPDATA%\UnrealVRMod\AceCombat8\scripts\`

---

## 2. 各テストの操作手順と確認ポイント

### 【TEST 1: ガンレティクルの透過度操作】
1. UEVRメニュー $\to$ **`Script UI`** $\to$ **`AC8-Test1-GunReticle-Opacity`** を開きます。
2. **`[Activate Test 1]`** にチェックを入れます。
3. **`Opacity`** スライダーを 0.0 〜 1.0 に動かします。
   - **確認ポイント**: 画面中央のガンレティクル（円やバー）が薄くなったり消えたりするか？

---

### 【TEST 2: WBP_HUD_Locator_Wingman 表示テスト】
1. **`AC8-Test2-Locator-Wingman`** を開きます。
2. **`[Activate Test 2]`** にチェックを入れます。
3. **`[Inject to Screen (AddToViewport)]`** と **`[Force Visible]`** にチェックを入れます。
4. **`Scale`** を 3.0 〜 5.0 に拡大し、**`Blink (Flash)`** をONにします。
   - **確認ポイント**: 画面上にピカピカ点滅する僚機矢印（緑/青）が出現するか？

---

### 【TEST 3: WBP_LocatorWidget サイズ操作（初期位置＝ピッチラダー中央）】
1. **`AC8-Test3-LocatorWidget-Scaler`** を開きます。
2. **`[Activate Test 3]`** にチェックを入れます。
3. デフォルトでピッチラダーと同じ座標 `(X=0, Y=0)` に配置されています。
4. **`Scale`** スライダーを 2.0 〜 8.0 に引き伸ばします。
5. **`Expand Internal Canvas Scale`** にチェックを入れます。
   - **確認ポイント**: ピッチラダー中央付近に、サイズ0で潰れていた敵用ロケーターが拡大されて出現するか？

---

### 【TEST 4: MissileRangeIndicator 表示テスト（初期位置＝ピッチラダー中央）】
1. **`AC8-Test4-MissileRange-Indicator`** を開きます。
2. **`[Activate Test 4]`** にチェックを入れます。
3. デフォルトでピッチラダーと同じ座標 `(X=0, Y=0)` に配置されています。
4. **`Scale`** スライダーを 3.0 〜 8.0 にし、**`Blink`** をONにします。
   - **確認ポイント**: 公式の三角矢印（T_HUD_UIArrow_001）がピッチラダー中央に点滅出現するか？

---

### 【TEST 5: LiveMainHUDParent4K_C 詳細調査】
1. **`AC8-Test5-LiveMainHUD-Probe`** を開きます。
2. **`[Activate Test 5]`** にチェックを入れます。
3. パネル上に `LiveMainHUDParent4K` のコンポーネント一覧とプロパティが表示されます。
4. **`[>>> DUMP REPORT TO FILE NOW <<<]`** ボタンを押すと、`data/ac8_live_main_hud_dump.txt` に詳細レポートが出力されます。
