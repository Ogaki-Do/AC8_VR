-- ============================================================================
--  AC8 过场守护 v1   (ac8_cutscene_guard_v1.lua)
-- ----------------------------------------------------------------------------
--  目的
--    规避皇牌空战8 过场动画时 UEVR 渲染线程死循环导致的崩溃：
--        LowLevelFatalError [RenderingThread.cpp:1415]
--        GameThread timed out waiting for RenderThread after 120.00 secs
--
--  为什么这么治（证据链，均为本机实锤）
--    1. 游戏自带崩溃报告 CrashContext.runtime-xml：RenderThread 0 整段栈
--       都在 UEVRBackend，是 CPU 侧死循环（栈顶无 ntdll 等待帧），不是等 GPU。
--    2. UEVR 日志同期 1417 次
--       "the vtable is already hooked, maybe previous frame was not rendered?"
--    3. 这个 UEVR fork 其实**自带同类保护**：
--       VR.cpp  update_shf_auto_2d_mode()
--       逻辑 = 检测到过场 -> m_2d_screen_mode = true（切 2D 单屏，绕开
--       立体双 pass），过场结束再还原。
--       但它被 is_shf_executable() 门禁限制为只对 "shf-win64-shipping"
--       生效；AC8 是 AceCombat8.exe，所以这个保护从不触发（日志里
--       "[SHf][Auto2D]" 一条都没有）。
--       => 本脚本就是把这个官方策略搬到 Lua 侧，对 AC8 生效。
--
--  三道防线
--    A 预防：过场切相机（换 pawn）且渲染已有轻微停滞 -> 立刻切 2D 模式。
--    B 兜底：渲染线程心跳停顿超过 STALL_SEC 秒 -> 强制切 2D 自救
--            （此时 game thread 仍能跑 Lua，所以救得回来）。
--    C 恢复：渲染恢复并稳定 RESTORE_SEC 秒 -> 还原成立体模式。
--
--  回滚方式
--    把本文件改名成 .lua1（UEVR 只加载 .lua 扩展名），下次启动即失效。
--    本脚本不改动任何其它脚本，也不写入 config.txt。
-- ============================================================================

local LOG = "[AC8-GUARD]"

-- ------------------------------------------------------------------ 可调参数
local CFG = {
    STALL_SEC   = 2.5,   -- B：渲染停顿多少秒判定卡死并自救
    RESTORE_SEC = 3.0,   -- C：渲染恢复正常持续多少秒后还原立体
    PREVENT_STALL = 0.5,-- A：换 pawn 时渲染已停滞多少秒才切（避免误伤正常换机）
    PAWN_EVERY  = 20,    -- 每多少帧检查一次 pawn（约 3 次/秒）
    WARMUP      = 30,    -- 前 N 次渲染心跳内不做任何动作（避开启动/加载）
    MAX_RESCUE  = 8,     -- 自救这么多次后不再还原，保持 2D 到底（防抖）
    -- 2026-10-03 14:45 排查结论（仅供参考，不影响下面开关）：
    --   1) 14:42 那次卡死连 game thread 都停了（本脚本 14:41:50 后无输出），
    --      且卡死前最后一刻 停滞=0.0s —— 瞬时死锁，本脚本大概率来不及拦。
    --   2) VR.cpp:7509 起：2D 模式只把 HMD 尺寸换成 rt_size（只降分辨率），
    --      不改渲染路径、不减少 per-eye pass —— 对路径型死锁效果有限。
    --   3) VR.cpp:2635：2D 模式下 is_mono_rendering_active() 返回 false，
    --      若同时把 VR_RenderingMethod 设成 4(MONO)，切 2D 会把它关掉。
    PREVENT     = true,  -- A 开关
    RESCUE      = true,  -- B 开关
    RESTORE     = true,  -- C 开关

    -- 二级降级：切了 2D 画面还在卡，就再切 MONO 单眼渲染（枚举值 4）。
    -- 这是唯一真正绕开 per-eye 双 pass 的办法，但会切换渲染方法，可能触发
    -- swapchain 重建，本身也有风险 —— 所以默认关闭，确认 2D 不够用时再开。
    LEVEL2       = false,
    LEVEL2_AFTER = 5.0,  -- 切 2D 后仍停滞这么久才启用
}

local KEY        = "VR_2DScreenMode"
local METHOD_KEY = "VR_RenderingMethod"
local MONO_VALUE = "4"

-- ------------------------------------------------------------------ 运行时态
local S = {
    beats = 0,     -- 渲染线程心跳计数（render thread 写；只做自增）
    seen  = -1,    -- game thread 上次看到的心跳值
    stall = 0.0,   -- 心跳停滞累计秒
    ok_t  = 0.0,   -- 渲染正常持续秒
    T     = 0.0,   -- 总运行秒（engine delta 累计）
    forced = false,
    prev  = nil,   -- 切入前的原始 2D 模式值
    hb_ok = nil,   -- 渲染心跳是否可用（nil=未定 true=可用 false=回调从不触发）
    since_force = 0.0, -- 心跳不可用时的切入计时
    l2 = false, prev_method = nil, -- 二级降级状态
    pawn  = nil,
    frames = 0,
    rescues = 0,
    last_rescue_t = -999,
    started = false,
}

local TRUE_S, FALSE_S = "true", "false"

-- ------------------------------------------------------------------ 日志工具
local last_log_t = -999
local function log(s)
    print(LOG .. " " .. tostring(s))
end
local function log_throttled(s, gap)
    if S.T - last_log_t < (gap or 5) then return end
    last_log_t = S.T
    log(s)
end

-- ------------------------------------------------------------------ mod value
-- uevr.params.vr.set_mod_value(key, value_string) 直接改内存中的配置项，
-- 不落盘、不需要重启。get_mod_value 返回字符串。
local function mv_get(k)
    local vr = uevr and uevr.params and uevr.params.vr
    if not (vr and vr.get_mod_value) then return nil end
    local ok, v = pcall(function() return vr:get_mod_value(k) end)
    if ok and v ~= nil then return tostring(v) end
    return nil
end

local function mv_set(k, v)
    local vr = uevr and uevr.params and uevr.params.vr
    if not (vr and vr.set_mod_value) then return false end
    local ok = pcall(function() vr:set_mod_value(k, tostring(v)) end)
    return ok
end

-- ------------------------------------------------------------------ 切入/还原
local function enter_2d(reason)
    if S.forced then return end
    local cur = mv_get(KEY)
    if cur == nil then
        log_throttled("!! 读不到 " .. KEY .. "，无法切入 2D 模式")
        return
    end
    S.prev   = cur
    S.forced = true
    S.ok_t   = 0
    S.since_force = 0
    local ok = mv_set(KEY, TRUE_S)
    log(string.format(
        ">> 切 2D 屏幕模式  原因=%s  原值=%s  停滞=%.1fs  写入=%s",
        tostring(reason), tostring(cur), S.stall, tostring(ok)))
end

local function exit_2d(reason)
    if not S.forced then return end
    -- 二级降级用过的先还原，再还原 2D 模式
    if S.l2 then
        mv_set(METHOD_KEY, S.prev_method or "0")
        log("<<< 还原渲染方法 = " .. tostring(S.prev_method))
        S.l2 = false
        S.prev_method = nil
    end
    local ok = mv_set(KEY, S.prev or FALSE_S)
    S.forced = false
    S.ok_t   = 0
    log(string.format("<< 还原立体模式  值=%s  原因=%s  写入=%s",
        tostring(S.prev), tostring(reason), tostring(ok)))
end

-- ------------------------------------------------------------------ pawn 探测
local function pawn_name()
    if not (uevr and uevr.api and uevr.api.get_player_pawn) then return nil end
    local ok, p = pcall(function() return uevr.api:get_player_pawn() end)
    if not ok or p == nil then return nil end
    local ok2, nm = pcall(function() return p:get_full_name() end)
    if not ok2 or type(nm) ~= "string" then return nil end
    return nm
end

-- ============================================================================
--  注册回调
-- ============================================================================
local function setup()
    -- 初始读取，顺便探测 bool 的写法（"true/false" 还是 "1/0"）
    local cur = mv_get(KEY)
    if cur == "1" or cur == "0" then
        TRUE_S, FALSE_S = "1", "0"
    end
    log("启动：当前 " .. KEY .. " = " .. tostring(cur)
        .. "   布尔写法 = " .. TRUE_S .. "/" .. FALSE_S)

    -- ---- 渲染线程心跳（两个时机都挂，任一推进即算活着）----
    local r1, r2 = false, false
    pcall(function()
        uevr.sdk.callbacks.on_post_slate_draw_window_render_thread(function()
            S.beats = S.beats + 1
        end)
        r1 = true
    end)
    pcall(function()
        uevr.sdk.callbacks.on_pre_slate_draw_window_render_thread(function()
            S.beats = S.beats + 1
        end)
        r2 = true
    end)
    log("渲染心跳注册：post_slate=" .. tostring(r1)
        .. "  pre_slate=" .. tostring(r2))

    if not (r1 or r2) then
        log("!! 渲染线程回调注册失败，只剩 pawn 预防可用")
    end

    -- ---- 游戏线程主循环（判定 + 动作都在这里，渲染线程只自增）----
    local ok = pcall(function()
        uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
            local d = tonumber(delta)
            if d == nil or d <= 0 then d = 1 / 60 end
            if d > 1 then d = 1 end          -- 夹住异常大的 delta（加载/断点）
            S.T = S.T + d
            S.frames = S.frames + 1

            -- 心跳比对
            if S.beats ~= S.seen then
                S.seen  = S.beats
                S.stall = 0
            else
                S.stall = S.stall + d
            end

            -- 心跳可用性自检：启动 10 秒后心跳还是 0，说明渲染线程回调在
            -- 这个游戏里压根没被调用，那就不能拿它当判据。
            if S.hb_ok == nil then
                if S.beats > 0 then
                    S.hb_ok = true
                    log("渲染心跳可用")
                elseif S.T > 10 then
                    S.hb_ok = false
                    log("!! 渲染线程回调从未触发，改为仅用换 pawn 判定"
                        .. "（自救兜底关闭）")
                end
            end

            -- 预热：心跳可用时用心跳计数；不可用时退化为运行时间
            local warm = (S.hb_ok == false and S.T > 10)
                      or (S.beats > CFG.WARMUP)

            -- A 预防：过场换相机
            if CFG.PREVENT and S.frames % CFG.PAWN_EVERY == 0 then
                local nm = pawn_name()
                if nm ~= nil then
                    if S.pawn == nil then
                        S.pawn = nm
                    elseif nm ~= S.pawn then
                        S.pawn = nm
                        -- 心跳可用时要求渲染已有轻微停滞（避免误伤正常换机）；
                        -- 心跳不可用时只能见 pawn 变化就切。
                        if warm and (S.hb_ok == false
                                     or S.stall >= CFG.PREVENT_STALL) then
                            enter_2d("过场换 pawn")
                        end
                    end
                end
            end

            -- B 兜底：渲染线程已经不动了（只有心跳可用时才有意义）
            if CFG.RESCUE and (not S.forced) and warm
                and S.hb_ok == true and S.stall >= CFG.STALL_SEC then
                S.rescues = S.rescues + 1
                S.last_rescue_t = S.T
                enter_2d(string.format("渲染停顿 %.1fs（第 %d 次自救）",
                    S.stall, S.rescues))
            end

            -- 二级降级（默认关闭）：切了 2D 还在卡 -> 再切 MONO 单眼渲染
            if CFG.LEVEL2 and S.forced and (not S.l2) and S.hb_ok == true
                and S.stall >= CFG.LEVEL2_AFTER then
                local cur = mv_get(METHOD_KEY)
                if cur ~= nil and cur ~= MONO_VALUE then
                    S.prev_method = cur
                    S.l2 = true
                    mv_set(METHOD_KEY, MONO_VALUE)
                    log(">>> 二级降级：切 MONO 单眼渲染（原方法=" .. tostring(cur) .. "）")
                end
            end

            -- 周期状态（每 10 秒一条，方便事后对照日志）
            log_throttled(string.format(
                "状态 帧=%d 心跳=%d 停滞=%.1fs 2D=%s 自救=%d",
                S.frames, S.beats, S.stall, tostring(S.forced), S.rescues), 10)

            -- C 恢复
            if CFG.RESTORE and S.forced then
                if S.rescues >= CFG.MAX_RESCUE then
                    -- 反复卡死，不再还原，保持 2D 到本次会话结束
                    if S.rescues == CFG.MAX_RESCUE then
                        log("!! 自救已达上限 " .. CFG.MAX_RESCUE
                            .. " 次，保持 2D 模式不再还原")
                        S.rescues = S.rescues + 1  -- 只提示一次
                    end
                elseif S.hb_ok == false then
                    -- 没有心跳可依据，切入后固定 2 秒还原
                    S.since_force = S.since_force + d
                    if S.since_force >= 2.0 then
                        exit_2d("换 pawn 后已过 2s")
                    end
                elseif S.stall == 0 then
                    S.ok_t = S.ok_t + d
                    -- 刚救回来不久就再放宽一点，避免 2D/立体来回抖
                    local need = CFG.RESTORE_SEC
                    if S.T - S.last_rescue_t < 15 then need = need * 3 end
                    if S.ok_t >= need then exit_2d("渲染已恢复") end
                else
                    S.ok_t = 0
                end
            end
        end)
    end)
    log("引擎 tick 注册 = " .. tostring(ok))

    S.started = true
end

-- 脚本加载时 uevr.params / callbacks 已就绪（与 fps_stat_v1 同一模式），
-- 直接初始化；任何一步失败都只影响本脚本，不影响游戏和其它脚本。
local ok, err = pcall(setup)
if not ok then
    print(LOG .. " !! 初始化失败: " .. tostring(err))
end
