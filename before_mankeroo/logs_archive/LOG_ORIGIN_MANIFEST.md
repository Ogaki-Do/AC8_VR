# 『ACE COMBAT 8』UEVR ログ・成果物 対応マニフェスト（出所一覧）

作成日: 2026年10月4日  
保存場所: `D:\Ogaki\Desktop\Ace-uevr-test\logs_archive\`

どのログファイルがどのLuaスクリプトおよび検証作業によって出力されたかの完全な対応表です。

---

## 1. 人工水平儀・UI復元関連 (`custom_horizon_and_uifix/`)

| ファイル名 | 出力元スクリプト | 役割・記録内容 |
| :--- | :--- | :--- |
| `ac8_ui_fix.txt` | `ac8_ui_fix.lua` | 2D HUD・メニュー復元ログ。Viewportへのルートウィジェット（`WBP_HUD_Chronicle_MainFlight_000_C`等）の再アタッチ結果を記録。 |
| `ac8_horizon_config.txt` | `ac8_horizon_hud.lua` | 自作人工水平儀の設定値永続化ファイル（バー長さ・太さ・中央空間gap・オフセット・ピッチ感度）。 |
| `hud_horizon_texture_log.txt` | `ac8_horizon_hud.lua` | 水平儀駆動ログ。`LandingGuideHorizontal`/`Vertical`の捕捉、シーンリセット、公式テクスチャ適用の成否履歴。 |
| `pitch_textures.txt` | `ac8_horizon_hud.lua` | ゲーム内メモリの全2,620個のTexture2Dから、pitch/horizon/ladder/guide関連テクスチャを抽出した一覧。 |

---

## 2. HUDウィジェット階層ダンプ (`hud_dumps/`)

| ファイル名 | 出力元スクリプト | 役割・記録内容 |
| :--- | :--- | :--- |
| `hud_dump_*.txt` (複数) | `dump_hud_info.lua` | ゲーム起動中の全1,138個のUMGウィジェットの完全ツリーダンプ。親キャンバス（`MainCanvas`）、`PitchMeterWidget`、`LandingGuide`等のVisibilityと型情報を網羅。 |

---

## 3. 技術検証・試行錯誤ログ (`technical_investigation_logs/`)

| ファイル名 | 出力元スクリプト | 役割・記録内容 |
| :--- | :--- | :--- |
| `landing_guide_log.txt` | `test_landing_guide_horizon.lua` | 初めて`LandingGuideHorizontal`の実体（Transient）を検出し、姿勢角（P/R）で駆動できることを実証したブレークスルーログ。 |
| `hud_horizon_speed_log.txt` | `ac8_hud_horizon_speed.lua` | 機体Pawnからの対気速度取得と、HUDへの数値表示を試みたテストログ。 |
| `speed_search.txt` | 速度探索スクリプト | PawnおよびFlightController内の速度プロパティ（`CurrentSpeed`, `SpeedKmh`等）を探索した出力結果。 |
| `ftext_test.txt` | `test_ftext.lua` | UEVR LuaからUEの`TextBlock:SetText`を呼ぶとSEH（Access Violation）が発生する原因調査ログ。 |
| `debug_line_log.txt` | `test_draw_debug_line.lua` | `UKismetSystemLibrary.DrawDebugLine`が製品版（Shipping）バイナリでスタブ化（削除）されていることを確認したログ。 |
| `m1_m2_test_log.txt` | `test_horizon_m1_m2.lua` | 機体姿勢（ピッチ/ロール）を`K2_GetActorRotation`と`RootComponent.RelativeRotation`で比較検証したログ。 |
