# ACE COMBAT 8 : ターゲットロケーター復帰・技術総括＆v8テスト手順書

- **対象タイトル**: 『ACE COMBAT 8』(UEVR + OpenXR)
- **作成日**: 2026年10月9日
- **テストスクリプト**: `ac8_target_locator_test.lua` (v8: 26,079 bytes)
- **原本保護**: `ac8_ladder_fix_v19_fast.lua` (73,244 bytes 完全無改造・保護)

---

## 1. 反省の訂正（真実の教訓）

過去のドキュメントにあった「自前UIを作ろうとすると描画スレッド競合やクラッシュが起きるから断念」という記述を、ユーザー様のご指摘に基づき以下のように訂正します。

> **【真の技術的制約】**  
> **「そもそもUEVR/Lua環境には、自前でテキストUIやSlateウィジェットを新規作成・独自描画する機能・環境自体が存在しない」**

- UEVRのLua APIには、ゲーム実行時に新しいSlate/UMGウィジェット（`CreateWidget`等）をイチから生成する機能はありません。
- また、DirectXのHUDオーバーレイ描画（ImGui等）はHMDのVRディスプレイ（Viewport）内に常時固定表示されません。
- **結論**:  
  **「ゲーム内に元々存在しているネイティブHUDアセットを発掘し、それをViewport上で目覚めさせて流用・制御する」ことだけが、VR内に確実かつ美麗にUIを表示させる唯一無二の方法である。**

---

## 2. ピッチ・ヨー（人工水平儀）の解法分析と今回への適用

### ① ピッチ・ヨーはどうやって解決されたのか？
1. **消失の原因**:
   - ゲーム本体は `LiveWidgetToTextureSystem`（テクスチャベイク中間層）を使い、姿勢計ウィジェットをレンダーターゲットテクスチャに毎フレーム書き込んでコックピットガラス（マテリアル `MID_MI_IndicatorGlass`）に投影していた。
   - UEVRがステレオ（両眼）描画フックを行う際、このテクスチャベイク中間層が描画パスから脱落して停止したため、HUDガラスから水平線が消失した。
2. **解決の決定打（`ac8_horizon_hud.lua` / `ac8_ladder_fix_v19_fast.lua`）**:
   - VRのViewport画面に確実に直接描画されている `WBP_HUD_Chronicle_MainFlight_000_C`（`MainFlight`）のツリー深層を捜索。
   - 画面中央の `MainCanvas` 直下に、非表示（Hidden/Collapsed）になって眠っていた公式パーツ **`LandingGuide`**（親CanvasPanel）および **`LandingGuideHorizontal` / `LandingGuideVertical`**（`UImage`）を発掘！
   - 親パネル `LandingGuide` を `SetVisibility(0)`（Visible）および `SetRenderOpacity(1.0)` で目覚めさせた。
   - `UImage::SetBrushFromTexture` により、公式の0度水平バーテクスチャ（`T_HUD_PitchMeter_MarkCenter_001`）を直接流し込んだ。
   - 自機のピッチ・ロール姿勢角に合わせて `SetRenderTranslation` と `SetRenderTransformAngle` で毎フレームトランスフォームを更新。
   - **結果**: 自前UIを1ドットも作ることなく、完全な公式品質の人工水平儀がVR正面に復活した！

### ② ターゲットロケーター（矢印）への適用
ターゲットロケーター（画面外の敵を指す矢印）も、ピッチラダーと全く同一の成功法則を適用します：

1. **土台となる公式ウィジェットの選定**:
   - `MainFlight` 配下でViewportに直結している以下の公式ウィジェットを流用：
     - **Mode 0: `MissileRangeIndicator`**（親: `MissileRangePanel` $\to$ `Altimeter`）。元からピッチラダー右側の高度計テープ内に常駐している公式矢印！
     - **Mode 1: `LandingGuideVertical`**（親: `LandingGuide` $\to$ `MainCanvas`）。水平儀で実績100%の公式ガイド針！
     - **Mode 2: `LandingGuideHorizontal`**（親: `LandingGuide` $\to$ `MainCanvas`）。水平儀で実績100%の公式バー！
     - **Mode 3: `Locator_Wingman`**（`WBP_HUD_Locator_Wingman_000_C`）。公式エスコートロケーター！
2. **公式矢印テクスチャの直接流し込み（`SetBrushFromTexture`）**:
   - `T_HUD_UIArrow_001`（公式HUD三角矢印）
   - `T_HUD_Multi_TargetPin_002`（公式3Dターゲットピン矢印）
   - `T_HUD_LocatorEscort_000`（公式ロケーター矢印）
   - `T_HUD_UIArrow_Line_002`（公式細線矢印）
3. **親パネルの覚醒**:
   - `LandingGuide` や `MissileRangePanel` を `SetVisibility(0)` + `SetRenderOpacity(1.0)` で確実に強制可視化。
4. **極座標リング配置と敵機方向への自動回転**:
   - 自機とロックオン敵機の3D相対ベクトルから、時計方位角（Heading Angle）を算出。
   - ピッチラダー中央（HUD中心）から半径 $R$（px）の円周上へ極座標配置（`SetRenderTranslation`）。
   - 矢印自身の向きを敵機方向へリアルタイム回転追従（`SetRenderTransformAngle`）。
   - 画面外時のみ自動点灯（正面時は自動消灯）。

---

## 3. これまでの実装の整理（何が指示通りで、何が違っていたか）

| 項目 | 前回の実装（v7等） | 指示通りだった点 | 指示通りでなかった点 | 今回（v8）の修正 |
| :--- | :--- | :--- | :--- | :--- |
| **アプローチ** | 3Dアクター（`ChronicleTargetContainerActorBP_C`）のコンポーネントを自機正面へ引っ張ろうとした | 「3D要素」というキーワードへの着目 | 3Dアクターのルートが数km彼方にあるためフラスタム/距離カリングで消去され、BillboardのElementsも空で表示不能だった | ピッチラダー実績の「Viewport直結2D公式ウィジェット覚醒＋公式矢印テクスチャ注入」へ完全回帰 |
| **モード選択** | なし（単一処理） | なし | 「モードがないんだが？」というご指摘通り、比較検証できるモードが欠落していた | **4つのモード（Mode 0〜3）** を完全実装（ラジオボタン切替） |
| **スライダー** | 3D座標のcmスライダーのみ | スライダーUIの実装 | HUDピクセル基準の半径や角度調整スライダーがなかった | **ピクセル基準の半径（Radius）、Scale X/Y、Opacity、Offset X/Y、FOV角度、回転微調整スライダー** を全完備 |
| **テスト表示** | ロックオン＋画面外時のみ | 自動判定ロジック | 画面外に出さないと確認できず、そもそも出ているのかテストしづらかった | **`[Force Test Display (Always On)]`** チェックボックスを新設。敵の位置に関係なく即座に常時表示させて位置・サイズ・テクスチャを確認可能に |

---

## 4. v8 テストスクリプトの使い方

1. ゲーム内で出撃（または訓練飛行）を開始します。
2. キーボードの **`Insert`** キーを押し、UEVRメニューを開きます。
3. **`Script UI`** にある **`AC8 TARGET LOCATOR ARROW RESTORATION (v8)`** を開きます。
4. **`[Activate Target Locator]`** にチェックを入れます。
5. **最速確認手順（即座に矢印を画面に出す）**:
   - 隣にある **`[Force Test Display (Always On)]`** にチェックを入れます。
   - これにより、敵機の画面外判定をバイパスし、**今すぐコックピット正面HUDに矢印が強制表示**されます！
6. **モードの切り替え（どの公式パーツを使うか）**:
   - `Mode 0: MissileRangeIndicator` (高度計横の公式矢印)
   - `Mode 1: LandingGuideVertical` (水平儀実績のMainCanvas針)
   - `Mode 2: LandingGuideHorizontal` (水平儀実績のMainCanvasバー)
   - `Mode 3: Locator_Wingman` (公式僚機ロケーター)
7. **テクスチャの選択**:
   - `T_HUD_UIArrow_001`（三角矢印）や `T_HUD_Multi_TargetPin_002`（ピン）をクリックして見た目を切り替え。
8. **スライダー調整**:
   - `Ring Radius`: ピッチラダー中央からの距離
   - `Arrow Length / Width`: 矢印の大きさ
   - `Quick Position Presets`: `Whisky Mark Center` や `Pitch Ladder Right` ボタンでワンクリック配置。
9. 見た目と位置が決まったら、**`[Force Test Display]`** のチェックを外せば、**「敵機が画面外に出た時だけ自動点灯・敵機の方向を指す」実戦モード**に切り替わります！
