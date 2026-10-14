# 『ACE COMBAT 8』360° JHMCS プランA（JhmcsA）総括アーカイブ報告書
**アーカイブ作成日**: 2026-10-04  
**ステータス**: 実証実験完了 $\to$ 【不採用・ボツ確定】

---

## 1. プランA（JhmcsA）の仮説と目的

### 仮説
* フリールック（右スティック）操作時にゲーム内のカメラ（`PlayerCameraManager / PCM`）が回転することで、ネイティブターゲット枠（`WBP_TargetSelectionDraw`）が360°全方位に描画されることを確認した。
* **アイディア**: PCMを頭部視線（HMD）に合わせて旋回させつつ、UEVRのステレオレンダリングフック（`on_early_calculate_stereo_view_offset`）でカメラの回転差分（`diff_yaw`）を差し引けば、**「ゲーム本体は敵機を視野内に捉えてターゲット枠を描画し、VR内のコックピット視界は二重回転せずに静止する」**のではないか？

---

## 2. 実施された検証内容

1. **クラスリフレクション解析（公式API）**:
   * 対象: `LiveCockpitCameraInputComponent`, `LiveCockpitCameraComponent`, `LivePlayerCameraManager`
   * ログ: [`ac8_jhmcs_a_investigation.txt`](file:///C:/Users/Ogaki/AppData/Roaming/UnrealVRMod/AceCombat8/data/archive_plan_a_20261004/ac8_jhmcs_a_investigation.txt)
2. **ステレオ視界回転フック（`on_early_calculate_stereo_view_offset`）**:
   * `rotation.Yaw` への動的書き込みテスト（`sol::uevr::API::UObject` への書き込み成功確認）
3. **ゲーム内実機飛行テスト**:
   * 出撃状態での右スティックフリールックおよび視界相殺トグル検証

---

## 3. 判明した技術的知見（ログ記録より）

### A. カメラ入力コンポーネント（LiveCockpitCameraInputComponent）の物理限界
リフレクションダンプにより、ゲーム本体の入力処理に以下のハードコードされた限界角が判明：
* `HorizontalLimit = 115.000` (水平旋回角リミット: 115°)
* `VerticalLimitMax = 50.000` (上仰角リミット: 50°)
* `VerticalLimitMin = -25.000` (下俯角リミット: -25°)
* `RightStickSwingSpeed = 4.500`

### B. UEVRステレオレンダリングとの干渉（致命的欠陥）
* `on_early_calculate_stereo_view_offset` で `rotation.Yaw` を個別に補正すると、Unreal Engine の内部ステレオ変換行列における瞳孔間距離（IPD）の投影中心と回転中心が乖離。
* 結果として、**視界が横・前後に剪断スライドする激しい歪み**が生じ、立体視の崩壊を招く。
* `view_index == 0`（左目）のみ補正された場合、右目（未補正）との間で完全に異なる方角を向く激しい斜視・視線解離が発生。

### C. `VR_DecoupledPitch=true` の弊害
* 機体のピッチ・ロールとVRカメラの自然な傾き同期が途切れ、機動時にコックピット内で天地が狂う強烈なVR酔い・違和感を誘発。

---

## 4. 結論：プランA 不採用の理由

1. **立体視（Stereo）の物理的破綻**: 瞳孔間オフセットと視線回転が干渉し、剪断歪みを防ぐことができない。
2. **ゲーム内部リミット（115°）の存在**: 入力コンポーネント自体が 115° で頭打ちとなるため、真後ろ（180°）までの完全追従が困難。
3. **機体挙動との同期リスク**: カメラを回すこと自体が、機体ピッチ/ロール連動を不安定にする。

---

## 5. アーカイブファイル一覧

| ファイル名 | 格納場所 | 内容説明 |
| :--- | :--- | :--- |
| **`ac8_jhmcs_plan_a_evaluation.lua`** | `archive/2026-10-04_jhmcs_plan_a_archive/` | プランA検証用スクリプト本体 |
| **`ac8_jhmcs_a_investigation.txt`** | `archive/2026-10-04_jhmcs_plan_a_archive/` | リフレクション解析 & 評価テレメトリログ |
| **`ac8_camera_investigation.txt`** | `archive/2026-10-04_jhmcs_plan_a_archive/` | カメラ親子階層ツリー & 360°フリールック観測ログ |

---
**次期ステップ**: プランB（ウィジェット投影ハック方式：カメラ完全固定・360°円筒UIマッピング）の実装へ移行。
