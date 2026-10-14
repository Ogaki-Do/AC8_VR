--[[
  AC8 HUD 自定义  ——  改位置 / 大小 / 透明度，可保存

  当前支持：
    PitchLadder   俯仰梯 + 速度矢量标       容器 Altimeter / Velocity  实测 (-1150, 116)
    Radar         雷达 + 小地图整棵子树    容器 MiniMapLayer 等
    AircraftInfo  机体信息                 容器 WBP_PlayerStateWidget 等
    Draw canvas   HUD 的分层画布           MainCanvas / DynamicDrawCanvas 等

  每组的控件：
    opacity              透明度
    scale                缩放
    X / Y                位置（Draw canvas 那组没有，见 nopos）
    Heading X / Y        速度矢量标相对俯仰梯的额外偏移（只有 PitchLadder 组有）
                         出厂值实测 = (-1913, -1200）

    每个位置滑条下面还有 [-1] [+1] 两个按钮：
    滑条量程 ±4000 而实际值在千位，拖一格跳几十、对不准 ——
    粗调拖滑条，收尾用按钮一步步挪。
    Load saved <组名>    把这一组拉回**上次保存**的状态（撤销进来之后的乱调）
    Reset ALL to base    所有组拉回**出厂值**并写盘（和上面那个互为正反）

  【没有"启用"开关】
    拖任意一个滑条，这一组就生效；要撤销按组末尾的 Restore。
    早先有个 ON/OFF 勾选框，但它和"拖滑条自动启用"互相打架 ——
    拖完滑条后它已经是 ON，再点一下就是关掉，所有改动瞬间还原，
    看起来就是"开关是反的 / 怎么调都不生效"。去掉这个状态就没有搞反的可能。

  【为什么必须用 SetRenderXxx 这些函数】
    UPROPERTY 直写不会推送到 Slate 侧：内存里值变了、画面纹丝不动。
    必须调 UFUNCTION（SetRenderTranslation / SetRenderScale /
    SetRenderOpacity），它才会让控件正确失效重绘。

  【怎么定位目标节点】
    按名字全局搜，不是沿父链往上走。
    容器不一定是 UCanvasPanel —— MiniMapLayer 这类就是 UUserWidget，
    只搜 CanvasPanel 会漏掉它们（漏掉父层 → 只动子节点 → 移动比例不一致）。
    因此搜索同时覆盖 CanvasPanel 和 UserWidget 两类（见 SEARCH_CLASSES），
    并用 SCOPE 限定在飞行 HUD 底下，避免抓到暂停菜单里的同名副本。

  【界面上为什么全是英文】
    UEVR 的 ImGui 字体不含中文字形，写中文只会显示成一串 '?'。
    日志文件不受影响，那边照旧写中文。

  用法：Insert → LuaLoader → ac8_ladder_fix.lua
  日志：data\ac8_ladder_fix.txt     配置：data\ac8_ladder.json
--]]

local api = uevr.api
if api == nil then return end

-- 版本号。日志第一行和界面上都会打印 ——
-- 改完脚本游戏往往还开着，UEVR 不会自动重载，对不上就是该 Reset scripts 了。
local SCRIPT_VERSION = "v19"

--------------------------------------------------------------------------
-- 目标定义
--
-- 每个组都要写全 x / y / op / sc / active ——
-- 少写一个，apply 里就会拿 nil 去做算术，异常会把**后面所有组**一起拖垮，
-- 而日志里一点痕迹都没有（实测踩过：v2 漏了 x/y，结果只有排第一的组能用）。
--------------------------------------------------------------------------
local TARGETS = {
    {
        key    = "ladder",
        label  = "PitchLadder",
        from   = { "PitchMeter" },         -- 名字搜不到时，从这个类的实例沿父链往上找
        nodes  = {
            "Altimeter",      -- 中央仪表簇：俯仰梯 + 速度表 + 高度表 + 加力表
            -- ★ 速度矢量标（滑移标）。它和俯仰梯本来是一套：俯仰梯显示机头指向，
            --   速度矢量标显示实际运动方向，两者的差值就是滑移角 —— 必须一起动，
            --   否则俯仰梯挪走了、它留在原地，两个符号就对不上了。
            --
            --   ★ LaoFan 脚本也在钉这两个节点（VELOCITY_X/Y、VICON_BASE）。两边都是
            --   写 RenderTranslation，会互相覆盖 —— 我们是每帧写（带读回 guard），
            --   它走慢车道（约每 600 帧一次），所以实际是我们说了算。
            --   **不需要改 LaoFan 的脚本**：下面给这几个节点单独留了一组微调滑条，
            --   在组的 X/Y 之上叠加，自己这边就能把它们对齐。
            --
            --   RenderTranslation 是**相对偏移**不是绝对坐标，所以给同一个值
            --   就会保持原来的相对关系、一起挪。
            "Velocity",
            "VelocityIcon",
        },
        -- 子偏移：只作用于下面列出的节点，叠加在组的 x/y 之上。
        -- 用途：速度矢量标（滑移标）虽然要和俯仰梯一起动，但两者的设计基准
        --      不一定重合，需要一个能单独微调的量。
        subnames = { "Velocity", "VelocityIcon" },
        sublabel = "Heading",
        x = 690.0, y = 756.0, active = true,  op = 1.0, sc = 1.0,
        -- 速度矢量标的实测对齐值（叠加在组的 x/y 之上）
        sdx = -1913.0, sdy = -1200.0,
    },
    {
        -- 雷达不是单个面板，是圆盘 / 底盘 / 小地图图标 / 边角 各一块拼出来的，
        -- 必须整组一起动，否则只挪走一部分。
        key    = "radar",
        label  = "Radar",
        from   = { "MiniMap", "Radar" },
        nodes  = {
            -- ★ MiniMapLayer 是这一组的关键：它是 UUserWidget（不是 CanvasPanel），
            --   整棵小地图子树都挂在它下面。只动子节点、不动它，就会
            --   「小地图自己的边框/底图不动，图标层全跑了」= 比例不一致。
            --   prune_nested 会把它的后代自动剔掉，所以列上它 + 子节点名是安全的。
            "MiniMapLayer",
            "MIniMapCanvas",
            "RadarCircleCanvasPanel",     -- 雷达圆盘（条件生成，不一定在场）
            "RadarCircleBase",            -- 盘底（同上）
            "MiniMapIconCanvasPanel",
            "MiniMapCornerCanvas",
            "MiniMapSearchCorners",
            "MiniMapEnlargedCorners",
        },
        x = 0.0, y = 0.0, active = false, op = 1.0, sc = 1.0,
    },
    {
        -- 机体信息同样是多块：状态面板 + 飞机图标/名字 + 速度表 + 高度表 + 加力 + 武器
        key    = "info",
        label  = "AircraftInfo",
        from   = { "PlayerState", "PlayerStatus" },
        nodes  = {
            -- ★ Altimeter 不是「俯仰梯的容器」，而是中央仪表簇的总容器，
            --   里面同时装着俯仰梯、速度表、高度表、加力表。那几块归 PitchLadder
            --   那组管 —— 这一组再列它们就会两个目标抢同一批控件，位移叠加。
            --
            --   HUDMessageWidget 试过、已撤掉：它是消息系统的父控件，太宽泛 ——
            --   连角色头像和名字一起拖走了。
            "WBP_PlayerStateWidget",      -- 机体图标 / 机体文字的父控件
            "PlaneIconStatPanel",         -- 机体图标
            "PlaneCanvas",
            "PlaneTextStatPanel",         -- 机体文字
            "PlayerNamePanel",
            "Weapons",                    -- 武器
            "WeaponsADMM",
            "Flares",
            "IconsCanvas",
        },
        x = 0.0, y = 0.0, active = false, op = 1.0, sc = 1.0,
    },
    {
        -- HUD 按优先级切成的几块画布，名字里直接写着 WorldToScreen。
        -- 其中 LowestPriorityDynamicDrawCanvas 尺寸 6867x3699，比 4K 还大一圈。
        --
        -- nopos = 不带位置：它们是整层画布，挪走等于把整个 HUD 挪走，用不上。
        key    = "drawcanvas",
        label  = "Draw canvas",
        from   = { "WorldToScreen", "DynamicDraw" },
        nodes  = {
            "LowestPriorityDynamicDrawCanvas",
            "LowestPriorityCanvasWorldToScreenDraw",
            "WorldToScreenDrawCanvas",
            "TopPriorityCanvas",
            "MainCanvas",
            "DynamicDrawCanvas",
        },
        nopos = true,
        x = 0.0, y = 0.0, active = false, op = 1.0, sc = 1.0,
    },
}

-- 作用域：只认飞行 HUD 底下的容器。
-- 暂停菜单里有一份同名的雷达/仪表副本（挂在 WBP_Menu_PauseTop_000_C 下），
-- 按名字全局搜会连它们一起抓走 —— 实测 11 个雷达容器里有 5 个是菜单里的。
local SCOPE = "WBP_HUD_Chronicle_MainFlight_000_C"

-- 出厂值快照。
-- 必须在任何 load_cfg() 之前拍下来 —— 拍晚了读到的就是配置文件里的值，
-- 那样「重置」等于什么都没做。
local DEFAULTS = {}
for _, t in ipairs(TARGETS) do
    DEFAULTS[t.key] = { x = t.x, y = t.y, active = t.active, op = t.op, sc = t.sc,
                        sdx = t.sdx or 0.0, sdy = t.sdy or 0.0 }
end

-- 定期重解析的间隔（tick）。600 ≈ 10 秒。
-- 调小 = 换关卡后恢复更快，但全量枚举的卡顿更频繁。
local RESCAN_EVERY = 1800

local CFG_FILE = "ac8_ladder.json"
local dirty, save_msg = false, ""

--------------------------------------------------------------------------
-- 日志 / 工具
--------------------------------------------------------------------------
local FH = nil
do
    local ok, f = pcall(function() return io.open("ac8_ladder_fix.txt", "w") end)
    if ok and f ~= nil then FH = f end
end
local function log(s)
    if FH == nil then return end
    pcall(function() FH:write(s); FH:write("\n"); FH:flush() end)
end

log("=== ac8_ladder_fix " .. SCRIPT_VERSION .. " ===")

-- 调 UFUNCTION 的兜底：有的绑定挂在对象上，有的只能走 obj.call(obj, "名字", ...)
local function call(obj, fn, ...)
    local ok, f = pcall(function() return obj[fn] end)
    if ok and f ~= nil then
        local ok2, r = pcall(f, obj, ...)
        if ok2 then return r end
    end
    local ok3, f2 = pcall(function() return obj.call end)
    if ok3 and f2 ~= nil then
        local ok4, r2 = pcall(f2, obj, fn, ...)
        if ok4 then return r2 end
    end
    return nil
end

local function full_name(o)
    local ok, s = pcall(function() return o:get_full_name() end)
    if ok and type(s) == "string" then return s end
    return nil
end

local function leaf(o)
    local s = full_name(o)
    if s ~= nil then return s:match("([^.]+)$") or s end
    return "?"
end

-- 取出对象路径（去掉全名开头的类名前缀：全名形如 "CanvasPanel /Engine/..."）
local function path_of(o)
    local s = full_name(o)
    if s == nil then return nil end
    return s:match("^%S+%s+(.*)$") or s
end

-- 结构体字段读取。
-- Y 分量在 LuaVR 的绑定里用 tr.Y 读不出来（实测恒为 nil），两种大小写都试。
-- 只影响读回判断，不影响写入。
local function num_field(o, names)
    for _, n in ipairs(names) do
        local ok, v = pcall(function() return o[n] end)
        if ok and type(v) == "number" then return v end
    end
    return nil
end

local function get_rt_xy(obj)
    local ok1, rt = pcall(function() return obj:get_property("RenderTransform") end)
    if not ok1 or rt == nil then return nil, nil end
    local ok2, tr = pcall(function() return rt.Translation end)
    if not ok2 or tr == nil then return nil, nil end
    return num_field(tr, { "X", "x" }), num_field(tr, { "Y", "y" })
end

local function get_rt_scale(obj)
    local ok1, rt = pcall(function() return obj:get_property("RenderTransform") end)
    if not ok1 or rt == nil then return nil, nil end
    local ok2, sc = pcall(function() return rt.Scale end)
    if not ok2 or sc == nil then return nil, nil end
    return num_field(sc, { "X", "x" }), num_field(sc, { "Y", "y" })
end

--------------------------------------------------------------------------
-- 目标节点解析
--
-- 只从「运行时实例」出发：蓝图模板里也有同名节点，值恰好是设计值，
-- 认错了等于没认。判据是路径里带 /Engine/Transient。
-- 祖先名用「完全相等」比较，子串匹配会命中父层（AltimeterPanel 之于 Altimeter）。
--------------------------------------------------------------------------
-- ★ 要搜的不止 CanvasPanel。
--   很多容器是 UUserWidget（比如 MiniMapLayer 就是 WBP_HUD_Radar_..._C），
--   只枚举 CanvasPanel 会漏掉它们 —— 结果就是「只动了子节点、父层没动」，
--   表现正是同一组元素移动比例不一致。
local SEARCH_CLASSES = {}
local UW = nil
do
    for _, path in ipairs({ "Class /Script/UMG.UserWidget",
                            "Class /Script/UMG.CanvasPanel" }) do
        local ok, c = pcall(function() return api:find_uobject(path) end)
        if ok and c ~= nil then
            SEARCH_CLASSES[#SEARCH_CLASSES + 1] = c
            if path:find("UserWidget", 1, true) then UW = c end
        end
    end
end
if #SEARCH_CLASSES == 0 then
    log("!! 一个搜索用的类都拿不到（find_uobject 失败），所有目标都会是 not found")
end

-- 按名字全局搜。名字可能带唯一后缀（CanvasPanel_63），所以后缀剥掉再比一次。
-- 返回所有命中的容器（不是只返回第一个）——
-- 雷达、机体信息都是多块面板拼的，必须整组一起动。
local function find_all_by_name(node_names)
    local out = {}
    local want = {}
    for _, n in ipairs(node_names) do want[n] = true end

    -- 按「全名」去重，不能按叶名 —— 同名面板可能有多个实例，
    -- 按叶名去重只会留下第一个，可能根本不是要动的那个。
    local seen = {}
    for _, cls in ipairs(SEARCH_CLASSES) do
        local ok, arr = pcall(function() return cls:get_objects_matching(false) end)
        if ok and type(arr) == "table" then
            for _, w in ipairs(arr) do
                local okn, nm = pcall(function() return w:get_full_name() end)
                if okn and type(nm) == "string"
                    and nm:find("/Engine/Transient", 1, true)
                    and nm:find(SCOPE, 1, true)      -- 排除暂停菜单里的同名副本
                then
                    local l = nm:match("([^.]+)$") or ""
                    -- 结尾的 _数字 要「反复剥」：WBP_HUD_Command_Wingman_Parts_003_01
                    -- 只剥一次会留下 _Parts_003，跟名单里的基名对不上。
                    local base = l
                    repeat
                        local prev = base
                        base = base:gsub("_%d+$", "")
                        if base == prev then break end
                    until false
                    if (want[l] or want[base]) and not seen[nm] then
                        seen[nm] = true
                        out[#out + 1] = w
                    end
                end
            end
        end
    end
    return out
end

-- ★ 去掉同组里被其它容器包含的那些。
--   容器是嵌套的：同时给外层和内层写同一个位移，里面的元素会走两份
--   （外层一份 + 内层一份），表现就是「不同元素移动比例不同」。
--
-- ★ 用「路径前缀」判断包含，不要用 GetParent()。
--   实测教训：GetParent() 在嵌套 UUserWidget 的边界上会断链 ——
--   从 MiniMapIconCanvasPanel 往上爬，爬不到 MiniMapLayer / MIniMapCanvas，
--   于是判定「不嵌套」放行。结果这些图标层被移动了两次。
--   而 UMG 里子控件的 Outer 就是所属的 WidgetTree，路径前缀天然反映包含关系。
local function is_under(child_path, parent_path)
    if child_path == nil or parent_path == nil then return false end
    if #parent_path >= #child_path then return false end
    return child_path:sub(1, #parent_path) == parent_path
end

local function prune_nested(list)
    if #list < 2 then return list end
    local paths = {}
    for i, o in ipairs(list) do paths[i] = path_of(o) end

    local keep = {}
    for i, o in ipairs(list) do
        local p, nested = paths[i], false
        if p ~= nil then
            for j = 1, #paths do
                if j ~= i and is_under(p, paths[j]) then nested = true; break end
            end
        end
        if not nested then keep[#keep + 1] = o end
    end
    return keep
end

-- 兜底：从子控件沿父链往上找（名字搜不到时才用）
local function find_by_walk(from_patterns, node_names)
    if UW == nil then return nil, {} end
    local ok, arr = pcall(function() return UW:get_objects_matching(false) end)
    if not ok or type(arr) ~= "table" then return nil, {} end

    local want_node = {}
    for _, n in ipairs(node_names) do want_node[n] = true end

    for _, w in ipairs(arr) do
        local okn, nm = pcall(function() return w:get_full_name() end)
        if okn and type(nm) == "string" and nm:find("/Engine/Transient", 1, true) then
            local hit_from = false
            for _, p in ipairs(from_patterns) do
                if nm:find(p, 1, true) then hit_from = true; break end
            end
            if hit_from then
                local chain, cur = {}, w
                for _ = 1, 12 do
                    cur = call(cur, "GetParent")
                    if cur == nil then break end
                    local l = leaf(cur)
                    chain[#chain + 1] = l
                    if want_node[l] then return cur, chain end
                end
                return nil, chain
            end
        end
    end
    return nil, {}
end

-- 解析之后做一次预处理：把每个容器的「键」和「是否属于子偏移节点」算好存下来。
-- 这两样每帧都要用，但它们都依赖 get_full_name()（跨绑定调用 + 字符串分配），
-- 现算的话每帧几十次，纯属白烧 CPU 和 GC。
local function prepare_items(t)
    t.items = nil
    if t.objs == nil then return end
    local out = {}
    for i, o in ipairs(t.objs) do
        local l = leaf(o)
        local base = l:gsub("_%d+$", "")
        local issub = false
        if t.subnames ~= nil then
            for _, nm in ipairs(t.subnames) do
                if l == nm or base == nm then issub = true; break end
            end
        end
        out[i] = { o = o, k = path_of(o) or l, fn = full_name(o), sub = issub }
    end
    t.items = out
    -- ★ 换了新一批对象，写入 guard 必须作废。
    --   否则 opApplied/scApplied 还是旧值 → 判定成"没变过" → 透明度/缩放
    --   根本不会写到新控件上（位置不受影响，它走的是逐对象的读回判断）。
    --   实测症状：重进关卡后控件找回来了、位置也回去了，但大小/透明度没恢复。
    t.opApplied, t.scApplied = nil, nil
end

local function find_node(from_patterns, node_names)
    local list = find_all_by_name(node_names)
    if #list == 0 then
        -- 名字一个都没搜到，才退回沿父链往上找（只可能找到一个）
        local w = find_by_walk(from_patterns, node_names)
        list = (w ~= nil) and { w } or {}
    end
    return prune_nested(list)
end

--------------------------------------------------------------------------
-- 原值快照
--------------------------------------------------------------------------
-- 每个控件「被我们动过之前」的原值，按完整路径存。
-- 用字符串做键、不用对象句柄：句柄跨帧能不能当表键用没有保证，路径是稳的。
local ORIG = {}

local function key_of(o)
    return path_of(o) or leaf(o)
end

-- remember / restore 收的是「预处理项」e = { o = 控件, k = 键, sub = 是否子偏移节点 }。
-- 为什么不在函数里现算键：path_of 要走 get_full_name()，
-- 那是跨绑定调用、还会分配一个字符串。每帧对每个容器来一遍纯属浪费 ——
-- 键在解析的时候算一次就够了（见 prepare_items）。
local function remember(e)
    local r = ORIG[e.k]
    if r == nil then
        local ox, oy = get_rt_xy(e.o)
        local sx, sy = get_rt_scale(e.o)
        ORIG[e.k] = { x = ox, y = oy, sx = sx, sy = sy }
    end
end

-- 完整还原（位移 + 缩放 + 透明度）。
-- 每项都带差异判断，否则这一组关着的时候每帧都要写一遍、每帧都让控件失效重绘。
local function restore(e)
    local r = ORIG[e.k]
    if r == nil then return end
    local o = e.o

    local cx, cy = get_rt_xy(o)
    if type(r.x) == "number" and type(r.y) == "number"
        and not (type(cx) == "number" and math.abs(cx - r.x) < 1
                 and type(cy) == "number" and math.abs(cy - r.y) < 1) then
        pcall(function() o:SetRenderTranslation({ X = r.x, Y = r.y }) end)
    end

    local sx, sy = get_rt_scale(o)
    if type(r.sx) == "number" and type(r.sy) == "number"
        and not (type(sx) == "number" and math.abs(sx - r.sx) < 0.01
                 and type(sy) == "number" and math.abs(sy - r.sy) < 0.01) then
        pcall(function() o:SetRenderScale({ X = r.sx, Y = r.sy }) end)
    end

    local ok, cur = pcall(function() return o:GetRenderOpacity() end)
    if ok and type(cur) == "number" and math.abs(cur - 1.0) > 0.01 then
        pcall(function() o:SetRenderOpacity(1.0) end)
    end
end

--------------------------------------------------------------------------
-- 应用
--------------------------------------------------------------------------
-- 单组应用。拆出来是为了能**单独 pcall** ——
-- 之前是一整个大循环，任何一组里出个错（比如某个字段是 nil 导致算术失败），
-- apply 就整体中断，**排在它后面的组全部静默失效**，日志里还一点痕迹都没有。
-- 实测就是那样坏的：PitchLadder 排第一位移正常，Radar 抛错，
-- AircraftInfo / Draw canvas 一行都没跑到。
local function apply_one(t)
    if t.items == nil then return end

    if not t.active then
        -- ★ 只有在「之前确实改过」的时候才还原。
        --   这一条是省开销的关键：没动过的组（比如一直没启用的 Radar / Draw canvas）
        --   原本每帧都会对每个容器跑一遍 restore —— 里面要查 ORIG、
        --   读 RenderTransform、读缩放、读透明度，全是跨绑定调用。
        --   4 个组加起来 13 个容器 × 每帧 2 次回调 = 每秒几千次无谓调用。
        --   现在没改过就一个调用都不发。
        if t.applied then
            for _, e in ipairs(t.items) do restore(e) end
            t.applied = false
        end
        -- 清掉写入 guard，下次生效时重新写一遍
        t.opApplied, t.scApplied = nil, nil
        return
    end

    local op_dirty = (type(t.op) == "number" and t.op ~= t.opApplied)
    local sc_dirty = (type(t.sc) == "number" and t.sc ~= t.scApplied)

    for _, e in ipairs(t.items) do
        local o = e.o
        remember(e)               -- 记下原值，之后才能还原

        -- 位置（nopos 的组跳过）
        if not t.nopos then
            -- 子偏移：解析时已经判好 e.sub，这里不再算名字
            local ox, oy = 0.0, 0.0
            if e.sub then ox, oy = t.sdx or 0.0, t.sdy or 0.0 end
            local tx, ty = t.x + ox, t.y + oy

            local cx, cy = get_rt_xy(o)
            -- 读回 guard：已经是目标值就跳过，省掉无意义的失效重绘
            if not (type(cx) == "number" and math.abs(cx - tx) < 1
                    and type(cy) == "number" and math.abs(cy - ty) < 1) then
                pcall(function() o:SetRenderTranslation({ X = tx, Y = ty }) end)
            end
        end

        -- 透明度 / 缩放：只在值变过时写
        if op_dirty then
            pcall(function() o:SetRenderOpacity(t.op) end)
        end
        if sc_dirty then
            pcall(function() o:SetRenderScale({ X = t.sc, Y = t.sc }) end)
        end
    end

    if op_dirty then t.opApplied = t.op end
    if sc_dirty then t.scApplied = t.sc end
    t.applied = true     -- 记下「这一组我们动过」，关掉时才需要还原
end

local function apply()
    for _, t in ipairs(TARGETS) do
        local ok, err = pcall(apply_one, t)
        if not ok then
            log(string.format("!! [%s] apply 出错，这一组没生效: %s",
                t.label, tostring(err)))
        end
    end
end

--------------------------------------------------------------------------
-- 配置存取
--------------------------------------------------------------------------
local HAS_JSON = false
pcall(function() HAS_JSON = (json ~= nil and json.dump_file ~= nil) end)

local function cfg_by_key(k)
    for _, t in ipairs(TARGETS) do
        if t.key == k then return t end
    end
    return nil
end

local function save_cfg()
    if not HAS_JSON then return false, "no json api" end
    local out = {}
    for _, t in ipairs(TARGETS) do
        out[t.key] = { x = t.x, y = t.y, active = t.active, op = t.op, sc = t.sc,
                       sdx = t.sdx or 0.0, sdy = t.sdy or 0.0 }
    end
    local ok = pcall(function() json.dump_file(CFG_FILE, out, 4) end)
    return ok, ok and "saved" or "save FAILED"
end

-- 把配置里的一组值套到目标上。返回是否有改动。
local function apply_cfg_entry(tg, v)
    if type(v) ~= "table" then return false end
    if type(v.x) == "number" then tg.x = v.x end
    if type(v.y) == "number" then tg.y = v.y end
    if type(v.active) == "boolean" then tg.active = v.active end
    if type(v.op) == "number" then tg.op = v.op end
    if type(v.sc) == "number" then tg.sc = v.sc end
    if type(v.sdx) == "number" then tg.sdx = v.sdx end
    if type(v.sdy) == "number" then tg.sdy = v.sdy end
    tg.opApplied, tg.scApplied = nil, nil
    return true
end

local function read_cfg()
    if not HAS_JSON then return nil end
    local ok, t = pcall(function() return json.load_file(CFG_FILE) end)
    if not ok or type(t) ~= "table" then return nil end
    return t
end

local function load_cfg()
    local t = read_cfg()
    if t == nil then return false end
    local n = 0
    for k, v in pairs(t) do
        local tg = cfg_by_key(k)
        if tg ~= nil and apply_cfg_entry(tg, v) then n = n + 1 end
    end
    return n > 0
end

-- 「从 save 中还原」用：只还原某一组，值取自上次保存的配置文件。
local function load_cfg_one(tg)
    local all = read_cfg()
    if all == nil then return false end
    local v = all[tg.key]
    if v == nil then return false end
    return apply_cfg_entry(tg, v)
end

local function resolve_all(verbose)
    for _, t in ipairs(TARGETS) do
        if t.objs == nil or verbose then
            t.objs = find_node(t.from, t.nodes)
            prepare_items(t)
            if verbose then
                if #t.objs > 0 then
                    log(string.format("  [%s] 命中 %d 个容器：", t.label, #t.objs))
                    for i, o in ipairs(t.objs) do
                        log(string.format("      %d) %s", i, leaf(o)))
                    end
                else
                    local _, chain = find_by_walk(t.from, t.nodes)
                    log(string.format("  [%s] !! 一个都没命中，走过的链：%s",
                        t.label, table.concat(chain, " < ")))
                end
            end
        end
    end
end

-- 定期重解析。只有「和上次抓到的不是同一批对象」时才记日志 ——
-- 正常情况下它什么都不做，只是确认一下；换了关卡才会真的换一批句柄。
local function rescan_all()
    local changed = {}
    for _, t in ipairs(TARGETS) do
        local before = t.items and t.items[1] and t.items[1].k or nil
        t.objs = find_node(t.from, t.nodes)
        prepare_items(t)
        local after = t.items and t.items[1] and t.items[1].k or nil
        if after ~= before then
            changed[#changed + 1] = string.format("%s(%d)", t.label,
                t.objs ~= nil and #t.objs or 0)
        end
    end
    if #changed > 0 then
        log("重解析，目标有变化: " .. table.concat(changed, "  "))
    end
end

-- v19-fast：轮转重解析——每 RESCAN_EVERY 帧只重解析一组目标。
-- 原版每 10 秒把 5 组连发全部枚举（扫全量 UObject）= 用户实测"时不时小卡一下"
-- 的主嫌；轮转后开销降为 1/5，5 组全过一遍也只要 5 × 30 秒。rescan_all 保留给
-- Reload targets 按钮用（一键全量，行为不变）。
local rescan_idx = 1
local function rescan_one()
    local n = #TARGETS
    if n == 0 then return end
    local t = TARGETS[rescan_idx]
    rescan_idx = rescan_idx % n + 1
    local before = t.items and t.items[1] and t.items[1].k or nil
    t.objs = find_node(t.from, t.nodes)
    prepare_items(t)
    local after = t.items and t.items[1] and t.items[1].k or nil
    if after ~= before then
        log(string.format("重解析，目标有变化: %s(%d)", t.label,
            t.objs ~= nil and #t.objs or 0))
    end
end

--------------------------------------------------------------------------
-- 界面（全 ASCII）
--------------------------------------------------------------------------
local HAS_BUTTON = false
pcall(function() HAS_BUTTON = (imgui ~= nil and imgui.button ~= nil) end)

-- same_line 不一定有这个绑定，没有就退化成竖排（多几行而已）
local HAS_SAME_LINE = false
pcall(function() HAS_SAME_LINE = (imgui ~= nil and imgui.same_line ~= nil) end)

-- ±1 微调。
-- 为什么需要：位置类的滑条量程都是 ±4000，可实际要调的值就在千位上下 ——
-- 拖一格就跳几十，根本对不准。按钮一步步挪才实用。
-- 拖动滑条仍是粗调，对不准就用这个收尾。
local function nudge_row(t, field, label)
    local ok1, c1 = pcall(function() return imgui.button(label .. " -1") end)
    if ok1 and c1 then
        t[field] = (t[field] or 0.0) - 1.0
        t.active = true; dirty = true
    end
    if HAS_SAME_LINE then pcall(function() imgui.same_line() end) end
    local ok2, c2 = pcall(function() return imgui.button(label .. " +1") end)
    if ok2 and c2 then
        t[field] = (t[field] or 0.0) + 1.0
        t.active = true; dirty = true
    end
end

local function ui_body()
    imgui.text("AC8 HUD tune   " .. SCRIPT_VERSION)

    for _, t in ipairs(TARGETS) do
        -- 标签上标出可见性：vis=1 是 Collapsed —— 控件根本没在画，
        -- 这时候怎么改属性画面上都不会有变化，标出来省得白试。
        local vtag = ""
        if t.objs ~= nil and t.objs[1] ~= nil then
            local okv, vv = pcall(function() return t.objs[1]:GetVisibility() end)
            if okv and type(vv) == "number" then
                if vv == 1 then vtag = "  [HIDDEN]"
                elseif vv == 2 then vtag = "  [HIDDEN vis=2]"
                else vtag = "  [vis=" .. vv .. "]" end
            end
        end
        imgui.text("  " .. t.label .. vtag
            .. (t.active and "   [modified]" or "")
            .. ((t.objs and #t.objs > 0) and "" or "   (not found)"))

        if t.objs ~= nil and #t.objs > 0 then
            -- 透明度：既能当开关用，也方便辨认是哪块内容
            local c3, v3 = imgui.slider_float(t.label .. " opacity", t.op or 1.0, 0.0, 1.0)
            if c3 then t.op = v3; t.active = true; dirty = true end

            local c4, v4 = imgui.slider_float(t.label .. " scale", t.sc or 1.0, 0.1, 4.0)
            if c4 then t.sc = v4; t.active = true; dirty = true end

            if not t.nopos then
                local c1, v1 = imgui.slider_float(t.label .. " X", t.x, -4000.0, 4000.0)
                if c1 then t.x = v1; t.active = true; dirty = true end
                local c2, v2 = imgui.slider_float(t.label .. " Y", t.y, -4000.0, 4000.0)
                if c2 then t.y = v2; t.active = true; dirty = true end
                nudge_row(t, "x", t.label .. " X")
                nudge_row(t, "y", t.label .. " Y")
            end

            -- 子偏移滑条（只有配了 subnames 的组才有）
            if t.subnames ~= nil then
                local subX = t.label .. " " .. (t.sublabel or "sub") .. " X"
                local subY = t.label .. " " .. (t.sublabel or "sub") .. " Y"
                local cs1, vs1 = imgui.slider_float(subX, t.sdx or 0.0, -4000.0, 4000.0)
                if cs1 then t.sdx = vs1; t.active = true; dirty = true end
                nudge_row(t, "sdx", subX)

                local cs2, vs2 = imgui.slider_float(subY, t.sdy or 0.0, -4000.0, 4000.0)
                if cs2 then t.sdy = vs2; t.active = true; dirty = true end
                nudge_row(t, "sdy", subY)
            end

            -- 「从 save 中还原」：把这一组拉回**上次保存**的状态，
            -- 用于撤销这次进来之后的乱调。
            -- （不要和下面那个「Reset ALL to base」搞混：
            --   那个是把所有组拉回**出厂值**，跟存档无关。）
            local okr, clicked = pcall(function()
                return imgui.button("Load saved  " .. t.label)
            end)
            if okr and clicked then
                if load_cfg_one(t) then
                    dirty = false
                    log(string.format("[%s] 从存档还原", t.label))
                else
                    log(string.format("[%s] 没有可还原的存档", t.label))
                end
            end
        end
    end

    -- 保存
    local okb, saved = pcall(function() return imgui.button("Save") end)
    if okb and saved then
        local ok, msg = save_cfg()
        save_msg = (ok and "[OK] " or "[FAIL] ") .. msg
        if ok then dirty = false end
        log("保存 " .. tostring(ok) .. " " .. msg)
    end

    -- 「Reset ALL to base」：所有组回到**出厂值**（位置=出厂坐标、
    -- 透明度/缩放=1、速度矢量标偏移=出厂值），并立即写盘。
    -- 和上面的「Load saved」互为正反：一个回出厂，一个回存档。
    local okrs, reset = pcall(function() return imgui.button("Reset ALL to base") end)
    if okrs and reset then
        for _, t in ipairs(TARGETS) do
            local d = DEFAULTS[t.key]
            if d ~= nil then
                t.x, t.y, t.active, t.op, t.sc = d.x, d.y, d.active, d.op, d.sc
                t.sdx, t.sdy = d.sdx, d.sdy
                t.opApplied, t.scApplied = nil, nil
            end
        end
        local ok = save_cfg()
        save_msg = ok and "[RESET] all back to base" or "[RESET] save FAILED"
        if ok then dirty = false end
        log("重置为出厂值 " .. tostring(ok))
    end

    -- 手动重载：回归主菜单 / 换任务之后，缓存的目标可能已经不在了。
    -- 自动检查每 10 秒跑一次，这个是保险 —— 一键立刻重新抓一遍。
    local okrl, reload = pcall(function()
        return imgui.button("Reload targets (after menu / mission change)")
    end)
    if okrl and reload then
        for _, t in ipairs(TARGETS) do
            t.objs, t.items = nil, nil
            t.applied = false
        end
        resolve_all(true)
        log("手动重载目标")
    end

    imgui.text(dirty and "UNSAVED CHANGES" or "saved")
    if save_msg ~= "" then imgui.text(save_msg) end
end

-- 界面整体再包一层 pcall。
-- 里面任何一句出错（某个绑定不存在、某个字段是 nil），都会让整块界面画不出来，
-- 而且 UEVR 只会把它吞掉 —— 表现就是"菜单里什么都没有"，完全查不出原因。
-- 出错时记一次日志，不刷屏。
local ui_err_logged = false
local function ui_safe()
    local ok, err = pcall(ui_body)
    if not ok and not ui_err_logged then
        ui_err_logged = true
        log("!! 界面出错，可能整块画不出来: " .. tostring(err))
    end
end

local ui_ok = pcall(function() uevr.sdk.callbacks.on_draw_ui(ui_safe) end)
log("on_draw_ui 注册 = " .. tostring(ui_ok)
    .. "   button = " .. tostring(HAS_BUTTON)
    .. "   json = " .. tostring(HAS_JSON))

--------------------------------------------------------------------------
-- 启动
--------------------------------------------------------------------------
log("=== 配置 ===")
log("  读取配置 = " .. tostring(load_cfg()))

log("=== 目标容器解析 ===")
resolve_all(true)

--------------------------------------------------------------------------
-- 每帧写回
--------------------------------------------------------------------------
-- ★ 两个时机都要写。
--   on_post_engine_tick 在引擎 tick 之后；如果游戏是在 Slate 的准备阶段才
--   把位置/大小算出来，那我们的写入会被盖掉。pre_slate 那个回调在绘制
--   窗口之前触发，是最后一手。两处都有读回 guard，值已经对了就跳过，
--   不会每帧无谓地让控件失效。
pcall(function()
    uevr.sdk.callbacks.on_pre_slate_draw_window_render_thread(function()
        apply()
    end)
end)

-- 启动时 HUD 可能还没生成（比如在菜单里就加载了脚本），那样所有组都会是
-- not found 并且永远不再重试。所以空的目标定期补找一次。
-- 只在「还有组是空的」时候才枚举 —— 全找到了就彻底停下，不再有开销。
local ticks = 0
pcall(function()
    uevr.sdk.callbacks.on_post_engine_tick(function()
        apply()
        ticks = ticks + 1

        -- ★ 每 ~30 秒轮转重解析一组目标（v19-fast 卡顿优化）。
        --
        --   为什么是「无条件」而不是「检测到失效才重解析」：
        --   1) 试过按句柄存活性判断（api:find_uobject(实例全名)）—— 实测那个
        --      API 对**活着的实例**也返回 nil，于是每轮都把好句柄判成失效、
        --      清空、停止写入，反而制造出「调好了却突然不生效」。已撤掉。
        --   2) 回归主菜单/换任务后，旧控件未必被销毁 —— 句柄还在、只是不再是
        --      屏幕上那一个。单纯查「还活不活着」根本判断不出来。
        --
        --   那就定期重新抓一遍，用结果比对代替猜测：抓到的是同一批就什么都不做，
        --   换了才真的换句柄。
        --   v19-fast：原版每 10 秒 5 组连发全量枚举（卡顿主嫌）改为每 30 秒
        --   只转一组 —— 想换关后恢复更快就调小 RESCAN_EVERY；想立刻全量，
        --   用面板上的 Reload targets 按钮。
        if ticks % RESCAN_EVERY == 0 then pcall(rescan_one) end
    end)
end)
