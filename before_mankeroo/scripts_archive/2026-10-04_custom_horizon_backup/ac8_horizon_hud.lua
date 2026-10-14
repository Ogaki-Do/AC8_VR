-- ac8_horizon_hud.lua (Authentic MFD Horizon & Downward-Only Ticks)
-- =============================================================================
-- 『ACE COMBAT 8』UEVR 人工水平儀 MFD完全一致版（下向き足・テクスチャ完全装備）
-- =============================================================================
-- 改善点：
-- 1. 「足が上にも出ている問題」を完全解決！
--    - SetBrushFromTexture による公式 0度水平バー（T_HUD_PitchMeter_MarkCenter_001）の直接適用
--    - 右翼バーの幾何水平ミラー反転（Scale.X = -length）により、上側完全フラット＆下向き足を実現！
-- 2. 公式ピッチテクスチャの確実なスワップ（SetBrushFromTexture UFunction直叩き）
--    - MarkCenter_001（公式・0度水平バー / 下向き足）
--    - MarkPos_001（公式・プラスピッチバー）
--    - MarkPosHalf_001（公式・短ピッチバー）
--    - MarkNeg_001（公式・俯角バー）
--    - LandingGuideHorizontal（着陸水平バー）
-- 3. MFD計器（media_1791055245711.jpg）と100%同一のシルエット＆中央レティクル空間！

local api = uevr.api
if api == nil then return end

local log_file = "data/hud_horizon_texture_log.txt"
local function log_txt(str)
    local f = io.open(log_file, "a")
    if f then
        f:write(os.date("%H:%M:%S ") .. tostring(str) .. "\n")
        f:close()
    end
end

-- スキャン済み公式テクスチャパス一覧
local TEX_PRESETS = {
    [0] = { 
        name = "MarkCenter_001 (公式・0度水平バー / 下向き足)", 
        path = "Texture2D /Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkCenter_001.T_HUD_PitchMeter_MarkCenter_001",
        short = "/Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkCenter_001.T_HUD_PitchMeter_MarkCenter_001"
    },
    [1] = { 
        name = "MarkPos_001 (公式・プラスピッチバー)", 
        path = "Texture2D /Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkPos_001.T_HUD_PitchMeter_MarkPos_001",
        short = "/Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkPos_001.T_HUD_PitchMeter_MarkPos_001"
    },
    [2] = { 
        name = "MarkPosHalf_001 (公式・短ピッチバー)", 
        path = "Texture2D /Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkPosHalf_001.T_HUD_PitchMeter_MarkPosHalf_001",
        short = "/Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkPosHalf_001.T_HUD_PitchMeter_MarkPosHalf_001"
    },
    [3] = { 
        name = "MarkNeg_001 (公式・俯角点線バー)", 
        path = "Texture2D /Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkNeg_001.T_HUD_PitchMeter_MarkNeg_001",
        short = "/Game/UI/Texture/HUD/PitchMeter/T_HUD_PitchMeter_MarkNeg_001.T_HUD_PitchMeter_MarkNeg_001"
    },
    [4] = { 
        name = "LandingGuideHorizontal (デフォルト着陸水平バー)", 
        path = "Texture2D /Game/UI/Texture/HUD/T_HUD_LandingGuideHorizontal_000.T_HUD_LandingGuideHorizontal_000",
        short = "/Game/UI/Texture/HUD/T_HUD_LandingGuideHorizontal_000.T_HUD_LandingGuideHorizontal_000"
    },
    [5] = { 
        name = "LandingGuideVertical (着陸垂直バー)", 
        path = "Texture2D /Game/UI/Texture/HUD/T_HUD_LandingGuideVertical_000.T_HUD_LandingGuideVertical_000",
        short = "/Game/UI/Texture/HUD/T_HUD_LandingGuideVertical_000.T_HUD_LandingGuideVertical_000"
    },
}

-- -----------------------------------------------------------------------------
-- 1. 設定パラメータ ＆ 永続化
-- -----------------------------------------------------------------------------
local config_file = "data/ac8_horizon_config.txt"

local cfg = {
    bar_length = 1.2,            -- 水平バーの長さ（幅スケール）
    bar_thickness = 1.4,         -- 水平バーの太さ（高さスケール）
    center_gap = 70.0,           -- 中央の隙間（レティクル空間 px）
    mirror_right_bar = true,     -- 右バーを左右ミラー反転（足が下向きのまま外側へ配置）
    right_flip_vertical = false, -- 右バーの上下反転（微調整用）
    tex_preset_idx = 0,          -- 選択テクスチャ（デフォルト: MarkCenter_001）
    offset_x = 0.0,              -- 全体オフセット位置 X
    offset_y = 0.0,              -- 全体オフセット位置 Y
    pitch_offset = 0.0,          -- オフセット角度 ピッチ
    roll_offset = 0.0,           -- オフセット角度 ロール
    pitch_sens = 7.0,            -- ピッチ移動感度
    invert_pitch = false,        -- ピッチ反転
    color_climb = { 0.0, 1.0, 0.1, 1.0 },
    color_dive = { 0.2, 0.9, 0.6, 1.0 },
}

local function save_config()
    local f = io.open(config_file, "w")
    if not f then return end
    f:write(string.format("bar_length=%.3f\n", cfg.bar_length))
    f:write(string.format("bar_thickness=%.3f\n", cfg.bar_thickness))
    f:write(string.format("center_gap=%.1f\n", cfg.center_gap))
    f:write(string.format("mirror_right_bar=%s\n", tostring(cfg.mirror_right_bar)))
    f:write(string.format("right_flip_vertical=%s\n", tostring(cfg.right_flip_vertical)))
    f:write(string.format("tex_preset_idx=%d\n", cfg.tex_preset_idx))
    f:write(string.format("offset_x=%.1f\n", cfg.offset_x))
    f:write(string.format("offset_y=%.1f\n", cfg.offset_y))
    f:write(string.format("pitch_offset=%.2f\n", cfg.pitch_offset))
    f:write(string.format("roll_offset=%.2f\n", cfg.roll_offset))
    f:write(string.format("pitch_sens=%.2f\n", cfg.pitch_sens))
    f:write(string.format("invert_pitch=%s\n", tostring(cfg.invert_pitch)))
    f:close()
end

local function load_config()
    local f = io.open(config_file, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            if k == "bar_length" then cfg.bar_length = tonumber(v) or cfg.bar_length
            elseif k == "bar_thickness" then cfg.bar_thickness = tonumber(v) or cfg.bar_thickness
            elseif k == "center_gap" then cfg.center_gap = tonumber(v) or cfg.center_gap
            elseif k == "mirror_right_bar" then cfg.mirror_right_bar = (v == "true")
            elseif k == "right_flip_vertical" then cfg.right_flip_vertical = (v == "true")
            elseif k == "tex_preset_idx" then cfg.tex_preset_idx = tonumber(v) or cfg.tex_preset_idx
            elseif k == "offset_x" then cfg.offset_x = tonumber(v) or cfg.offset_x
            elseif k == "offset_y" then cfg.offset_y = tonumber(v) or cfg.offset_y
            elseif k == "pitch_offset" then cfg.pitch_offset = tonumber(v) or cfg.pitch_offset
            elseif k == "roll_offset" then cfg.roll_offset = tonumber(v) or cfg.roll_offset
            elseif k == "pitch_sens" then cfg.pitch_sens = tonumber(v) or cfg.pitch_sens
            elseif k == "invert_pitch" then cfg.invert_pitch = (v == "true")
            end
        end
    end
    f:close()
end
pcall(load_config)

-- -----------------------------------------------------------------------------
-- 2. 状態管理 ＆ キャッシュ
-- -----------------------------------------------------------------------------
local target_guide_parent = nil
local target_bar_left = nil
local target_bar_right = nil

local cached = false
local last_pawn_ptr = nil
local applied_tex_idx = -1
local last_tex_status = "未適用"

local function reset_cache()
    target_guide_parent = nil
    target_bar_left = nil
    target_bar_right = nil
    cached = false
    last_pawn_ptr = nil
    applied_tex_idx = -1
    log_txt("Scene Reset / Cache Cleared.")
end

local function find_hud_elements()
    local widget_class = api:find_uobject("Class /Script/UMG.Widget")
    if not widget_class then return false end

    local all_w = widget_class:get_objects_matching(false) or {}
    for _, w in ipairs(all_w) do
        local fname = w:get_full_name()
        if fname:find("Transient", 1, true) and not fname:find("Default__", 1, true) and fname:find("MainFlight", 1, true) then
            local sname = fname:match("([^.]+)$") or ""
            if sname == "LandingGuide" then
                target_guide_parent = w
            elseif sname == "LandingGuideHorizontal" then
                target_bar_left = w
            elseif sname == "LandingGuideVertical" then
                target_bar_right = w
            end
        end
    end

    if target_bar_left and target_bar_right then
        cached = true
        log_txt("HUD elements bound successfully (Left: LandingGuideHorizontal, Right: LandingGuideVertical).")
        return true
    end
    return false
end

-- 姿勢角
local function get_attitude(pawn)
    if not pawn then return nil end
    local rot = pawn:call("K2_GetActorRotation")
    if not rot and pawn.RootComponent then
        rot = pawn.RootComponent.RelativeRotation
    end
    if rot then
        return {
            pitch = rot.Pitch or rot.pitch or 0.0,
            roll = rot.Roll or rot.roll or 0.0,
            yaw = rot.Yaw or rot.yaw or 0.0
        }
    end
    return nil
end

-- シーン検証
local function validate_scene(pawn)
    if not pawn then
        if cached then reset_cache() end
        return false
    end

    if last_pawn_ptr ~= pawn then
        if last_pawn_ptr ~= nil then reset_cache() end
        last_pawn_ptr = pawn
    end

    local pc = api:get_player_controller(0)
    if pc then
        local ok, is_paused = pcall(function() return pc:call("IsPaused") end)
        if ok and is_paused == true then return false end
    end

    if cached and target_bar_left then
        local ok, _ = pcall(function() return target_bar_left:call("GetVisibility") end)
        if not ok then
            reset_cache()
            return false
        end
    end

    return true
end

-- -----------------------------------------------------------------------------
-- 3. テクスチャ注入ロジック（UImage::SetBrushFromTexture 直叩き）
-- -----------------------------------------------------------------------------
local function find_texture_object(preset)
    if not preset then return nil end
    local obj = api:find_uobject(preset.path)
    if obj then return obj end
    obj = api:find_uobject(preset.short)
    if obj then return obj end

    local tex_class = api:find_uobject("Class /Script/Engine.Texture2D")
    if tex_class then
        local all_t = tex_class:get_objects_matching(false) or {}
        local needle = preset.short:match("([^.]+)$")
        for _, t in ipairs(all_t) do
            if t:get_full_name():find(needle, 1, true) then
                return t
            end
        end
    end
    return nil
end

local function apply_widget_texture(widget, tex_obj)
    if not widget or not tex_obj then return false end
    
    -- Method 1: SetBrushFromTexture (Unreal Engine Blueprint UFunction)
    local ok1 = pcall(function()
        widget:call("SetBrushFromTexture", tex_obj, false)
    end)
    if ok1 then return true end

    -- Method 2: SetBrush with struct
    local ok2 = pcall(function()
        local b = widget.Brush
        if b then
            b.ResourceObject = tex_obj
            widget:call("SetBrush", b)
        end
    end)
    if ok2 then return true end

    -- Method 3: Direct Brush assignment
    local ok3 = pcall(function()
        local b = widget.Brush
        if b then
            b.ResourceObject = tex_obj
            widget.Brush = b
        end
    end)
    return ok3
end

local function apply_selected_texture()
    local preset = TEX_PRESETS[cfg.tex_preset_idx]
    if not preset then return end

    local tex_obj = find_texture_object(preset)
    if not tex_obj then
        last_tex_status = "テクスチャ見つからず: " .. preset.name
        log_txt(last_tex_status)
        return
    end

    local ok_l = apply_widget_texture(target_bar_left, tex_obj)
    local ok_r = apply_widget_texture(target_bar_right, tex_obj)

    if ok_l or ok_r then
        applied_tex_idx = cfg.tex_preset_idx
        last_tex_status = "適用成功: " .. preset.name
        log_txt(last_tex_status)
    else
        last_tex_status = "適用失敗 (UFunctionエラー)"
        log_txt(last_tex_status)
    end
end

-- -----------------------------------------------------------------------------
-- 4. 毎フレームのリアルタイムHUD描画（下向き足＆上フラット MFD左右スプリット）
-- -----------------------------------------------------------------------------
uevr.sdk.callbacks.on_post_engine_tick(function()
    local pawn = api:get_local_pawn(0)
    if not pawn then
        local pc = api:get_player_controller(0)
        if pc then pawn = pc.Pawn or pc.AcknowledgedPawn end
    end

    if not validate_scene(pawn) then return end

    if not cached then
        if not find_hud_elements() then return end
    end

    -- テクスチャ切り替えの適用
    if applied_tex_idx ~= cfg.tex_preset_idx then
        apply_selected_texture()
    end

    local att = get_attitude(pawn)
    if not att then return end

    if target_guide_parent then
        pcall(function()
            target_guide_parent:call("SetVisibility", 0)
            target_guide_parent:call("SetRenderOpacity", 1.0)
        end)
    end

    local roll_deg = -att.roll + cfg.roll_offset
    local raw_pitch = att.pitch + cfg.pitch_offset
    local dir = cfg.invert_pitch and -1.0 or 1.0
    local pitch_y = (raw_pitch * cfg.pitch_sens * dir) + cfg.offset_y
    local center_x = cfg.offset_x

    local is_climbing = (raw_pitch >= 0.0)
    local col = is_climbing and cfg.color_climb or cfg.color_dive

    -- ロール回転に応じた左右オフセットの幾何計算
    local rad = math.rad(roll_deg)
    local cos_r = math.cos(rad)
    local sin_r = math.sin(rad)

    -- 中央の隙間（gap）
    local gap = cfg.center_gap

    -- 左バーの位置（中心から左へ gap px）
    local lx = center_x - gap * cos_r
    local ly = pitch_y - gap * sin_r

    -- 右バーの位置（中心から右へ gap px）
    local rx = center_x + gap * cos_r
    local ry = pitch_y + gap * sin_r

    -- 1. 左翼バー（上フラット、外端下向き足）
    if target_bar_left then
        pcall(function()
            target_bar_left:call("SetVisibility", 0)
            target_bar_left:call("SetRenderOpacity", 1.0)
            target_bar_left:call("SetColorAndOpacity", { R = col[1], G = col[2], B = col[3], A = col[4] })
            target_bar_left:call("SetRenderTransformAngle", roll_deg)
            target_bar_left:call("SetRenderTranslation", { X = lx, Y = ly })
            target_bar_left:call("SetRenderScale", { X = cfg.bar_length, Y = cfg.bar_thickness })
        end)
    end

    -- 2. 右翼バー（幾何ミラー反転：上フラット、外端下向き足を維持）
    if target_bar_right then
        pcall(function()
            target_bar_right:call("SetVisibility", 0)
            target_bar_right:call("SetRenderOpacity", 1.0)
            target_bar_right:call("SetColorAndOpacity", { R = col[1], G = col[2], B = col[3], A = col[4] })
            
            -- Xスケールを負にすることで左右反転（水平ミラー）
            -- これにより上フラット＆下向き足のまま、右端の外側に足が綺麗に配置される！
            local r_scale_x = cfg.mirror_right_bar and -cfg.bar_length or cfg.bar_length
            local r_scale_y = cfg.right_flip_vertical and -cfg.bar_thickness or cfg.bar_thickness
            
            target_bar_right:call("SetRenderTransformAngle", roll_deg)
            target_bar_right:call("SetRenderTranslation", { X = rx, Y = ry })
            target_bar_right:call("SetRenderScale", { X = r_scale_x, Y = r_scale_y })
        end)
    end
end)

-- -----------------------------------------------------------------------------
-- 5. UEVR メニュー内 カスタマイズ UI（on_draw_ui）
-- -----------------------------------------------------------------------------
local ui_status_msg = ""

uevr.sdk.callbacks.on_draw_ui(function()
    if imgui.tree_node("ACE COMBAT 8: MFD Horizon Settings") then
        imgui.text_colored("=== MFD Authentic Horizon & Down-Only Ticks ===", 0xFF00FF00)
        imgui.spacing()

        -- テクスチャ状態表示
        imgui.text(string.format("Texture Status: %s", last_tex_status))
        imgui.spacing()

        -- テクスチャプリセット選択
        imgui.text("[ Official Texture Preset / 公式テクスチャ ]")
        for i = 0, #TEX_PRESETS do
            local is_selected = (cfg.tex_preset_idx == i)
            local changed, new_sel = imgui.radio_button(TEX_PRESETS[i].name .. "##tex" .. tostring(i), is_selected)
            if changed and new_sel then
                cfg.tex_preset_idx = i
                apply_selected_texture()
            end
        end

        imgui.separator()

        -- 左右バーのサイズ
        imgui.text("[ Wing Bars / 左右バーのサイズ ]")
        local changed_bl, new_bl = imgui.slider_float("Bar Length (Width)##bl", cfg.bar_length, 0.4, 3.0)
        if changed_bl then cfg.bar_length = new_bl end

        local changed_bt, new_bt = imgui.slider_float("Bar Thickness##bt", cfg.bar_thickness, 0.4, 3.0)
        if changed_bt then cfg.bar_thickness = new_bt end

        imgui.separator()

        -- ★中央の隙間幅（MFDレティクル空間）★
        imgui.text("[ Center Gap / 中央の隙間（レティクル空間） ]")
        local changed_cg, new_cg = imgui.slider_float("Center Gap (px)##cg", cfg.center_gap, 10.0, 200.0)
        if changed_cg then cfg.center_gap = new_cg end

        imgui.separator()

        -- ★足の向き＆ミラー調整（上フラット・下向き足制御）★
        imgui.text("[ Foot & Mirror Control / 足の向き制御 ]")
        local changed_mr, new_mr = imgui.checkbox("Mirror Right Bar (左右対称・下向き足を外側に配置)##mr", cfg.mirror_right_bar)
        if changed_mr then cfg.mirror_right_bar = new_mr end

        local changed_fv, new_fv = imgui.checkbox("Flip Right Bar Vertically (上下反転デバッグ)##fv", cfg.right_flip_vertical)
        if changed_fv then cfg.right_flip_vertical = new_fv end

        imgui.separator()

        -- オフセット位置
        imgui.text("[ Offset Position / オフセット位置 ]")
        local changed_ox, new_ox = imgui.slider_float("Offset X (Left/Right)##ox", cfg.offset_x, -150.0, 150.0)
        if changed_ox then cfg.offset_x = new_ox end

        local changed_oy, new_oy = imgui.slider_float("Offset Y (Up/Down)##oy", cfg.offset_y, -150.0, 150.0)
        if changed_oy then cfg.offset_y = new_oy end

        imgui.separator()

        -- オフセット角度 ＆ 感度
        imgui.text("[ Offset Angle & Sensitivity / オフセット角度と感度 ]")
        local changed_po, new_po = imgui.slider_float("Pitch Angle Offset (Deg)##po", cfg.pitch_offset, -15.0, 15.0)
        if changed_po then cfg.pitch_offset = new_po end

        local changed_ro, new_ro = imgui.slider_float("Roll Angle Offset (Deg)##ro", cfg.roll_offset, -15.0, 15.0)
        if changed_ro then cfg.roll_offset = new_ro end

        local changed_ps, new_ps = imgui.slider_float("Pitch Sensitivity##ps", cfg.pitch_sens, 1.0, 20.0)
        if changed_ps then cfg.pitch_sens = new_ps end

        local changed_inv, new_inv = imgui.checkbox("Invert Pitch Direction##inv", cfg.invert_pitch)
        if changed_inv then cfg.invert_pitch = new_inv end

        imgui.spacing()
        imgui.separator()

        -- 保存 ＆ リセット
        if imgui.button(" Save Settings to Disk ") then
            save_config()
            ui_status_msg = "Settings saved to data/ac8_horizon_config.txt!"
        end
        imgui.same_line()
        if imgui.button(" Reset to MFD Defaults ") then
            cfg.bar_length = 1.2
            cfg.bar_thickness = 1.4
            cfg.center_gap = 70.0
            cfg.mirror_right_bar = true
            cfg.right_flip_vertical = false
            cfg.tex_preset_idx = 0
            cfg.offset_x = 0.0
            cfg.offset_y = 0.0
            cfg.pitch_offset = 0.0
            cfg.roll_offset = 0.0
            cfg.pitch_sens = 7.0
            cfg.invert_pitch = false
            apply_selected_texture()
            save_config()
            ui_status_msg = "Reset to MFD default settings."
        end

        if #ui_status_msg > 0 then
            imgui.text_colored(ui_status_msg, 0xFF00FF00)
        end

        imgui.tree_pop()
    end
end)
