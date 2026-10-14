--[[
  ============================================================================
  ac8_hud_hierarchy_tree.lua : HUD 要素ヒエラルキー & 表示切替インスペクター
  ============================================================================
  Game:       ACE COMBAT 8
  Platform:   UEVR (Universal Unreal VR Mod) + OpenXR
  Feature:    HUDの全UMG要素（親Canvas、コンテナ、子Widget）を階層ツリーで可視化！
              各要素の横にあるチェックボックス [✅] で表示・非表示をリアルタイム操作し、
              どのオブジェクトが画面上のどのHUD要素かを簡単に特定・調査できます。
  
  表示イメージ:
    ▼ [✅] [*] WBP_HUD_Chronicle_MainFlight_000_C (UserWidget) [12個の子要素]
      ▼ [✅] [*] WBP_ChroniclePersistent (UserWidget) [8個の子要素]
        ▼ [✅] [*] PitchMeterWidget_1 (PitchMeterWidget) [4個の子要素]
          ・ [✅] [*] End5_R_1 (Image)
          ・ [✅] [*] Positive_R (Image)
        ・ [✅] [*] NeutralPanel (CanvasPanel)
  ============================================================================
--]]

local api = uevr.api
if api == nil then return end

local SCRIPT_NAME = "HUD_HIERARCHY_TREE"
local SCRIPT_VERSION = "v1.1"

-- -----------------------------------------------------------------------------
-- 0. 安全ユーティリティ
-- -----------------------------------------------------------------------------
local function safe_call(fn, default)
    local ok, res = pcall(fn)
    return ok and res or default
end

local function get_safe_name(obj)
    if not obj then return "" end
    local ok, n = pcall(function() return obj:get_full_name() end)
    return (ok and type(n) == "string") and n or ""
end

local function get_short_name(obj)
    local fn = get_safe_name(obj)
    return fn:match("([^.]+)$") or fn
end

local function get_safe_class_name(obj)
    if not obj then return "unknown" end
    local ok, c = pcall(function() return obj:get_class():get_name() end)
    return (ok and type(c) == "string") and c or "unknown"
end

local vis_names = {
    [0] = "Visible",
    [1] = "Collapsed",
    [2] = "Hidden",
    [3] = "HitTestInvisible",
    [4] = "SelfHitTestInvisible"
}

-- -----------------------------------------------------------------------------
-- 1. UMG 子ウィジェット取得関数 (完全階層対応)
-- -----------------------------------------------------------------------------
local function get_widget_children(w)
    if w == nil then return {} end
    local children = {}
    local seen = {}

    -- 1. UserWidget の場合: WidgetTree の RootWidget
    local ok_wt, wt = pcall(function() return w.WidgetTree or w:get_property("WidgetTree") end)
    if ok_wt and wt ~= nil then
        local ok_rw, rw = pcall(function() return wt.RootWidget or wt:get_property("RootWidget") end)
        if ok_rw and rw ~= nil and rw ~= w then
            local p = tostring(rw)
            if not seen[p] then seen[p] = true; table.insert(children, rw) end
        end
    end

    -- 2. 直接の RootWidget プロパティ
    local ok_drw, drw = pcall(function() return w.RootWidget or w:get_property("RootWidget") end)
    if ok_drw and drw ~= nil and drw ~= w then
        local p = tostring(drw)
        if not seen[p] then seen[p] = true; table.insert(children, drw) end
    end

    -- 3. ContentWidget (Border, SizeBox, Button等) の Content
    local ok_cnt, cnt = pcall(function() return w.Content or w:call("GetContent") end)
    if ok_cnt and cnt ~= nil and cnt ~= w then
        local p = tostring(cnt)
        if not seen[p] then seen[p] = true; table.insert(children, cnt) end
    end

    -- 4. PanelWidget (CanvasPanel, HorizontalBox, VerticalBox, Overlay等) の子供
    local count = 0
    local ok_c, res_c = pcall(function() return w:call("GetChildrenCount") end)
    if ok_c and type(res_c) == "number" then count = res_c end
    if count == 0 then
        local ok_c2, res_c2 = pcall(function() return w:GetChildrenCount() end)
        if ok_c2 and type(res_c2) == "number" then count = res_c2 end
    end

    if count > 0 then
        for i = 0, math.min(count - 1, 300) do
            local ch = nil
            local ok_ch, res_ch = pcall(function() return w:call("GetChildAt", i) end)
            if ok_ch and res_ch ~= nil then ch = res_ch end
            if ch == nil then
                local ok_ch2, res_ch2 = pcall(function() return w:GetChildAt(i) end)
                if ok_ch2 and res_ch2 ~= nil then ch = res_ch2 end
            end
            if ch ~= nil and ch ~= w then
                local p = tostring(ch)
                if not seen[p] then seen[p] = true; table.insert(children, ch) end
            end
        end
    end

    return children
end

-- -----------------------------------------------------------------------------
-- 2. 状態管理
-- -----------------------------------------------------------------------------
local S = {
    -- 構築済みツリールート
    roots = {},
    total_node_count = 0,
    scan_status = "未スキャン (出撃後に [🔄 HUDツリーをスキャン] を押してください)",
    scan_timestamp = "なし",

    -- ユーザー操作のオーバーライド保持 (ゲーム側の毎フレーム上書きに対抗)
    hidden_overrides = {},  -- [ptr_string] = { obj = w, node = node }
    shown_overrides  = {},  -- [ptr_string] = { obj = w, node = node, target_vis = int }

    -- カスケード (親のチェックON/OFFを子供にも連動させるか)
    cascade_children = false,

    -- 検索フィルター
    search_query = "",

    -- 選択中ノードの詳細情報
    selected_node = nil,

    -- 点滅 (Blink) 機能
    blink_node = nil,
    blink_timer = 0,
    blink_state = false,

    -- スキャン対象フィルタモード
    -- 0: MainFlight HUD (推奨・軽量)
    -- 1: すべてのゲーム内HUD (HUD関連全般)
    -- 2: すべてのUMGウィジェット (全メモリ)
    scan_mode = 0,

    -- 自動初回スキャン用
    auto_scan_done = false,
    frame_counter = 0,
}

-- -----------------------------------------------------------------------------
-- 3. ノードツリー構築
-- -----------------------------------------------------------------------------
local node_id_counter = 0

local function build_node(w, depth, visited, parent_node)
    if w == nil or depth > 15 then return nil end
    local ptr = tostring(w)
    if visited[ptr] then return nil end
    visited[ptr] = true

    node_id_counter = node_id_counter + 1
    local sn = get_short_name(w)
    local cn = get_safe_class_name(w)
    local fn = get_safe_name(w)

    -- 現在のVisibility
    local cur_vis = safe_call(function() return w:call("GetVisibility") end, 4)
    if type(cur_vis) ~= "number" then cur_vis = 4 end

    -- 初期表示状態 (0=Visible, 3=HitTestInvisible, 4=SelfHitTestInvisible は表示中)
    local is_currently_shown = (cur_vis == 0 or cur_vis == 3 or cur_vis == 4)

    -- 既存のオーバーライド設定があるか確認
    if S.hidden_overrides[ptr] ~= nil then
        is_currently_shown = false
    elseif S.shown_overrides[ptr] ~= nil then
        is_currently_shown = true
    end

    local node = {
        id = string.format("n_%d", node_id_counter),
        ptr = ptr,
        obj = w,
        name = sn,
        class_name = cn,
        full_name = fn,
        depth = depth,
        parent = parent_node,
        children = {},
        expanded = (depth <= 1), -- 最上位ルートと第1階層は初期展開
        visible = is_currently_shown,
        orig_vis = cur_vis,
        match_filter = true,
    }

    -- 子ウィジェットの探索
    local ch_objs = get_widget_children(w)
    for _, ch_w in ipairs(ch_objs) do
        local ch_node = build_node(ch_w, depth + 1, visited, node)
        if ch_node ~= nil then
            table.insert(node.children, ch_node)
        end
    end

    return node
end

local function scan_hud_tree()
    S.scan_status = "スキャン中..."
    node_id_counter = 0
    S.roots = {}
    S.selected_node = nil
    local visited = {}

    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then
        S.scan_status = "エラー: UMG.Widget クラスが見つかりません"
        return
    end

    local all_widgets = safe_call(function() return widget_class:get_objects_matching(false) end, {})
    if not all_widgets or #all_widgets == 0 then
        S.scan_status = "エラー: ウィジェットが検出されませんでした"
        return
    end

    -- ルート候補の検出
    local root_candidates = {}

    if S.scan_mode == 0 then
        -- モード0: MainFlight HUD (最も重要なフライトHUDルート)
        for _, w in ipairs(all_widgets) do
            local fn = get_safe_name(w)
            if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
                if fn:find("MainFlight", 1, true) and fn:find("_C_", 1, true) then
                    table.insert(root_candidates, w)
                end
            end
        end
        -- もし見つからなければHUD全般をフォールバック
        if #root_candidates == 0 then
            for _, w in ipairs(all_widgets) do
                local fn = get_safe_name(w)
                if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
                    if (fn:find("HUD", 1, true) or fn:find("Flight", 1, true)) and fn:find("_C_", 1, true) then
                        table.insert(root_candidates, w)
                    end
                end
            end
        end
    elseif S.scan_mode == 1 then
        -- モード1: ゲーム内すべてのHUD (HUD, Flight, Radar, Reticle, CockpitUI等)
        for _, w in ipairs(all_widgets) do
            local fn = get_safe_name(w)
            if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) then
                local lfn = fn:lower()
                if (lfn:find("hud") or lfn:find("flight") or lfn:find("radar") or lfn:find("gauge") or lfn:find("menu"))
                   and fn:find("_C_", 1, true) then
                    table.insert(root_candidates, w)
                end
            end
        end
    else
        -- モード2: 親を持たない全トップレベルウィジェット
        for _, w in ipairs(all_widgets) do
            local fn = get_safe_name(w)
            if fn:find("Transient", 1, true) and not fn:find("Default__", 1, true) and fn:find("_C_", 1, true) then
                table.insert(root_candidates, w)
            end
        end
    end

    -- 重複・内包除外（親を持つものはルート候補から除外）
    local final_roots = {}
    local seen_ptr = {}
    for _, rw in ipairs(root_candidates) do
        local p = tostring(rw)
        if not seen_ptr[p] then
            seen_ptr[p] = true
            table.insert(final_roots, rw)
        end
    end

    -- ツリー構築
    local total_count = 0
    for _, rw in ipairs(final_roots) do
        local root_node = build_node(rw, 0, visited, nil)
        if root_node then
            table.insert(S.roots, root_node)
        end
    end

    -- カウント集計
    local function count_nodes(n)
        local c = 1
        for _, ch in ipairs(n.children) do
            c = c + count_nodes(ch)
        end
        return c
    end

    for _, rn in ipairs(S.roots) do
        total_count = total_count + count_nodes(rn)
    end

    S.total_node_count = total_count
    S.scan_timestamp = os.date("%H:%M:%S")
    S.scan_status = string.format("スキャン完了: ルート %d 個, 全ノード %d 個 (%s)", #S.roots, total_count, S.scan_timestamp)
    print(string.format("[%s] %s", SCRIPT_NAME, S.scan_status))
end

-- -----------------------------------------------------------------------------
-- 4. 表示／非表示 適用ロジック
-- -----------------------------------------------------------------------------
local function apply_node_visibility(node, show, recursive)
    node.visible = show
    local ptr = node.ptr

    if not show then
        -- 非表示 (Hidden = 2, または Collapsed = 1)
        S.hidden_overrides[ptr] = { obj = node.obj, node = node }
        S.shown_overrides[ptr] = nil
        safe_call(function()
            node.obj:call("SetVisibility", 2) -- Hidden (レイアウト崩れを防ぎ非表示化)
            node.obj:call("SetRenderOpacity", 0.0)
        end)
    else
        -- 表示復元
        S.hidden_overrides[ptr] = nil
        local target_vis = node.orig_vis
        -- 元がHidden/Collapsedだった場合は、強制表示としてSelfHitTestInvisible(4)を使用
        if target_vis == 1 or target_vis == 2 then
            target_vis = 4
        end
        S.shown_overrides[ptr] = { obj = node.obj, node = node, target_vis = target_vis }
        safe_call(function()
            node.obj:call("SetVisibility", target_vis)
            node.obj:call("SetRenderOpacity", 1.0)
        end)
    end

    -- 子ノードへの再帰カスケード
    if recursive and node.children and #node.children > 0 then
        for _, ch in ipairs(node.children) do
            apply_node_visibility(ch, show, true)
        end
    end
end

-- 全復元
local function reset_all_visibility()
    S.hidden_overrides = {}
    S.shown_overrides = {}

    local function rec_reset(n)
        safe_call(function()
            n.obj:call("SetVisibility", n.orig_vis)
            n.obj:call("SetRenderOpacity", 1.0)
        end)
        n.visible = (n.orig_vis == 0 or n.orig_vis == 3 or n.orig_vis == 4)
        for _, ch in ipairs(n.children) do
            rec_reset(ch)
        end
    end

    for _, rn in ipairs(S.roots) do
        rec_reset(rn)
    end
    print(string.format("[%s] 全HUD要素の表示状態を初期状態にリセットしました", SCRIPT_NAME))
end

-- 全展開 / 全折りたたみ
local function set_all_expanded(expand)
    local function rec_exp(n)
        n.expanded = expand
        for _, ch in ipairs(n.children) do
            rec_exp(ch)
        end
    end
    for _, rn in ipairs(S.roots) do
        rec_exp(rn)
    end
end

-- -----------------------------------------------------------------------------
-- 5. 点滅 (Blink) 処理
-- -----------------------------------------------------------------------------
local function start_blink(node)
    S.blink_node = node
    S.blink_timer = 90 -- 約1.5秒間
    S.blink_state = false
end

local function update_blink()
    if S.blink_node and S.blink_timer > 0 then
        S.blink_timer = S.blink_timer - 1
        -- 8フレームごとにON/OFF反転
        if S.blink_timer % 8 == 0 then
            S.blink_state = not S.blink_state
        end

        local obj = S.blink_node.obj
        if obj then
            safe_call(function()
                if S.blink_state then
                    obj:call("SetVisibility", 2) -- Hidden
                    obj:call("SetRenderOpacity", 0.0)
                else
                    obj:call("SetVisibility", 4) -- SelfHitTestInvisible
                    obj:call("SetRenderOpacity", 1.0)
                end
            end)
        end

        -- 終了時復元
        if S.blink_timer == 0 then
            apply_node_visibility(S.blink_node, S.blink_node.visible, false)
            S.blink_node = nil
        end
    end
end

-- -----------------------------------------------------------------------------
-- 6. 毎フレーム Tick (オーバーライドの強制維持)
-- -----------------------------------------------------------------------------
uevr.sdk.callbacks.on_post_engine_tick(function()
    S.frame_counter = S.frame_counter + 1

    -- 点滅更新
    update_blink()

    -- 毎フレーム: 非表示オーバーライドを強制維持 (ゲーム側のTick書き換えに対抗)
    for ptr, item in pairs(S.hidden_overrides) do
        if item.obj then
            safe_call(function()
                item.obj:call("SetVisibility", 2)
                item.obj:call("SetRenderOpacity", 0.0)
            end)
        end
    end

    -- 毎フレーム: 強制表示オーバーライドを維持
    for ptr, item in pairs(S.shown_overrides) do
        if item.obj then
            safe_call(function()
                item.obj:call("SetVisibility", item.target_vis)
                item.obj:call("SetRenderOpacity", 1.0)
            end)
        end
    end

    -- 出撃後 (約300フレーム後) に自動初回スキャンを試みる (未スキャン時のみ)
    if not S.auto_scan_done and S.frame_counter >= 300 and #S.roots == 0 then
        S.auto_scan_done = true
        scan_hud_tree()
    end
end)

-- -----------------------------------------------------------------------------
-- 7. 検索フィルタ評価
-- -----------------------------------------------------------------------------
local function evaluate_filter(node, q)
    if q == "" then
        node.match_filter = true
        for _, ch in ipairs(node.children) do
            evaluate_filter(ch, q)
        end
        return true
    end

    local q_lower = q:lower()
    local self_match = node.name:lower():find(q_lower, 1, true) ~= nil
                    or node.class_name:lower():find(q_lower, 1, true) ~= nil

    local any_child_match = false
    for _, ch in ipairs(node.children) do
        if evaluate_filter(ch, q) then
            any_child_match = true
        end
    end

    node.match_filter = self_match or any_child_match
    -- マッチした場合は親を自動展開
    if node.match_filter and q ~= "" then
        node.expanded = true
    end
    return node.match_filter
end

-- -----------------------------------------------------------------------------
-- 8. ImGui UI描画
-- -----------------------------------------------------------------------------
local function render_node_tree(node)
    if not node.match_filter then return end

    local has_children = (node.children ~= nil and #node.children > 0)
    local indent_str = string.rep("    ", node.depth)

    -- インデントスペース
    if node.depth > 0 then
        imgui.text(indent_str)
        imgui.same_line()
    end

    -- 1. [▼ / ▶] 展開・折りたたみボタン (子がある場合のみ)
    if has_children then
        local toggle_label = node.expanded and "v##exp_" .. node.id or ">##exp_" .. node.id
        if imgui.button(toggle_label) then
            node.expanded = not node.expanded
        end
    else
        -- 子のない末端要素は位置揃え用の小スペース
        imgui.text("  ")
    end
    imgui.same_line()

    -- 2. [✅] 表示・非表示 チェックボックス
    local ch_vis, val_vis = imgui.checkbox("##chk_" .. node.id, node.visible)
    if ch_vis then
        apply_node_visibility(node, val_vis, S.cascade_children)
    end
    imgui.same_line()

    -- 3. [*] 点滅ボタン (画面上でピカピカ点滅させて即座に特定)
    if imgui.button("*##blk_" .. node.id) then
        start_blink(node)
    end
    imgui.same_line()

    -- 4. オブジェクト名 & クラス名 & 子要素数表示
    local is_selected = (S.selected_node == node)
    local child_info = has_children and string.format(" [%d]", #node.children) or ""
    local display_label = string.format("%s (%s)%s##lbl_%s", node.name, node.class_name, child_info, node.id)

    -- 色分け: コンテナ親(黄) / 末端パーツ(水色) / 非表示中(グレー) / 選択中(緑)
    local color = has_children and 0xFFFFFF88 or 0xFFAAAAFF
    if not node.visible then
        color = 0xFF888888
    end
    if is_selected then
        color = 0xFF55FF55
    end

    imgui.text_colored(display_label, color)
    if imgui.is_item_clicked ~= nil and imgui.is_item_clicked() then
        S.selected_node = node
    end

    -- 5. 展開されている場合は子供を再帰描画
    if has_children and node.expanded then
        for _, ch in ipairs(node.children) do
            render_node_tree(ch)
        end
    end
end

local function render_ui()
    imgui.text("====================================================================")
    imgui.text_colored(string.format("  AC8 HUD 要素ヒエラルキー & 表示切替インスペクター %s", SCRIPT_VERSION), 0xFF00FFCC)
    imgui.text("  [v/>]: 展開/折りたたみ | [✅]: 表示/非表示 | [*]: 画面上でピカピカ点滅")
    imgui.text("====================================================================")

    -- スキャンボタン & 状態
    if imgui.button(">>> 🔄 HUDツリーをスキャン (更新) <<<##btn_scan") then
        scan_hud_tree()
    end
    imgui.same_line()
    imgui.text(string.format("状態: %s", S.scan_status))

    -- スキャンモード選択
    imgui.text("スキャン範囲: ")
    imgui.same_line()
    if imgui.radio_button("MainFlight HUD (標準)##m0", S.scan_mode == 0) then
        S.scan_mode = 0
    end
    imgui.same_line()
    if imgui.radio_button("HUD全般##m1", S.scan_mode == 1) then
        S.scan_mode = 1
    end
    imgui.same_line()
    if imgui.radio_button("全UMGウィジェット##m2", S.scan_mode == 2) then
        S.scan_mode = 2
    end

    imgui.separator()

    -- 全体一括操作ボタン群
    if imgui.button("▼ 全て展開##btn_exp_all") then
        set_all_expanded(true)
    end
    imgui.same_line()
    if imgui.button("▶ 全て折りたたむ##btn_col_all") then
        set_all_expanded(false)
    end
    imgui.same_line()
    if imgui.button("↺ 初期状態にリセット##btn_reset_all") then
        reset_all_visibility()
    end
    imgui.same_line()
    local ch_cas, val_cas = imgui.checkbox("親チェック時に子供も連動 (Cascade)##chk_cascade", S.cascade_children)
    if ch_cas then
        S.cascade_children = val_cas
    end

    -- リアルタイム検索フィルター
    if imgui.input_text ~= nil then
        local ch_q, new_q = imgui.input_text("名前で検索・絞り込み##filter_q", S.search_query)
        if ch_q then
            S.search_query = new_q
            for _, rn in ipairs(S.roots) do
                evaluate_filter(rn, S.search_query)
            end
        end
    end

    imgui.separator()

    -- 選択ノードの詳細情報パネル
    if S.selected_node ~= nil then
        local sn = S.selected_node
        imgui.text_colored("【選択中オブジェクトの詳細情報】", 0xFFFFAA00)
        imgui.text(string.format("  名前: %s | クラス: %s | 初期Visibility: %s (%d)",
            sn.name, sn.class_name, vis_names[sn.orig_vis] or "不明", sn.orig_vis))

        -- 座標やサイズ、RenderTransform情報の取得
        local tx, ty, rot = 0.0, 0.0, 0.0
        safe_call(function()
            local rt = sn.obj:get_property("RenderTransform")
            if rt and rt.Translation then
                tx = rt.Translation.X or rt.Translation.x or 0.0
                ty = rt.Translation.Y or rt.Translation.y or 0.0
            end
            if rt and rt.Angle then rot = rt.Angle end
        end)
        local ds_x, ds_y = 0.0, 0.0
        safe_call(function()
            local ds = sn.obj:call("GetDesiredSize")
            if ds then ds_x = ds.X or ds.x or 0.0; ds_y = ds.Y or ds.y or 0.0 end
        end)

        imgui.text(string.format("  RT位置: (X=%.1f, Y=%.1f, 角度=%.1f) | 望ましいサイズ: (W=%.1f, H=%.1f)", tx, ty, rot, ds_x, ds_y))
        imgui.text(string.format("  フルパス: %s", sn.full_name))

        if imgui.button("この要素を点滅させる##btn_sel_blink") then
            start_blink(sn)
        end
        imgui.same_line()
        if imgui.button("ログに出力 (print)##btn_log_sel") then
            print(string.format("[%s] SELECTED WIDGET: Name=%s, Class=%s, Path=%s", SCRIPT_NAME, sn.name, sn.class_name, sn.full_name))
        end
        imgui.same_line()
        if imgui.button("選択解除##btn_deselect") then
            S.selected_node = nil
        end
        imgui.separator()
    end

    -- ツリービュー本体
    if #S.roots == 0 then
        imgui.text_colored("ツリーが読み込まれていません。上の [🔄 HUDツリーをスキャン] をクリックしてください！", 0xFFFFFF77)
    else
        imgui.text(string.format("HUD ヒエラルキー ツリー一覧 (全 %d 要素):", S.total_node_count))
        for _, rn in ipairs(S.roots) do
            render_node_tree(rn)
        end
    end
end

if uevr.sdk.callbacks.on_draw_ui ~= nil then
    uevr.sdk.callbacks.on_draw_ui(function()
        pcall(render_ui)
    end)
end

print(string.format("[%s] %s が正常にロードされました。", SCRIPT_NAME, SCRIPT_VERSION))
