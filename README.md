# Ace Combat 8 VR (`ogaki-ac8vr`)

[English](#english) | [日本語](#japanese)

---

<a name="japanese"></a>
# 【日本語】Ace Combat 8 VR 総合ガイド

本ドキュメントは、ACE COMBAT 8 を完全な VR コックピット視点でプレイするための UEVR 専用プロファイル＆ネイティブプラグイン **`ogaki-ac8vr`** の総合取扱説明書です。

---

## 1. 動作環境・対応バージョン

- **ゲーム本体**: ACE COMBAT 8（Steam版 最新 Ver.1.01.002 完全対応）
- **UEVR**: Nightly 1100 以降（OpenXR 推奨 / OpenVR 対応）
- **レンダリング設定**: DirectX 12 / Native Stereo
- **前提条件**:
  - UEVR 本体がインストールされていること
  - EAC（Easy Anti-Cheat）バイパスが適用されていること（Flat2VR Discord等を参照）

---

## 2. 実装済み主要機能

1. **コックピット HUD 最適配置＆全解像度対応**:
   - ピッチラダー（人工水平儀・姿勢計）およびウィスキーマークを毎フレーム直接描画。
   - FPM（速度ベクトル / フライトパスマーカー）の親速度動的相殺とクローズドループ実測合流。
   - 機首方向ガイド（ボアサイト軸）および画面外ターゲットロケーターの幾何中心センタリング。
   - 4K、ウルトラワイド（21:9 / 32:9）、縦型画面でもHUDが崩れない動的 SafeFrame スケーリング。
2. **3D ワールドターゲット＆ビルボード制御**:
   - C++ ネイティブプラグインによるターゲット枠の適正リサイズ（巨大化防止）。
   - 敵味方・護衛対象マーカー、名称・距離ラベル（RTTI 型判定でクラッシュ防止）。
   - ミサイルシーカー枠の 0.25 スケール化および爆撃投下予測レティクル追従。
3. **HUD Glow（発光ブルーム）両眼立体再構築**:
   - 44 個のカスタムシェーダーによる美麗な立体発光。
   - 不要な背景発光を遮断する厳格 `[0.0, 1.0]` UV クランプマスク。
   - 作戦指示字幕（`CutinSituation`）およびミッション失敗赤警告（`LayerOne`）の消失防止。
4. **HIT / DESTROYED / SHOOT 表示復元**:
   - VR 内で完全に透明化していた加算 RetainerBox を無力化し、命中・撃破・射撃好機メッセージを完全復旧。
5. **UI・メニュー・シーン演出保護**:
   - ポーズメニューのカーソル 2 段飛び防止および背景透過マテリアル化。
   - シネマティック演出、格納庫（ハンガー）、ブリーフィングでのカメラ保護。

---

## 3. インストール・導入・アンインストール手順

> [!CAUTION]
> **【重要】オンライン接続とアンチチート（EAC）に関する免責事項**
> 本MODおよびUEVRは、ゲームプロセスへの外部DLLインジェクションを伴うため、**Easy Anti-Cheat（EAC）の無効化が必須**となります。
> EACを無効化した状態でのオンラインマルチプレイへの接続は、**アカウントBAN（停止処分）のリスク**があります。
> 本MODの利用は**完全自己責任**とし、必ず**オフライン環境またはシングルプレイヤー（キャンペーン）モード専用**としてお楽しみください。

### 3.1 事前準備
1. **作業用フォルダの作成**:
   - 日本語などのマルチバイト文字が含まれるパスによる不具合を避けるため、ドライブ直下などに半角英数字のみの作業用フォルダ（例: `C:\AC8-UEVR`）を作成します。
2. **ゲームの初回起動と事前グラフィック設定**:
   - Steamからゲームを通常起動し、初回シェーダーコンパイルを完了させます。
   - オプションのグラフィック設定で以下を調整します（VR酔い防止・負荷軽減のため強く推奨）：
     - **垂直同期（V-Sync）**: `オフ`（入力遅延防止）
     - **モーションブラー**: `オフ`（3D酔い防止のため最重要）
     - **ブルーム**: `低` または `中`（視界確保・HUD視認性向上）
   - 設定後、一度ゲームを終了します。
3. **Easy Anti-Cheat (EAC) の無効化手順（steam_appid.txt 方式）**:
   本作は通常起動時に EAC が起動するため、外部ツール（UEVR）のプロセスインジェクションがブロックされます。以下の手順で EAC をバイパスし、ゲーム本体を直接起動できるように設定します：
   - **Step 1**: Steam ライブラリで『ACE COMBAT 8』を右クリック ＞「管理」＞「ローカルファイルを閲覧」を開きます。
   - **Step 2**: ゲームフォルダ内の `Game\Binaries\Win64` ディレクトリを開きます。
     - *※ `AceCombat8.exe`（または `Ace7Game.exe`）が存在する階層です。*
   - **Step 3**: このフォルダ内に新規テキストファイルを作成し、ファイル名を `steam_appid.txt` に変更します。
   - **Step 4**: `steam_appid.txt` をメモ帳で開き、半角数字で `2288340` と入力して保存します。
     - *※ ACE COMBAT 7 の場合は `502500` と入力します。*
   - **Step 5**: 同フォルダ内の `AceCombat8.exe` を直接ダブルクリックして起動し、EAC 画面を挟まずにオフラインゲームが直接立ち上がることを確認します。
   - **Step 6（推奨）**: `AceCombat8.exe` を右クリックして「ショートカットの作成」を行い、先ほど作成した作業用フォルダ（例: `C:\AC8-UEVR`）やデスクトップに配置しておきます。以降の VR プレイ時は必ずこのショートカットからゲームを起動します。

### 3.2 MODファイルの配置
1. 配布 ZIP アーカイブ（例: `AC8-VR-v0.1.0.zip`）をダウンロード・解凍します。
2. Windows のエクスプローラーで `%APPDATA%\UnrealVRMod\AceCombat8` を開きます（フォルダが存在しない場合は新規作成）。
3. ZIP 内のすべてのファイル・フォルダ（`scripts/`, `data/`, `plugins/`, `config.txt`, `cvars_data.txt`, `VERSION` 等）を、上記ディレクトリにそのまま配置します。

### 3.3 ゲーム起動と UEVR インジェクション手順
1. VR ヘッドセット（Meta Quest Link / Virtual Desktop / SteamVR / 各種 PCVR）を PC に接続し、VR ランタイム（OpenXR 推奨）を起動状態にします。
2. EAC 無効化状態で『ACE COMBAT 8』を起動します。
3. UEVR（Nightly 版）の `UEVRInjector.exe` を起動します。
4. プロセス一覧から本作のゲームプロセス（`AceCombat8` または `Ace7Game.exe` 等）を選択します。
5. 「**Inject**」ボタンを押下します。
6. VR ヘッドセット内で立体視およびコックピット視点へ切り替わり、本MODの HUD・ターゲット枠・Glow再構築が自動適用されます。

### 3.4 アップデート手順
1. ゲームおよび UEVR を終了します。
2. 最新の MOD アーカイブの内容を `%APPDATA%\UnrealVRMod\AceCombat8` に上書きコピーします。

### 3.5 アンインストール手順
1. `%APPDATA%\UnrealVRMod\AceCombat8` フォルダ内のファイル・フォルダをすべて削除します。

---

## 4. 操作方法とカスタマイズ（機能の使い方）

### 4.1 ゲーム内ショートカットキー
- **`Insert` キー**: UEVR メニューの開閉（HUD位置調整スライダーあり）。
- **`F7` キー**: シネマティックカメラの 2D 平面スクリーン / 3D VR 表示切り替え。
- **`F9` キー**: HUD Glow の手動強制再同期（万が一発光が消灯した場合の復旧用）。
- **`Space` キー**: 開発・診断用テレメトリ情報の JSON ダンプ出力。

### 4.2 HUD 位置のカスタマイズ
`data/CustomHUDPosition.json` をメモ帳などのテキストエディタで開くことで、各HUD要素の表示位置やスケールを自由に微調整できます：
- `pitchLadder`: ピッチラダーの垂直・水平オフセットおよび拡大率
- `radar`: レーダーの画面配置
- `aircraftInfo`: 速度・高度・残弾数表示の位置

---

## 5. よくある質問とトラブルシューティング

- **Q: ゲーム起動時にクラッシュする**
  - A: UEVR の設定が `OpenXR` かつ `DirectX 12` になっているか確認してください。また、Easy Anti-Cheat バイパスが正常に機能しているか確認してください。
- **Q: HUD が画面の端に寄ってしまう**
  - A: 本MODは起動後約 5 フレームでキャンバスサイズを自動計測して中央へ吸着します。ミッション開始直後に一瞬動くのは正常な確定動作です。
- **Q: 発光（Glow）が全画面で眩しくなる**
  - A: `F9` キーを押して Glow パイプラインを再同期させてください。

---

<a name="english"></a>
# 【English】Ace Combat 8 VR Comprehensive Guide

This document is the comprehensive manual for **`ogaki-ac8vr`**, an advanced UEVR profile and companion native plugin designed to deliver a complete cockpit VR flight experience for ACE COMBAT 8.

---

## 1. System Requirements & Compatibility

- **Target Game**: ACE COMBAT 8 (Steam Latest Ver.1.01.002)
- **UEVR**: Nightly 1100 or newer (OpenXR recommended / OpenVR compatible)
- **Rendering API**: DirectX 12 / Native Stereo
- **Prerequisites**:
  - UEVR installed and configured.
  - EAC (Easy Anti-Cheat) bypass applied (refer to Flat2VR Discord).

---

## 2. Key Features

1. **Precision Cockpit HUD Placement**:
   - Real-time overwrite of the Pitch Ladder and Whisky Mark every frame, preventing the native engine's -1920 reset.
   - Dynamic Flight Path Marker (FPM / Velocity Vector) counter-shift and closed-loop center alignment.
   - Dynamic safe-frame margin calculations supporting FHD, 4K, Ultrawide (21:9 / 32:9), and portrait aspect ratios without layout distortion.
2. **3D World Target Billboards**:
   - C++ native reflection hack (`SetElements`) to resize and stabilize target billboard containers.
   - Safe RTTI type checking (`is_a`) for target names, distance labels, and escort markers.
   - Scaled missile seeker reticle (0.25x) and terrain-following bomb landing reticle.
3. **Stereo HUD Glow & Shader Pipeline**:
   - Stereo HUD emission reconstructed via 44 DXBC shaders and C++ DLL.
   - Strict `[0.0, 1.0]` UV clamping mask preventing full-screen bloom bleeding.
   - Preserved critical mission text (`CutinSituation`) and mission-failed warning glow (`LayerOne`).
4. **Restored Combat Indicators (HIT / DESTROYED / SHOOT)**:
   - Neutralized additive RetainerBoxes (`EffectMaterial = nil`) to fully restore previously invisible combat alerts in VR.
5. **Presentation & Menu Protections**:
   - Elimination of pause-menu double-skip input glitches and opaque black overlay removal.
   - Cinematic, hangar, and briefing camera protection.

---

## 3. Installation & Setup Guide

> [!CAUTION]
> **Important Disclaimer on Anti-Cheat (EAC) & Online Connectivity**
> Because this mod and UEVR require process memory injection, **disabling Easy Anti-Cheat (EAC) is mandatory**.
> Connecting to official online multiplayer with EAC disabled poses a **high risk of account suspension / ban**.
> Use this mod **entirely at your own risk**, strictly in **offline single-player / campaign mode**.

### 3.1 Prerequisites
1. **Working Directory Setup**:
   - Create a clean working folder with ASCII-only characters (e.g. `C:\AC8-UEVR`) to avoid path encoding glitches with multi-byte characters.
2. **First-Time Launch & Graphic Settings**:
   - Launch the game once normally via Steam to finish the initial shader compilation.
   - Adjust the following in the in-game Graphics Settings (strongly recommended for VR comfort):
     - **V-Sync**: `Off` (reduces input latency)
     - **Motion Blur**: `Off` (critical for motion sickness prevention)
     - **Bloom**: `Low` or `Medium` (optimizes cockpit and HUD clarity)
   - Exit the game.
3. **Disable Easy Anti-Cheat (EAC) via steam_appid.txt**:
   Standard launches trigger EAC, which blocks UEVR's process DLL injection. Follow these exact steps to bypass EAC and launch the game directly:
   - **Step 1**: Right-click *ACE COMBAT 8* in your Steam Library > **Manage** > **Browse local files**.
   - **Step 2**: Open the `Game\Binaries\Win64` directory (where `AceCombat8.exe` / `Ace7Game.exe` is located).
   - **Step 3**: Create a new text file named `steam_appid.txt` inside this folder.
   - **Step 4**: Open `steam_appid.txt` with Notepad, type `2288340` (or `502500` for AC7), and save.
   - **Step 5**: Double-click `AceCombat8.exe` directly to verify that the offline game launches without the EAC splash screen.
   - **Step 6 (Recommended)**: Right-click `AceCombat8.exe` and select **Create shortcut**, then place it in your working directory (e.g. `C:\AC8-UEVR`) or desktop. Always launch the game via this shortcut for VR sessions.

### 3.2 Mod File Deployment
1. Download and extract the release ZIP archive (e.g., `AC8-VR-v0.1.0.zip`).
2. Open `%APPDATA%\UnrealVRMod\AceCombat8` in Windows Explorer (create the folder if it does not exist).
3. Copy all files and directories (`scripts/`, `data/`, `plugins/`, `config.txt`, `cvars_data.txt`, `VERSION`, etc.) into this location.

### 3.3 Game Launch & UEVR Injection Sequence
1. Connect and start your VR headset (Meta Quest Link / Virtual Desktop / SteamVR / PCVR runtime, OpenXR recommended).
2. Launch ACE COMBAT 8 in EAC-disabled mode.
3. Launch `UEVRInjector.exe` from your UEVR Nightly directory.
4. Select the game process (`AceCombat8` or `Ace7Game.exe`) from the process drop-down.
5. Click **Inject**.
6. Put on your VR headset; stereoscopic 3D cockpit flight, dynamically centered HUD, and stereo Glow effects will initialize automatically.

### 3.4 Updating
1. Close both the game and UEVR.
2. Overwrite `%APPDATA%\UnrealVRMod\AceCombat8` with the new release files.

### 3.5 Uninstallation
1. Delete all contents inside `%APPDATA%\UnrealVRMod\AceCombat8`.

---

## 4. Controls & Customization

- **`Insert`**: Toggle UEVR overlay menu.
- **`F7`**: Toggle cinematic camera between 2D virtual theater and 3D mode.
- **`F9`**: Force re-synchronization of the HUD Glow pipeline.
- **`Space`**: Export real-time geometry telemetry JSON (`ac8_debug_telemetry.json`).
- **Customization**: Edit `data/CustomHUDPosition.json` with any text editor to adjust widget scales and offsets.
