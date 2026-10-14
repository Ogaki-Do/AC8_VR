# ogaki-ac8vr ビルド・パッケージング・リリース手順書＆チェックリスト

本ドキュメントでは、`ogaki-ac8vr` の C++ ネイティブプラグインおよびシェーダーのビルド手順、実機テスト環境への同期、配布用 ZIP パッケージの作成手順、およびリリース前チェックリストをまとめます。

---

## 1. ビルド環境の前提条件

`source_code/build.ps1` を実行して `AC8_VR-Runtime.dll` およびカスタム HLSL シェーダーをビルドするには、以下の開発環境が必要です：

1. **Visual Studio C++ Build Tools (MSVC)**:
   - x64 MSVC コンパイラ (`cl.exe`)
   - C++17 サポート (`/std:c++17`, `/EHsc`, `/O2`, `/MT`)
   - `vswhere.exe` がインストールパスを自動検出できる状態であること。
2. **Windows 10 / 11 SDK**:
   - UCRT、shared、um、winrt インクルードヘッダー群
   - `fxc.exe`（DirectX HLSL シェーダーコンパイラ）
3. **UEVR ヘッダー群**:
   - `source_code/vendor/uevr/` に同梱されているため、UEVR 本体のソースチェックアウトは不要です。

---

## 2. コンパイル手順（ビルドの実行）

PowerShell（管理者権限または実行ポリシーバイパス）を開き、`source_code` ディレクトリでビルドスクリプトを実行します。

### 2.1 通常ビルド（C++ および シェーダーの一括コンパイル）
```powershell
cd d:\Ogaki\Desktop\Ace-uevr-test\ogaki-ac8vr\source_code
powershell.exe -ExecutionPolicy Bypass -File .\build.ps1
```

- **処理内容**:
  1. `vswhere.exe` およびレジストリから MSVC と Windows SDK のパスを検出。
  2. `build/` ディレクトリを作成。
  3. `modules.json` に定義された 6 つのモジュール（`cinematic`, `escort`, `glow`, `warning`, `arrow`, `lock`）を個別にコンパイルし、オブジェクトファイル（`.obj`）を生成。
  4. `src/plugin.cpp` とリンクし、単一の DLL `build/AC8_VR-Runtime.dll` を生成。
  5. `fxc.exe` を使用して、6 つの HLSL エントリーポイント（VS/PS）をコンパイルし、`src/renderer/hud-route-assets/` 内の `hud-*.dxbc` を更新。
  6. 成功メッセージ `Built one DLL: build/AC8_VR-Runtime.dll` を出力。

### 2.2 高速ビルド（シェーダーのコンパイルをスキップ）
シェーダー（`.hlsl`）を変更しておらず、C++ ソースのみを修正した場合は `-SkipShaders` オプションを使用できます：
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\build.ps1 -SkipShaders
```

---

## 3. 実機テスト環境への同期手順

ビルドが完了したら、作業中の内容を実機の UEVR プロファイルディレクトリ（`%APPDATA%\UnrealVRMod\AceCombat8`）へ反映します。
プロジェクトルートにある自動同期スクリプト `sync-to-game.ps1` を使用します。

```powershell
cd d:\Ogaki\Desktop\Ace-uevr-test
powershell.exe -ExecutionPolicy Bypass -File .\sync-to-game.ps1
```

- **同期対象**:
  - `ogaki-ac8vr/scripts/` $\to$ `%APPDATA%\UnrealVRMod\AceCombat8\scripts\`
  - `ogaki-ac8vr/data/` $\to$ `%APPDATA%\UnrealVRMod\AceCombat8\data\`
  - `ogaki-ac8vr/plugins/` $\to$ `%APPDATA%\UnrealVRMod\AceCombat8\plugins\`
  - `config.txt`, `cvars_data.txt`, `VERSION`
- **注意点**:
  - ゲーム実行中は `AC8_VR-Runtime.dll` がプロセスによってロックされます。DLL を更新した場合は、必ずゲームを一度終了してから同期し、再起動してください。
  - Lua スクリプトのみの変更であれば、UEVR メニュー（`Insert` キー）からスクリプトの再読み込みを行うことで即座に反映可能です。

---

## 4. 配布パッケージ（ZIP）作成手順

プレイヤー向けに配布する ZIP アーカイブ（例: `AC8-VR-v0.1.0.zip`）を作成する手順です。

### 4.1 アセットの反映（ビルド成果物のコピー）
1. `source_code/build/AC8_VR-Runtime.dll` を `plugins/AC8_VR-Runtime.dll` へコピー。
2. `source_code/runtime-assets.txt` に記載されている **44 個のファイルのみ** を、`source_code/src/renderer/hud-route-assets/` から `plugins/ac8-hud-assets/` へコピー。

### 4.2 配布物に含めるファイル（ホワイトリスト）
配布用 ZIP のルートには、以下のフォルダおよびファイルのみを含めます：
```
[ZIP Root]
├── data/                       # 全設定データ (JSON, Flag, PerPlaneCameraOffsets.lua)
├── docs/                       # ユーザー向け仕様書 (COMPATIBILITY, CONFIGURATION)
├── plugins/                    # AC8_VR-Runtime.dll および ac8-hud-assets (44アセット)
├── scripts/                    # 9つの配布Luaスクリプト
├── config.txt                  # UEVR Core 設定ファイル
├── cvars_data.txt              # ゲームエンジン CVar 設定
├── features.txt / _ja.txt      # 機能一覧
├── INSTALLATION.md / _ja.md    # インストール手順書
├── README.md / _ja.md          # 概要書
├── CHANGELOG.md / _ja.md       # 更新履歴
├── CONTRIBUTING.md / _ja.md    # コントリビューション規約
├── THIRD_PARTY_NOTICES.md/_ja  # サードパーティ表記
├── PROFILE-FILES.txt           # ファイル構成リスト
└── VERSION                     # バージョン番号
```

### 4.3 配布物に絶対に含めてはならないファイル（除外ブラックリスト）
- `source_code/` フォルダ（一般プレイヤーの実行には不要であり、中間ファイルや大容量リファレンスを含むため）
- `.git/`, `.gitignore`, `.gitattributes`
- 生成された復元ジャーナル・一時キャッシュファイル：
  - `ac8_cinematic_ui_restore.json`
  - `ac8_hangar_restore_v48.json`
  - `ac8_hud_layout_cache.json`
- ログファイル、クラッシュダンプ（`log.txt`, `crash.dmp`）
- 開発者の個人絶対パスが含まれたファイル
- 未パックのゲームアーカイブ、セーブデータ、AES 暗号キー

---

## 5. バージョニング管理ルール

- リポジトリ直下の `VERSION` ファイルの文字列が公式バージョンを表します。
- バージョン番号を変更する際は、以下のファイルを同時に更新し、表記を一致させてください：
  1. `VERSION`
  2. `README.md` および `README_ja.md`
  3. `INSTALLATION.md` および `INSTALLATION_ja.md`
  4. `CHANGELOG.md` および `CHANGELOG_ja.md`
  5. 配布用 ZIP アーカイブのファイル名（例: `AC8-VR-vX.Y.Z.zip`）
  6. Git のリリースタグ（`vX.Y.Z`）
- 正式リリース前（`0.x.x`）の間は、バグ修正にはパッチ番号、新機能の追加にはマイナー番号を増やします。公開済みのバージョン番号を異なる内容で再利用してはなりません。

---

## 6. リリース前 実機検証チェックリスト

リリースビルドを公開する前に、以下の項目を実機（HMD）で必ず確認してください：

- [ ] **クリーン起動**:
  - ゲーム起動時にエラーダイアログが出ず、タイトル画面までスムーズに進むか。
  - 起動ロゴや注意画面の短縮が機能しているか（`AC8_VR-StartupMovies.lua`）。
- [ ] **ポーズ画面操作**:
  - メニュー表示時にキーボード／コントローラーの 1 入力で 1 項目ずつ進むか（二重スキップがないか）。
- [ ] **機体切り替えとカメラ位置**:
  - F/A-18C と F-4E を切り替えた際、それぞれのコックピット視点が適正なアイポイントに配置されるか。
- [ ] **コックピット HUD とレーダー**:
  - 人工水平儀・対気速度計・高度計が姿勢に合わせて狂いなく同期するか。
  - レーダー表示モードを切り替えた際、僚機（Wingman）ステータス表示が追従するか。
- [ ] **ワールドターゲット枠とアニメーション**:
  - 敵機が出現した際、公式の「大→小」に縮小する出現アニメーションが維持されているか。
  - ターゲット枠が VR 視界を邪魔しない適正なサイズにスケーリングされているか。
- [ ] **シネマティック演出**:
  - カットシーン突入時に 2D スクリーンモードへの退避または適切なマスクが適用されるか。
  - F7 キーによる手動トグルが正常に機能するか。
  - シネマティック終了後に元のコックピットカメラおよび VR HUD 設定が 100% 復元されるか。
- [ ] **ロード画面とフェード**:
  - ミッション開始時・終了時のロード画面で、マップが途中でチラ見えしないか。
- [ ] **ミッション終了・格納庫復帰**:
  - ミッションを離脱して格納庫へ戻った際、フリーズやデッドロックが発生せず正常に遷移するか。
- [ ] **ログ確認**:
  - `%APPDATA%\UnrealVRMod\AceCombat8\log.txt` を確認し、致命的な例外や未処理エラーが発生していないか。
