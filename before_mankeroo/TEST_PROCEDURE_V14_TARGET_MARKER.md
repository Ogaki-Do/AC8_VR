# ACE COMBAT 8 : ターゲットマーカー検証手順書 (v14)
**作成日時**: 2026-10-07  
**検証スクリプト**: `ac8_target_3d_test.lua` (v14)  
**並行稼働（本採用）**: `ac8_m_jhmcs.lua` (AC8 HUD tuneの直後)  

---

## 0. 今回の変更点まとめ
1. **JHMCS の本採用・配置順序**:
   - `ac8_m_jhmcs.lua` として配備し、UEVRメニュー内で **「AC8 HUD tune」の直後** に並ぶようファイル配置・命名を整理。
   - テスト用LUA（`ac8_target_3d_test.lua`）からは JHMCS 関連の重複コードを**完全削除**。
2. **【テストA】テキストサイズ変更（解決済み）**:
   - 一番軽快な **Phase 1（通常エンジンTick）** を本採用。
   - スライダーで文字サイズ（距離、機体名、TGTラベル）を自在に調整可能。
3. **【テストB】四角枠アイコンの特定＆サイズ変更（シンプル化）**:
   - ご指示通り、**「1ケースにつきチェックボックス1個 または スライダー1個」** に完全独立化。
   - 複数操作の組み合わせを廃止し、1つ動かすだけで即座に効果がわかる設計に一新。

---

## 1. 【テストA】ターゲットテキストのサイズ調整（実用テスト）

### 操作
1. UEVRメニュー（Scripting → `AC8 Target Marker Scaler (v14) : Test A & Test B`）を開きます。
2. 上部ボタンで **`[TEST A]`** を開きます。
3. **`ALL Texts Master Scale`** スライダーを動かします（`1.5x`, `2.0x`, `3.0x` などのプリセットボタンあり）。
4. **確認**: 正面・全周問わず、距離の数字や機体名などの文字サイズが軽快に拡大縮小することをご確認ください。

---

## 2. 【テストB】四角枠アイコンの特定＆サイズ変更テスト

上部ボタンで **`[TEST B]`** を開きます。
各テストケースは**「チェックボックス1個」または「スライダー1個」**で完結します。

### Part B-1: 部品特定テスト（どの部品が四角枠か？）
四角枠を非表示にして、**「どのコンポーネントが四角枠の本体なのか」**を1チェックで特定します。

| ケース番号 | チェックボックス操作 | 期待される判定 |
| :--- | :--- | :--- |
| **Case B1-1** | `[x] Case B1-1: Hide ContainerBox only` | 四角枠が消えたら、`ContainerBox` が四角枠本体！ |
| **Case B1-2** | `[x] Case B1-2: Hide ClockTargetPinBillboardImage only` | 四角枠が消えたら、ClockPin が四角枠本体！ |
| **Case B1-3** | `[x] Case B1-3: Hide AntiClockTargetPinBillboardImage only` | 四角枠が消えたら、AntiClockPin が四角枠本体！ |
| **Case B1-4** | `[x] Case B1-4: Hide EscortBillboardImage only` | 四角枠が消えたら、Escort が四角枠本体！ |
| **Case B1-5** | `[x] Case B1-5: Hide All Texts only` | 文字だけ消えて四角枠のみ残るか確認。 |
| **Case B1-6** | `[x] Case B1-6: Hide Entire Actor` | アクター丸ごと消えるか確認。 |

> ※ 終わったら **`[Uncheck All (Show Everything)]`** ボタンで一括復旧できます。

---

### Part B-2: サイズ変更テスト（1スライダー＝1テストケース）
気になるスライダーを1つだけ動かして、四角枠の大きさに変化が出るかを試します。

| ケース番号 | スライダー名 | 変更内容 | リセットボタン |
| :--- | :--- | :--- | :--- |
| **Case B2-1** | `AddElement BaseSize (64~1024)` | ビルボードサイズを直接注入（`512` や `1024` に動かす） | `[128 Reset]` |
| **Case B2-2** | `ContainerBox RelativeScale3D` | コンポーネントのローカル3Dスケール | `[1.0x Reset]` |
| **Case B2-3** | `ContainerBox WorldScale3D` | コンポーネントのワールド3Dスケール | `[1.0x Reset]` |
| **Case B2-4** | `Actor Scale3D` | ターゲットアクター全体の3Dスケール | `[1.0x Reset]` |
| **Case B2-5** | `RootComponent RelativeScale3D` | ルート配置コンポーネントのスケール | `[1.0x Reset]` |
| **Case B2-6** | `Material MID Parameter 'Scale'` | マテリアルシェーダーの Scale 値 | `[1.0 Reset]` |
| **Case B2-7** | `Material MID Parameter 'Size'` | マテリアルシェーダーの Size 値 | `[128 Reset]` |
| **Case B2-8** | `Material MID Parameter 'IconScale'` | マテリアルシェーダーの IconScale 値 | `[1.0 Reset]` |
| **Case B2-9** | `ContainerBox ScreenSize` | ビルボードのスクリーンサイズ値 | `[1.0 Reset]` |
| **Case B2-10**| `ContainerBox BoundsScale` | ビルボードの描画バウンド拡張（カリング対策） | `[1.0 Reset]` |

> ※ 1つのスライダーを動かして変化がなければ、その横の `[Reset]` を押して次のスライダーを試してください。

---

## 3. ご報告フォーマット

```text
【Part B-1（部品特定）】
- 四角枠が消えたケース: （例: Case B1-1 で消えた / 別のケースで消えた / どれでも消えなかった）

【Part B-2（サイズ変更）】
- 四角枠の大きさが変わったスライダー: （例: Case B2-X で大きくなった / 全部変化なし）
```
