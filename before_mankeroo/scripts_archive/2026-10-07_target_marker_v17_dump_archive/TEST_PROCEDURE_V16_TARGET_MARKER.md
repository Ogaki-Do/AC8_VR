# ACE COMBAT 8 : ターゲットマーカー検証手順書 (v16)
**作成日時**: 2026-10-07  
**検証スクリプト**: `ac8_target_3d_test.lua` (v16)  
**並行稼働（本採用）**: `ac8_m_jhmcs.lua` (AC8 HUD tuneの直後)  

---

## 0. 前回の検証結果と重要確定事項

### ① 四角枠の正体が100%特定されました！
ユーザー様のご検証により：
- **Case B1-1（Hide ContainerBox）→ 「四角が消えた！」**
- **Case B1-5（Hide RootComponent）→ 「文字と四角が消えた」**
- **Case B1-7（Hide All Texts）→ 「文字が消えた（四角は残る）」**
- **Case B1-8（Hide Entire Actor）→ 「文字と四角が消えた」**

この結果により、空中ターゲットの四角枠アイコンは間違いなく **`ContainerBox`（クラス名: `UMaterialBillboardComponent`）** であることが完全に証明されました！

---

## 1. ユーザー様のご質問への回答
> **「テキストみたいに実行タイミングもいじってみる必要があるのかな？」**

### 結論：実行タイミングの問題ではありません！
実は、前回の v15 の時点で、**「テキストと同じ3つの実行タイミング（通常Tick、VRカメラ計算後、描画直前）」すべてで毎フレーム連続実行**させていました。
B1-1 で四角枠がゲーム側のリセットに負けずに「消えた」のは、まさにこの3重タイミングで上書きしていたからです。
つまり、**実行タイミングはすでに完全に命中しています。**

### では、なぜスライダー（B2）でサイズが変わらなかったのか？
理由は、**Unreal Engine の「ビルボード（Billboard）」という部品の特殊仕様**にあります：
1. **通常のスケール（`Scale3D`）をエンジンが無視する仕様**:
   テキスト（`TextRenderComponent`）は通常の3Dメッシュと同様に `RelativeScale3D` で拡大できますが、ビルボード（カメラを常に向く板ポリゴン）は、Unreal Engine のレンダラー（`FMaterialBillboardSceneProxy`）が **`RelativeScale3D` や `ActorScale` を完全に無視して描画する設計**になっています。
2. **ビルボードのサイズは「Elements（要素データ）」または「マテリアル」で決まる**:
   ビルボードのサイズは `BaseSizeX` / `BaseSizeY`、またはシェーダー側の UV 拡大率でしか変わりません。
3. **v15 の B2 が効かなかった理由**:
   - `AddElement` に渡すマテリアルが空（`nil`）だったため無効化されていた。
   - `ContainerBox` は通常のマテリアルスロットを持たないため、通常のスロット操作ではパラメータが届かなかった。

---

## 2. 今回（v16）のテスト内容

v16 では、`ContainerBox`（ビルボード）の仕様に特化し、**実在するマテリアルの取得・注入**や**シェーダーパラメータ**を直接狙い撃ちするテストを組みました。
今回も厳格に **「1テストケース = 1スライダー または 1チェックボックス」** で、組み合わせ不要・単体操作でテストできます。

---

## 3. 【テストB】四角枠サイズ変更テスト（Part B-2）

UEVRメニューで `AC8 Target Marker Scaler (v16)` を開き、**`[TEST B]`** タブを選択してください。

### テスト手順（1スライダーずつ動かす）
どれか1つのスライダーを大きく動かし、四角枠の大きさに変化が出るかを確認してください。
確認後、横の **`[Reset]`** ボタンを押して元に戻し、次のスライダーを試してください。

| ケース番号 | 操作項目 | 内容 | リセット操作 |
| :--- | :--- | :--- | :--- |
| **Case B2-1** | `AddElement BaseSize (64~1024)` | 実在するHUDマテリアルを注入し、ビルボードのBaseSizeを直書き換え（512や1024に動かす） | `[128 Reset]` |
| **Case B2-2** | `Billboard Material MID 'Scale'` | マテリアルインスタンスを生成し、シェーダーの Scale（拡大率）を変更（2.0や3.0に動かす） | `[1.0 Reset]` |
| **Case B2-3** | `Billboard Material MID 'Size'` | シェーダーの Size パラメータを変更（300や500に動かす） | `[128 Reset]` |
| **Case B2-4** | `Billboard Material MID 'UVScale'` | シェーダーの UVScale / Tiling（テクスチャ倍率）を変更 | `[1.0 Reset]` |
| **Case B2-5** | `Blueprint Variable 'TargetBoxSize'` | ブループリント内部の変数 `TargetBoxSize` / `BoxSize` を変更 | `[128 Reset]` |
| **Case B2-6** | `TargetContainerManager 'TargetScale'`| HUD親マネージャー（`LiveTargetContainerManager`）の全体スケールを変更 | `[1.0 Reset]` |
| **Case B2-7** | `ScreenSpace Mode Off` (チェックボックス)| スクリーン固定サイズからワールド空間サイズへの切り替えテスト | チェックを外す |

> ※ 画面下の **`[=== Reset All B2 Sliders to Default ===]`** を押すと全スライダーが一括で初期値に戻ります。

---

## 4. ご報告フォーマット

```text
【Part B-2（四角枠サイズ変更）】
- 変化があったケース: （例: Case B2-X で大きくなった / 全部変化なし）
- 変化の様子: （例: 枠が巨大化した / 枠が消えた / 二重に表示された、など）
```
