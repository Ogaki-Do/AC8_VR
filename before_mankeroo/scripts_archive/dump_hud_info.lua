-- dump_hud_info.lua (v3)
-- HUDや水平儀のウィジェットツリーと子パーツ（Visibility）を深層調査するスクリプト

local api = uevr.api
if api == nil then return end

local function safe_call(fn, default)
    local ok, res = pcall(fn)
    if ok then return res end
    return default
end

local timestamp_str = os.date("%Y-%m-%d_%H%M%S")
local file = nil
local ok, f = pcall(function() return io.open("data/hud_dump_" .. timestamp_str .. ".txt", "w") end)
if ok and f then
    file = f
else
    local ok2, f2 = pcall(function() return io.open("data/hud_dump.txt", "w") end)
    if ok2 and f2 then file = f2 end
end

local function log(str)
    if file then
        file:write(str .. "\n")
        file:flush()
    end
end

log("==================================================================")
log("  ACE COMBAT 8 - HUD深層調査 & 水平儀パーツ検出 (v3)")
log("  実行日時: " .. os.date("%Y-%m-%d %H:%M:%S"))
log("==================================================================\n")

local vis_names = {
    [0] = "Visible (表示中)",
    [1] = "Collapsed (非表示・サイズ0)",
    [2] = "Hidden (非表示・サイズ維持)",
    [3] = "HitTestInvisible (当たり判定なし表示)",
    [4] = "SelfHitTestInvisible (自分のみ当たり判定なし表示)"
}

-- 1. 全UWidgetの走査と MainFlight HUD 配下の子パーツ洗い出し
log("【1. フライトHUD (WBP_HUD_Chronicle_MainFlight) の子パーツ全走査】")
local widget_class = safe_call(function() return api:find_uobject("Class /Script/UMG.Widget") end, nil)
local all_widgets = {}
if widget_class then
    all_widgets = safe_call(function() return widget_class:get_objects_matching(false) end, {}) or {}
end

log(string.format("  -> メモリ上の全ウィジェット数: %d 個", #all_widgets))

local hud_parts = {}
for _, w in ipairs(all_widgets) do
    local fname = safe_call(function() return w:get_full_name() end, "")
    if fname:find("MainFlight", 1, true) or fname:find("HUD_Chronicle", 1, true) then
        table.insert(hud_parts, w)
    end
end

log(string.format("  -> フライトHUD関連パーツ発見数: %d 個\n", #hud_parts))

for i, w in ipairs(hud_parts) do
    local fname = safe_call(function() return w:get_full_name() end, "unknown")
    local cname = safe_call(function() return w:get_class():get_name() end, "unknown")
    local vis = safe_call(function() return w:call("GetVisibility") end, nil)
    local vis_str = vis_names[vis] or tostring(vis)
    local short_name = fname:match("([^.]+)$") or fname
    
    local is_special = false
    local lshort = short_name:lower()
    if lshort:find("pitch") or lshort:find("horizon") or lshort:find("ladder") or lshort:find("aoa") or lshort:find("reticle") or lshort:find("sight") or lshort:find("crosshair") or lshort:find("flight") or lshort:find("canvas") then
        is_special = true
    end

    if is_special then
        log(string.format("  ★ [%03d] %s (型: %s) -> Visibility: %s", i, short_name, cname, vis_str))
    else
        log(string.format("     [%03d] %s (型: %s) -> Visibility: %s", i, short_name, cname, vis_str))
    end
end

-- 2. コックピットメッシュとマテリアル調査
log("\n【2. プレイヤー機 (F-35C) コックピットメッシュとマテリアル詳細】")
local pawn = safe_call(function() return api:get_player_pawn(0) or api:get_local_pawn(0) end, nil)
if not pawn then
    local pc = safe_call(function() return api:get_player_controller(0) end, nil)
    if pc then pawn = safe_call(function() return pc.Pawn or pc.AcknowledgedPawn end, nil) end
end

if pawn then
    local comps = safe_call(function()
        local mc = api:find_uobject("Class /Script/Engine.MeshComponent")
        return pawn:call("K2_GetComponentsByClass", mc)
    end, nil)
    
    if comps then
        for _, comp in ipairs(comps) do
            local cname = safe_call(function() return comp:get_full_name() end, "")
            if cname:lower():find("cockpit") or cname:lower():find("glass") or cname:lower():find("hud") then
                log("  ● メッシュコンポーネント: " .. cname)
                local num_mats = safe_call(function() return comp:call("GetNumMaterials") end, 0)
                log("    マテリアルスロット数: " .. tostring(num_mats))
                for midx = 0, (num_mats or 1) - 1 do
                    local mat = safe_call(function() return comp:call("GetMaterial", midx) end, nil)
                    if mat then
                        local mname = safe_call(function() return mat:get_full_name() end, "unknown")
                        log(string.format("      [Slot %d] %s", midx, mname))
                    end
                end
            end
        end
    end
else
    log("  -> プレイヤー機体を取得できませんでした")
end

log("\n==================================================================")
log("  深層調査完了")
log("==================================================================")

if file then file:close() end
