-- test_grid_draw.lua
-- HMD描画方式のグリッド一括比較テストスクリプト
-- 画面の4箇所に異なる方式で描画し、スクショ1回で成否を全判定する

local api = uevr.api
if api == nil then return end

local function safe_call(fn)
    local ok, res = pcall(fn)
    if ok then return res end
    return nil
end

-- =========================================================================
-- [手法 1] 左上: on_frame コールバック + ImGui 標準ウィンドウ (黄色)
-- =========================================================================
uevr.sdk.callbacks.on_frame(function()
    safe_call(function()
        imgui.set_next_window_pos({100, 100})
        imgui.set_next_window_size({380, 140})
        if imgui.begin_window("METHOD 1: on_frame Window", nil, 0) then
            imgui.text_colored("<<< METHOD 1: on_frame Window >>>", 0xFF00FFFF) -- Yellow (ARGB)
            imgui.text("Always rendered every frame?")
            imgui.text("Does this stay when menu is CLOSED?")
            imgui.button("[ Method 1 OK ]")
            imgui.end_window()
        end
    end)
end)

-- =========================================================================
-- [手法 2] 中央: on_frame + 公式 DrawList パス描画による図形 (ネオングリーン)
-- =========================================================================
uevr.sdk.callbacks.on_frame(function()
    safe_call(function()
        -- 画面中央 (960, 540) に透明全画面キャンバス
        local flags = 1 + 2 + 4 + 8 + 128 -- NoTitleBar, NoResize, NoMove, NoScrollbar, NoBackground
        imgui.set_next_window_pos({0, 0})
        imgui.set_next_window_size({1920, 1080})
        imgui.push_style_var(imgui.ImGuiStyleVar.WindowBorderSize, 0.0)

        if imgui.begin_window("METHOD_2_CANVAS", nil, flags) then
            local cx, cy = 960, 540
            local green = 0xFF00FF00 -- Green (ARGB)

            -- 横線
            imgui.draw_list_path_clear()
            imgui.draw_list_path_line_to({cx - 120, cy})
            imgui.draw_list_path_line_to({cx + 120, cy})
            imgui.draw_list_path_stroke(green, false, 4.0)

            -- 縦線
            imgui.draw_list_path_clear()
            imgui.draw_list_path_line_to({cx, cy - 70})
            imgui.draw_list_path_line_to({cx, cy + 70})
            imgui.draw_list_path_stroke(green, false, 4.0)

            -- ひし形 (中央レティクル風)
            imgui.draw_list_path_clear()
            imgui.draw_list_path_line_to({cx, cy - 25})
            imgui.draw_list_path_line_to({cx + 25, cy})
            imgui.draw_list_path_line_to({cx, cy + 25})
            imgui.draw_list_path_line_to({cx - 25, cy})
            imgui.draw_list_path_stroke(green, true, 3.0)

            -- ラベル
            imgui.set_cursor_screen_pos({cx - 110, cy + 80})
            imgui.text_colored("<<< METHOD 2: DrawList Shapes >>>", green)

            imgui.end_window()
        end
        imgui.pop_style_var()
    end)
end)

-- =========================================================================
-- [手法 3] 右上: on_draw_ui コールバック + ImGui ウィンドウ (水色)
-- =========================================================================
uevr.sdk.callbacks.on_draw_ui(function()
    safe_call(function()
        imgui.set_next_window_pos({1400, 100})
        imgui.set_next_window_size({380, 140})
        if imgui.begin_window("METHOD 3: on_draw_ui Window", nil, 0) then
            imgui.text_colored("<<< METHOD 3: on_draw_ui >>>", 0xFFFFFF00) -- Cyan (ARGB)
            imgui.text("Constrained to UEVR menu layer.")
            imgui.text("Likely disappears when menu closed.")
            imgui.button("[ Method 3 Test ]")
            imgui.end_window()
        end
    end)
end)

-- =========================================================================
-- [手法 4] 左上のゲーム内UI (SCOREテキスト) をLuaから直接書き換え (ピンク)
-- =========================================================================
local uobject_hooked = false
uevr.sdk.callbacks.on_post_engine_tick(function()
    if uobject_hooked then return end
    safe_call(function()
        local text_class = api:find_uobject("Class /Script/UMG.TextBlock")
        if text_class then
            local texts = text_class:get_objects_matching(false) or {}
            for _, tb in ipairs(texts) do
                local name = tb:get_full_name()
                if name:find("PrivateScoreText", 1, true) or name:find("ScoreText", 1, true) then
                    tb:call("SetText", "M4: LUA UMG OK!")
                    uobject_hooked = true
                end
            end
        end
    end)
end)
