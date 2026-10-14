-- ============================================================================
-- AC8 v110 : 全机型通用版 —— 相对锚定 + 零查找热循环 + 慢车道治闪烁
--              + 剖面自适应机型补偿（三层机制，免逐机型手动适配）
-- ============================================================================
--
-- 【v129 备注：FPS 组件已移出主脚本】
--   v127/v128 的 stat FPS 实验记录见文件尾 changelog。FPS 功能现居 UEVR
--   全局脚本：.../Roaming/UnrealVRMod/UEVR/scripts/fps_stat_v1.lua
--   （对所有游戏生效，含 console 诊断，改它不动主脚本）。
--   v129 本身 = v126 干净态，其余逻辑零改动。
--
-- 【v110 新增：为什么不再"逐机型适配"】
--   v109 的机型指纹表是查表法——每来一个新机型就要人工报数补一行，
--   这不是"通用"。v110 换成三层自适应机制：
--     第 1 层【路径剖面捕获】发现时对 cp→Speed/Altitude/Whisky 三条路径
--        逐层读 RT，算「未清零层 RT 和 S」打 [PROF] 日志。
--        若某机型磁带偏移来自 RT 层 ⇒ S 直接给出可抵消量（全自动）；
--     第 2 层【机型指纹表】S≈0 但画面仍有偏移 ⇒ 偏移藏在 canvas slot 的
--        LayoutData（RT 层读不到），用残留 RT 指纹查 TACH_K_TABLE 兜底；
--     第 3 层【TACH_NUDGE 旋钮】即时微调，不用重跑测量。
--   外加 monitor_profiles：每 600 帧重算剖面，布局漂移>300 单位自动报警。
--   F-16 补偿已按两轮独立实测精化为 (-330,-174) 单位（v109 的 -438 混入
--   了速度读数框，偏大）。
--
-- 【v109 的教训：脚本不重载，新代码一行都不会跑】
--   15:39 用户反馈"F-16 还是偏右"——根因是 15:29 写盘的新版从未被加载
--   （session 14:12 启动，帧号连续递增未重启）。UEVR 只在启动/重载时读盘，
--   **改完脚本必须重载（重启游戏或脚本重载）才生效**。
--
-- 【v108 已验证部分（保持不动）】
--   慢车道治闪烁：用户 13:5x 确认"闪烁基本消失，偶尔闪一下，无伤大雅"。
--   准星/W 重合：VELOCITY_NUDGE=(6,-46)，用户确认"w不低了"。
--
-- 【本轮目标（按你的三点要求）】
--   1) 基于 v102 调整：v102 的钉子值全部原样保留（F-14 已验证完美）
--   2) 通用：不再按机型写绝对值。F-18 与 F-14 的差异 = 中央 HUD 簇在游戏
--      原生布局里的摆放不同（实测 F-18 偏 +954,+570 单位 = +477,+285px）。
--      v107 让脚本**自己在运行时量出这个差**，而不是查表。
--   3) 效率：v102 每隔 90 帧就把整套流程重跑一遍
--         （2 次 find_uobject 扫全部 UserWidget + 十几次递归遍历控件树），
--         v104/v105 又在其上叠加了每轮 20+ 行 log_info 落盘 —— 这就是
--         「两三秒卡一下 → 一秒卡一下」的来源。v107 的热循环里
--         **一次 find_uobject 都没有**，只有缓存引用上的少量属性读写。
--
-- 【v107 原理（相对位置，非绝对值）】
--   控件关系（v102 架构，不变）：
--     WorldToScreenDrawCanvas.RT = (TW_X, TW_Y)      ← 世界投影层（副武器圈）
--     ChroniclePersistent.RT     = (CANVAS-TW) + K   ← 中央 HUD 容器，K=机型补偿
--   关键事实：两款机型里，cp 内部的相对布局完全一样，整套「主HUD+W+时速表」
--   只是被整体搬了位；准星(Velocity)在 cp 内，其钉子值会自动抵消 K，
--   雷达在 cp 外（MainCanvas），本来就不受影响。
--   ⇒ 唯一随机型变的量就是 K。
--
--   v107 用量出来的办法定 K（不写死）：
--     · 锚点 = 雷达圆面板（RadarCircleCanvasPanel）的实测圆心
--              —— 它在 cp 外面，两款机型实测位置一致（屏幕左下角固定位）
--     · 目标 = 时速表中点的设计位置 = 锚点 + DESIGN_D
--              DESIGN_D 来自 F-14 良好截图实测：tach中点-雷达心 = (647,-320)px
--              = (1294,-640) 单位
--     · K := 实测(时速表中点-锚点) - DESIGN_D，迭代收敛（每步只走一半误差，
--            误差反涨就自动减半增益，天然防震荡），收敛后锁定
--   F-14 上 K 应收敛到 (0,0) ⇒ 与 v102 一个像素不差；
--   F-18 上 K 应收敛到约 (-954,-570) ⇒ 主HUD+W 归位。
--
-- 【性能设计】
--   · discover() 整套发现流程只在三种情况跑：脚本加载、HUD 失效、找不到时重试
--   · 帧循环里只有：整数取模判断 + 每 20 帧一次批量重钉（缓存引用，无搜索）
--   · 锚定只在收敛期间（十几帧）测量；收敛后热循环零几何读取
--   · 稳态日志 = 每 600 帧一行心跳（≈10 秒一行），不产生持续文件 I/O
--
-- 【安全阀】
--   · 锚点合理性门：雷达圆实测位必须落在设计位 ±300px 内，否则判定
--     「测量空间不可信」，直接回退机型表（防瞎收敛把画面挪坏）
--   · 单轴补偿上限 K_MAX（超了回退机型表）
--   · 几何读数单位自动判定（脚本单位 / 像素两种都兼容）
--   · FORCE_K_X/Y：强制指定 K（逃生门，默认 0 = 自动）
--   · SWEEP_RESIDUAL：发现时一次性把「v103 式残留」的中间容器复位
--     （只动 RT 绝对值 >600 的中间层；锚定收敛会自动兜底任何残留）
--
-- ★ v108 改动（针对你实测反馈的两个新问题）
--   问题1「主武器准星一直跳动闪烁」：
--     视频逐帧分析确认：准星在帧145-170 稳定，帧171 出现单帧 30px 下跳且
--     形状突变（上部竖线闪断一帧），帧185-189 逐渐被裁掉、帧190 完全消失。
--     成因：Velocity/VelocityIcon/GunReticle 等是**游戏每帧重排的世界投影/
--     自绘元素**，v102 以来一直把它们和静态容器一起每 20~90 帧重钉一次，
--     等于和游戏每帧抢位置 —— 钉得越勤，闪得越明显（v102 90 帧一下不太显，
--     v107 20 帧一下就被你抓住了）。
--     ⇒ 修复：把这些元素移入**慢车道** —— 只在「发现时 + 每 600 帧」钉一次，
--        热循环（20 帧）只碰静态容器（cp/wtsc/磁带/雷达圆），永不和游戏对打。
--     【09:21 实测确认】用户反馈：闪烁基本消失，偶尔闪一下，已无伤大雅 ✔
--   问题2「准星位置略微偏下」：
--     3840×2160 录像逐帧实测（1 视频像素 = 1 脚本单位，映射已验证）：
--       准星组件仅稳定出现在帧 140-185：环形准心 (1898,1030)、W 标
--       (1890,988)、瞄准横线 y≈968 横跨 x1588-2190；帧 185 起被裁窄
--       (112→98)、帧 190 后完全消失。屏幕正中心是 (1920,1080)。
--     钉子链反算 final = TW+cp+Velocity+Icon = (1893,1037)，与实测环心
--     只差 5~7 单位 ⇒ 准星一直在按设计值走，并未被搬低。
--     历史：v94 起你多次说"略微偏下"——现在明白真相了：准星(环)一直
--     比 W 标低 ~45 单位(22px)，你要的是"环与 W 重叠"，此前几版都把它
--     理解成"相对屏幕中心偏低"，所以一直没修到点子上。
--   问题2 已修复（本轮，按你的 1080p 截图逐像素实测）：
--     W 标重心 (1899,982)、环形准心 (1892,1027) => 环比 W 低 45、左 7 单位
--     VELOCITY_NUDGE 默认 = (6, -46)：环上移 23px，与 W 标重迭。
--     其他参考取值：环归中屏幕正中 (27,43)；组件整体重心归中 (23,76)。
--   另修：几何测量通道整体失效时（v107 日志里所有控件都"读不到"），
--     锚定不再无限每 2 帧重试空转，2 秒内认输并保持 K=机型表/0。
--
-- ★ v120 改动（只动相机 roll 通道，其余一律不动）
--   现象：左右滚转时 HUD 概率性整体歪斜、数秒后自己回正（已排除机身动画）。
--   根因：v119 把 pawn 滚转角写进 UEVR 回调的基准相机 rotation。座舱视角下
--         游戏原生相机 roll 恒为 0（倾斜的是世界、不是相机）；而 HUD 的投影
--         基准会采样 view rotation，横滚时注入的 roll≠0 就把 HUD 带歪，HUD
--         朝向自身有平滑/延迟采样 ⇒ 表现为"概率出现、数秒回正"。
--   修正：roll 通道透传原生值（≈0，与 v108 基线逐帧一致）⇒ HUD 永不受污染；
--         位置锚定（机头动画扣除的核心）与 pitch/yaw（与原生座舱相机一致）
--         不动，头动、HUD 钉固、卡顿降频全部不受影响。
--
-- ★ v126 改动 = 回到 v120 干净态（用户指令：v121~v125 的基准拖动全部推翻）
--   背景：v121(慢速lerp)→动画复活；v122(持久判定)→没解决；v123/post覆写→
--         v124 实锤 post 收到的是叠加HMD后的最终视图，写绝对位姿=杀头动；
--         v125 改为只读+源头停anims，但两个都没真正跑起来（见①）。
--   v126 定位：v120 的相机通道原样保留（机体本地系刚性锚定 + roll 透传 +
--         warmup + 偏差护栏），只做两件事——
--   ① 修 Lua 作用域 bug（实锤：截图 Last Script Error——exception in
--      on_post_engine_tick: attempt to call a nil value）。初版把开关前移了，
--      但停动画实现仍留在帧循环之后：cam_get_pcm() 内部调用更下方才声明的
--      cam_get_pawn ⇒ 闭包里是全局 nil ⇒ on_frame 每帧抛异常 ⇒
--      StopAllCameraAnims 从未执行（"动画还在"的直接原因）。现整段前移并
--      自包含（只用全局+前置local），每帧执行；StopAllCameraAnims/Shakes
--      显式带 UE5 必需的 bool 参数（初版没带参数，pcall 静默失败=没停）。
--   ② 修 early 日志 nil 算术报错（cam.sx - cam.tx 在 tx 未就绪时炸，就是
--      截图里那条 Last Script Error）：tx/sx 加 nil 守卫，未就绪打 n/a。
--   侧移对策（用户描述：持续同向转 10-30s 后视角一次性偏对侧、反向转回、
--         回正后不再现）：early 覆写只消除施加于 early 之前的偏移；若侧移施加
--         于 early 之后（CameraAnim 类），靠每帧 StopAllCameraAnims 掐源头；
--         post 回调保持只读探针，日志 动画层(实测)/层峰 = post最终位姿 − early
--         刚性目标，侧移发生时该值非零即可实锤层次。
--   保留 v124 的两个地基修复（身份 get_address、向量不跨帧持有）——没有它们
--         锚定根本不会写入（v123 日志"基准已确立"每帧刷屏的实锤原因）。
--   彻底移除：v121 慢速重锚、v122 持久性判定、post 写入（CAM_POST_WRITE=false
--         锁死）；基准只在进场/换 pawn 时捕获，之后永不动。

-- ★ v119 改动（在 v118 = v108 干净基线 + 只两件事的基础上，修正问题1的实现 bug）
--   问题1「下压杆机头做下压动画→HUD 像慢半拍才追上去」：
--     录像分析确认：HUD（屏幕空间）全程不动，位移发生在相机——机头下压动画
--     驱动的是「相机相对飞机 pawn 的位姿」，回位时相机回归，视觉上就成了
--     "HUD 追上去"。⇒ 不动任何 HUD 钉子，把相机刚性钉回座舱。
--     [CAM] 相机刚性锚定（UEVR 官方相机回调 on_early_calculate_stereo_view_offset，
--     参考 praydog UEVR / DS-FreeCam 用法 + KismetMathLibrary 向量算子）：
--       v118 缺陷（实测复现）：基准偏移按"世界固定向量"记录 ⇒ 飞机一转身，
--         座舱绕机体转、相机却钉死在世界某点 ⇒ 一推杆视角甩出座舱盖。
--       v119 修正：偏移按**机体本地坐标系**记录，每帧随 pawn 旋转转回世界：
--           本地偏移 := LessLess_VectorRotator(相机位-pawn位, pawn旋转)
--           相机目标 := pawn位 + GreaterGreater_VectorRotator(本地偏移, pawn旋转)
--         角度同理：目标角 := pawn角 + 安装角差（欧拉差）
--         （算子与用法照抄 DS-FreeCam libfreecam.lua：GreaterGreater=本地→世界
--           向量、LessLess=世界→本地向量；每帧两次调用，零搜索零枚举）
--       · HMD 头部跟踪在该回调之后叠加 ⇒ 头动完全不受影响
--       · 飞机正常机动仍跟随；机头动画的额外位移/旋转每帧被刚性扣除
--       · 换关卡/换机自动重捕；开局先确认 10 个稳定帧才开写（防出生/过场动画瞬移）
--       · 与游戏相机偏差 >120cm 或 >15° 视为模型失配 ⇒ 该帧透传保命；
--         连续 30 秒失配则自动停用锚定（保证不会把视角甩出座舱）
--       · 逃逸开关：CAM_ANCHOR=false 完全回退原生相机
--       · 诊断：每 600 帧 [CAM] 状态行——"动画量"=本帧消除的动画量，
--         量大=动画在相机层（已被消除）；≈0 且仍晃=动画在座舱 mesh，下轮换靶
--   问题2「时不时小卡一下」：v118 降频维持原样（功能不变，只改间隔：
--     FINGERPRINT 240→1200 / VALIDATE 45→180 / MISSING_RETRY 300→1200 /
--     monitor_profiles 600→1800；ladder 侧重扫 10 秒全量 5 组 → 30 秒轮转 1 组）。
-- ============ v102 钉子值（原样保留，F-14 已验证） ============
local CANVAS_X,  CANVAS_Y     = 1200, 350     -- 中央 HUD 目标位置（净位移）
local TW_X,      TW_Y         = -35, -55      -- 副武器/自绘层
local WHISKY_X,  WHISKY_Y     = 10, 6         -- W
local VELOCITY_X, VELOCITY_Y  = -1227, -400   -- 主武器准星（抵消 cp 位移的绝对钉）
-- ★ v108 准星微调旋钮（在 VELOCITY_X/Y 之上叠加；每 2 单位 = 1 屏幕像素）
--   实测（你的 1080p 截图 09:21）：W 标重心 (1899,982)、环形准心 (1892,1027)
--   => 准星比 W 标低 45 单位（22px）。按你要求"准星与 W 重叠"：
local VELOCITY_NUDGE_X, VELOCITY_NUDGE_Y = 6, -46
--   其他参考取值：环归中屏幕正中 (27,43) / 组件整体重心归中 (23,76)
--   想再往上/下微调：各自加减（-8 = 上移 4px）
local MAIN_X,    MAIN_Y       = 0, 0
local TACH_PULL, TACH_Y       = 0, 0
local RADAR_CIRCLE_DY         = -95           -- 雷达圆：v102 你说完美，冻结

local VICON_BASE_X,      VICON_BASE_Y      = 1920, 1087
local GUNRETICLE_BASE_X, GUNRETICLE_BASE_Y = 1920, 1080

local SHIFT_VIA_PERSISTENT = true
local FIX_RADAR_CIRCLE     = true
local SINGLE_INSTANCE      = false -- ★誤爆削除を防止するため無効化

local RESET_LIST = {
    { key = "GunReticle",           pat = "GunReticle",           x = 1920, y = 1080 },
    { key = "Seeker",               pat = "Seeker",               x = 0,    y = 0    },
    -- { key = "Locator",              pat = "Locator",              x = 0,    y = 0    }, -- Unpinned for Target Locator restoration test
    { key = "ExplosivePredication", pat = "ExplosivePredication", x = 0,    y = 0    },
    { key = "TargetSelectionDraw",  pat = "TargetSelectionDraw",  x = 0,    y = 0    },
}

-- ============ v107 新增：锚定常量（全部是"相对设计关系"，不是机型绝对值） ============
-- 设计偏移 D = 时速表中点 - 雷达圆心（F-14 良好截图实测，单位 = 0.5px）
local DESIGN_DX, DESIGN_DY = 1294, -640
-- 雷达圆的设计位置（同上截图实测，单位）；同时用作「测量空间」判定的基准
local ANCHOR_EXP_X, ANCHOR_EXP_Y = 494, 1746
local SCALE_TOL    = 400   -- 空间判定容差（单位）
local K_MAX        = 2400  -- 单轴补偿上限（=1200px，超过视为不可信）
local TOL_UNITS    = 3     -- 收敛容差（1.5px）
local CAL_GAIN0    = 0.5   -- 初始增益：每步只走一半误差（宁慢不震荡）
local CAL_MAX_ITER = 40
local CAL_FAIL_MAX = 120  -- 连续读不到几何的次数上限（≈2 秒），超过就认输保持现状
local CAL_STEP_EVERY  = 2    -- 锚定步进间隔（帧）——等一帧让几何刷新
local ASSERT_EVERY    = 20   -- 批量重钉间隔（帧）
local VALIDATE_EVERY  = 180   -- 缓存活性校验间隔（帧；v118 从 45 降频）
local MISSING_RETRY_EVERY = 1200  -- 补找缺失控件间隔（帧；v118 从 300 降频）
local FINGERPRINT_EVERY   = 1200  -- 机型指纹检查间隔（帧；v118 从 240 降频，换机是稀有事件）
local HB_EVERY       = 600  -- 心跳日志间隔（帧，≈10 秒）
local MONITOR_EVERY  = 1800 -- 布局剖面监控间隔（帧；v118 从 HB 的 600 拆出并降频——3 条路径子树搜索比想象贵）
local SWEEP_RESIDUAL = true -- 发现时清理历史版本搬坏的中层容器
local SWEEP_THRESHOLD = 600 -- 中间层 RT 绝对值超过此值视为残留
local FORCE_K_X, FORCE_K_Y = 0, 0  -- 逃生门：非 0 = 强制 K，跳过自动锚定

-- ★ v110：机型自适应三层机制（不再逐机型手动适配）
--   第 1 层【路径剖面捕获】：发现时对 Speed/Altitude/Whisky 三条路径逐层读 RT，
--     记录「未清零层的 RT 和 S」并打 [PROF] 日志。若某机型的磁带偏移来自 RT 层
--     （而非 slot），S 就是可全自动抵消的量——零查表。
--   第 2 层【机型指纹表】兜底：剖面 S≈0 但用户实测有偏移（说明偏移藏在
--     canvas slot 的 LayoutData 里，RT 层看不到）→ 查 TACH_K_TABLE。
--   第 3 层【运行时微调旋钮】TACH_NUDGE_X/Y：即时增减，不用重跑测量。
--   每 600 帧重算一次剖面（monitor_profiles），HUD 重建/换机型导致剖面
--   漂移 >300 单位时自动打警告——不用重载脚本也能发现布局变了。
--
-- F-16 实测（两轮独立截图交叉）：
--   轮1(15:19)：高度带竖线 x≈1356，设计 x=1182 → 偏右 +174px
--   轮2(15:39)：高度带竖线 bbox x1335-1355 中心 1345 → 偏右 +163px
--   Y 两轮一致 +87px。故补偿取 (-330,-174) 单位（覆盖两轮误差<10px）。
--   （v109 原值 -438 来自簇中点测量，混入了速度读数框，偏大。）
local TACH_K_TABLE = {
    { rx = 689,  ry = 630,  dx = 0,    dy = 0    },  -- F-18：清零原生残留即正确
    { rx = 1026, ry = 938,  dx = -330, dy = -174 },  -- F-16：实测补偿（v110 精化）
    { rx = -330, ry = -174, dx = -330, dy = -174 },  -- F-16 自我签名：脚本重载后面板上已是补偿值
}
local TACH_K_TOL = 60          -- 指纹匹配容差（单位）
local TACH_KX, TACH_KY = 0, 0  -- 运行期解出的磁带簇补偿
local TACH_K_LOCKED = false    -- 命中过非零补偿就锁定，防二次发现时指纹被自己抹掉
local TACH_K_MATCH  = "未匹配(默认0)"
local TACH_NUDGE_X, TACH_NUDGE_Y = 0, 0  -- v110 手动微调（叠加在表补偿之上）

-- 回退表：只在「自动锚定不可信」时兜底（测量通道挂掉/机型极特殊时）
-- 注意：这不是主路径；主路径是运行时自己量出来的 K。
local K_FALLBACK = {
    { pat = "fa%-?18",        kx = 954,  ky = 570 },  -- F/A-18E/F
    { pat = "f%-?18",         kx = 954,  ky = 570 },
    { pat = "superhornet",    kx = 954,  ky = 570 },
    { pat = "hornet",         kx = 954,  ky = 570 },
    { pat = "fa%-?14",        kx = 0,    ky = 0   },  -- F-14D（设计基准）
    { pat = "f%-?14",         kx = 0,    ky = 0   },
    { pat = "tomcat",         kx = 0,    ky = 0   },
}

-- ============ 日志通道：uevr.params.functions.log_info -> UEVR 的 log.txt ============
-- （extended_cvars.lua 用的就是它；print 默认只进控制台不进文件）
local LOGFN = nil
do
    local fns = (uevr ~= nil and uevr.params ~= nil) and uevr.params.functions or nil
    if fns ~= nil then LOGFN = fns.log_info or fns.log_warn or fns.log end
end
do
    local _print = print
    print = function(...)
        local n = select("#", ...)
        local t = {}
        for i = 1, n do t[i] = tostring((select(i, ...))) end
        local s = table.concat(t, " ")
        _print(s)
        if LOGFN ~= nil then pcall(LOGFN, "[AC8V129] " .. s) end
    end
end

print(string.format("[AC8-V129] 日志通道=%s  canvas=(%d,%d) tweak=(%d,%d) velocity=(%d,%d)",
    tostring(LOGFN ~= nil), CANVAS_X, CANVAS_Y, TW_X, TW_Y, VELOCITY_X, VELOCITY_Y))
print(string.format("[AC8-V129] 准星微调 nudge=(%d,%d) => 实际钉=(%d,%d)（默认环与W重叠；归中屏心(27,43)）",
    VELOCITY_NUDGE_X, VELOCITY_NUDGE_Y, VELOCITY_X + VELOCITY_NUDGE_X, VELOCITY_Y + VELOCITY_NUDGE_Y))
print("[AC8-V129] 机型补偿 K 改为运行时相对锚定（锚点=雷达圆，目标=设计偏移），不再写死绝对值")
print("[AC8-V129] 准星/VelocityIcon/GunReticle 走慢车道（发现时+600帧），热循环不与游戏对打")

-- ============ 基础工具（沿用 v102/v105 已验证实现） ============
local function p(obj)
    if obj == nil then return "<nil>" end
    local ok, v = pcall(function() return obj:get_full_name() end)
    if not ok or v == nil then return "<no full_name>" end
    return v
end
local function short_name(obj)
    local nm = p(obj)
    if type(nm) == "string" then return nm:match("([^%.%/]+)$") or nm end
    return "<?>"
end
local function get_field(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(function() return obj[name] end)
    if not ok then return nil end
    return v
end
local function get_rt_xy(obj)
    if obj == nil then return nil, nil end
    local rt = get_field(obj, "RenderTransform")
    if rt == nil then return nil, nil end
    local t = get_field(rt, "Translation")
    if t == nil then return nil, nil end
    return get_field(t, "X"), get_field(t, "Y")
end
-- 热路径用：只写不读不打印
local function fast_rt(obj, tx, ty)
    if obj == nil then return false end
    pcall(function() obj:SetRenderTranslation({ X = tx, Y = ty }) end)
    return true
end
-- 发现路径用：写 + 读回验证 + 打印（一次性，不在热循环）
local function set_rt(obj, tx, ty, tag, quiet)
    if obj == nil then
        if not quiet then print(string.format("[AC8-V129]   RT %-38s !! 未找到", tag)) end
        return false
    end
    pcall(function() obj:SetRenderTranslation({ X = tx, Y = ty }) end)
    if not quiet then
        local nx, ny = get_rt_xy(obj)
        local good = (type(nx) == "number" and math.abs(nx - tx) < 1 and math.abs(ny - ty) < 1)
        print(string.format("[AC8-V129]   RT %-38s set=(%d,%d) readback=(%s,%s) %s",
            tag, tx, ty, tostring(nx), tostring(ny), good and "OK" or "<<< 未生效"))
    end
    return true
end
local function iter_children(w)
    local children = {}
    if w == nil then return children end
    local okc, cc = pcall(function() return w.GetChildrenCount and w:GetChildrenCount() or 0 end)
    if okc and type(cc) == "number" and cc > 0 then
        for i = 0, cc - 1 do
            local ok2, c = pcall(function() return w:GetChildAt(i) end)
            if ok2 and c then table.insert(children, c) end
        end
    end
    if #children == 0 then
        local wt = get_field(w, "WidgetTree")
        if wt then
            local r = get_field(wt, "RootWidget")
            if r then table.insert(children, r) end
        end
    end
    return children
end
local function find_desc(root, target, maxd, exact)
    if root == nil then return nil end
    local seen, found = {}, nil
    local function rec(w, d)
        if w == nil or found or d > maxd then return end
        local addr = tostring(w)
        if seen[addr] then return end
        seen[addr] = true
        local nm = short_name(w)
        local hit = exact and (nm == target) or (not exact and nm:find(target, 1, true) ~= nil)
        if hit then found = w; return end
        for _, c in ipairs(iter_children(w)) do rec(c, d + 1) end
    end
    rec(root, 0)
    return found
end
local function find_path(root, addr, maxd)
    if root == nil or addr == nil then return nil end
    local path = nil
    local function rec(w, d, acc)
        if w == nil or path or d > maxd then return end
        table.insert(acc, w)
        if tostring(w) == addr then path = acc; return end
        for _, c in ipairs(iter_children(w)) do rec(c, d + 1, acc) end
        if path == nil then table.remove(acc) end
    end
    rec(root, 0, {})
    return path
end
local function all_userwidgets()
    if uevr == nil or uevr.api == nil then return {} end
    local umg = uevr.api:find_uobject("Class /Script/UMG.UserWidget")
    if umg == nil then return {} end
    local ok, objs = pcall(function() return umg:get_objects_matching(false) end)
    if not ok or type(objs) ~= "table" then return {} end
    return objs
end
local function all_mainflights(uw)
    local out = {}
    for _, w in ipairs(uw) do
        local nm = p(w)
        if type(nm) == "string" and nm:find("WBP_HUD_Chronicle_MainFlight", 1, true)
            and not nm:find("Default__", 1, true) and not nm:find(".WidgetTree", 1, true) then
            table.insert(out, w)
        end
    end
    return out
end

-- ============ 几何测量：绝对中心（锚定的眼睛） ============
-- 依次尝试 绘制空间/缓存空间/tick空间；都要求 Size>0（未绘制的返回 0 直接作废）
local function abs_center(w)
    if w == nil then return nil end
    for _, fn in ipairs({ "GetPaintSpaceGeometry", "GetCachedGeometry", "GetTickSpaceGeometry" }) do
        local ok, geo = pcall(function() return w[fn](w) end)
        if ok and geo ~= nil then
            local ap = get_field(geo, "AbsolutePosition")
            local sz = get_field(geo, "Size")
            local ax, ay = get_field(ap, "X"), get_field(ap, "Y")
            local sx, sy = get_field(sz, "X"), get_field(sz, "Y")
            if type(ax) == "number" and type(ay) == "number"
               and type(sx) == "number" and type(sy) == "number" and sx > 0 and sy > 0 then
                return { x = ax + sx / 2, y = ay + sy / 2, via = fn }
            end
        end
    end
    return nil
end

-- ============ 机型指纹（只在换机/发现时算，不进热循环） ============
local function pawn_full_name()
    if uevr == nil or uevr.api == nil or uevr.api.get_player_pawn == nil then return nil end
    local ok, pawn = pcall(function() return uevr.api:get_player_pawn() end)
    if not ok or pawn == nil then return nil end
    local ok2, nm = pcall(function() return pawn:get_full_name() end)
    if ok2 and type(nm) == "string" then return nm end
    return nil
end
local function fallback_k(name)
    if name == nil then return nil end
    local low = string.lower(name)
    for _, it in ipairs(K_FALLBACK) do
        if low:find(it.pat) then return it.kx, it.ky end
    end
    return nil
end

-- ============ 缓存（v107 的核心：发现一次，之后只引用） ============
local C = {
    ready  = false,
    keep   = nil, base = nil, wtsc = nil, maincv = nil, cp = nil,
    ts = nil, ta = nil, vicon = nil, vel = nil, whisky = nil,
    radar = {}, radar_main = nil,
    pins = {},          -- { obj=, x=, y=, tag=, dyn= } dyn=随 K 变动（cp）
}
local cal = {
    active = false, kx = 0, ky = 0, gain = CAL_GAIN0, iter = 0,
    scale = nil, pex = nil, pey = nil, cur_fp = nil, warm = 0, fail = 0,
}

-- cp 的目标钉（R0 + K）
local R0_X = CANVAS_X - TW_X
local R0_Y = CANVAS_Y - TW_Y

-- ============ v110：路径剖面捕获（sweep 与 monitor 共用） ============
-- 对 cp→磁带/W 的三条路径逐层读 RT，输出 profile 数组。
--   zero_big=true  ：发现时用——顺带清零 >阈值 的历史残留层（原 v103 行为）
--   zero_big=false ：运行时用——只读不写，用于漂移监控
-- 每个 profile：{ key=目标名, layers={{name,x,y}...}, sx/sy=未清零层 RT 和（=机型原生偏移候选）,
--                 max_layer=被清零层，cleared=清零层数 }
-- ★ v110 修复：必须单段完成「读→录指纹→清零」。曾经的两段式（先旧循环清零，
--   再 capture 重读）会把指纹录成 (0,0)，导致机型表永远匹配不上。
local function capture_profiles(zero_big, quiet)
    local out = {}
    if C.cp == nil then return out end
    for _, tgt in ipairs({ "SpeedTachometerCenterPanel", "AltitudeTachometerCenterPanel", "WhiskyMarkPanel" }) do
        local t = find_desc(C.cp, tgt, 14, true)
        if t ~= nil then
            local path = find_path(C.cp, tostring(t), 14)
            if path ~= nil and #path > 2 then
                local prof = { key = tgt, layers = {}, sx = 0, sy = 0, cleared = 0 }
                for i = 2, #path - 1 do
                    local w = path[i]
                    local x, y = get_rt_xy(w)
                    local x0 = (type(x) == "number") and x or 0
                    local y0 = (type(y) == "number") and y or 0
                    -- 无条件记录幅度最大的路径层 RT 当指纹候选（小残留也算——
                    -- 脚本重载后 F-16 的指纹就是我们自己写进去的补偿值）
                    local mag = math.abs(x0) + math.abs(y0)
                    if zero_big and (C.resid == nil or mag > C.resid.mag) then
                        C.resid = { x = x0, y = y0, mag = mag }
                    end
                    table.insert(prof.layers, { name = short_name(w), x = x0, y = y0 })
                    if zero_big and (math.abs(x0) > SWEEP_THRESHOLD or math.abs(y0) > SWEEP_THRESHOLD) then
                        if not quiet then
                            print(string.format("[AC8-V129] [SWEEP] 复位残留中间层 %s RT=(%.0f,%.0f) -> (0,0)",
                                short_name(w), x0, y0))
                        end
                        fast_rt(w, 0, 0)
                        prof.max_layer = { name = short_name(w), x = x0, y = y0 }
                        prof.cleared = prof.cleared + 1
                    else
                        prof.sx = prof.sx + x0
                        prof.sy = prof.sy + y0
                    end
                end
                table.insert(out, prof)
            end
        end
    end
    return out
end

-- ============ 一次性：v103 式残留清扫（v110 单段式：读→录指纹→清零一次完成） ============
local function sweep_residual(quiet)
    if not SWEEP_RESIDUAL or C.cp == nil then return 0 end
    C.resid = nil
    C.prof = capture_profiles(true, quiet)
    local fixed = 0
    if C.prof ~= nil then
        for _, prof in ipairs(C.prof) do fixed = fixed + (prof.cleared or 0) end
    end
    if not quiet then
        if fixed > 0 then
            print(string.format("[AC8-V129] [SWEEP] 共复位 %d 个残留中间层", fixed))
        else
            print("[AC8-V129] [SWEEP] 无残留（中间层都在正常范围）")
        end
        if C.prof ~= nil then
            for _, prof in ipairs(C.prof) do
                print(string.format("[AC8-V129] [PROF] %s：%d 层，未清零层RT和 S=(%.0f,%.0f)",
                    prof.key, #prof.layers, prof.sx, prof.sy))
                if prof.max_layer ~= nil then
                    print(string.format("[AC8-V129] [PROF]   已清零层 %s RT=(%.0f,%.0f)",
                        prof.max_layer.name, prof.max_layer.x, prof.max_layer.y))
                end
            end
            print("[AC8-V129] [PROF] 注：S 非 0 = 磁带偏移来自 RT 层（可自动抵消）；S≈0 但有偏移 = slot 层（走机型表）")
        end
    end
    return fixed
end

-- ============ 机型指纹 -> 磁带簇补偿（v109，v110 加剖面证据） ============
-- 输入：sweep 捕获的原生残留 RT（C.resid）+ 路径剖面 S（C.prof）；输出：TACH_KX/TACH_KY
-- 锁定逻辑：命中过非零补偿后即使二次发现读到已被抹平的 RT，也保持原补偿。
local function match_tach_k()
    if TACH_K_LOCKED then
        TACH_K_MATCH = string.format("已锁定 K=(%d,%d)，保持", TACH_KX, TACH_KY)
        return
    end
    local r = C.resid
    if r == nil then
        TACH_KX, TACH_KY = 0, 0
        TACH_K_MATCH = "无原生残留 -> (0,0)"
        return
    end
    for _, e in ipairs(TACH_K_TABLE) do
        if math.abs(r.x - e.rx) <= TACH_K_TOL and math.abs(r.y - e.ry) <= TACH_K_TOL then
            TACH_KX, TACH_KY = e.dx, e.dy
            TACH_K_MATCH = string.format("残留RT=(%.0f,%.0f) 命中机型表 -> K=(%d,%d)", r.x, r.y, TACH_KX, TACH_KY)
            if TACH_KX ~= 0 or TACH_KY ~= 0 then TACH_K_LOCKED = true end
            return
        end
    end
    TACH_KX, TACH_KY = 0, 0
    TACH_K_MATCH = string.format("残留RT=(%.0f,%.0f) 未命中机型表 -> (0,0)，请把 [PROF] S 值和实测偏移补表", r.x, r.y)
end

-- ============ v110：运行时剖面监控 ============
-- 每 HB_EVERY 帧轻量重算三条路径剖面（只读，不清零不改钉）。
-- 实测结论：F-16 上被清零的布局层会被游戏恢复（sweep 清零无效但无害），
-- 所以「S 与发现时基线不同」是正常现象——只提示一次并刷新基线，不刷 ★。
-- 真正用途：机型切换/HUD 重建时给一行可回溯的日志。
local PROF_DRIFT_TOL = 300
local function monitor_profiles()
    if C.cp == nil or C.prof == nil then return end
    local now = capture_profiles(false, true)
    if #now == 0 then return end
    local drift = false
    for i = 1, math.min(#now, #C.prof) do
        local a, b = C.prof[i], now[i]
        local dx = math.abs((b.sx or 0) - (a.sx or 0))
        local dy = math.abs((b.sy or 0) - (a.sy or 0))
        if dx > PROF_DRIFT_TOL or dy > PROF_DRIFT_TOL then drift = true end
    end
    C.prof = now  -- 先刷新基线（S 稳定后自然不再提示）
    if drift then
        print("[AC8-V129] [PROF] 布局剖面与发现时不同（HUD 重建/游戏恢复中间层，机型切换时正常）——若画面此刻偏移异常，重载脚本重新捕获")
    end
end

-- ============ 雷达圆：收集全部同名节点（v102 命中即停 → 容易漏掉可见那套） ============
local function collect_radar(root)
    local out = {}
    if root == nil then return out end
    local seen = {}
    local function rec(w, d)
        if w == nil or d > 18 then return end
        local addr = tostring(w)
        if seen[addr] then return end
        seen[addr] = true
        if short_name(w):find("RadarCircleCanvasPanel", 1, true) then
            table.insert(out, w)
        end
        for _, c in ipairs(iter_children(w)) do rec(c, d + 1) end
    end
    rec(root, 0)
    return out
end

-- ============ 批量重钉（热路径；只动缓存引用） ============
-- ★ v108：分快慢两车道
--   快车道（每 ASSERT_EVERY 帧）：静态布局容器 —— cp/wtsc/maincv/磁带/雷达圆。
--     这些元素游戏不会每帧重排，钉住是安全的，且要防游戏偶尔复位。
--   慢车道（仅发现时 + 每 HB_EVERY 帧）：Velocity/VelocityIcon/GunReticle 等
--     世界投影/自绘元素 —— 游戏每帧重排它们，我们钉得越勤闪得越厉害，
--     所以几乎不碰，只做低频保底。
--   ★ 另加「读回 guard」：目标值已经一致就跳过写入，避免无意义的 paint 失效。
local function assert_pins(slow)
    local n = 0
    for _, pin in ipairs(C.pins) do
        if pin.obj ~= nil and (slow or not pin.slow) then
            local x, y = pin.x, pin.y
            if pin.dyn then x = R0_X + cal.kx; y = R0_Y + cal.ky end
            local cx, cy = get_rt_xy(pin.obj)
            local okx = (type(cx) == "number" and math.abs(cx - x) < 1)
            local oky = (type(cy) == "number" and math.abs(cy - y) < 1)
            if not (okx and oky) then
                fast_rt(pin.obj, x, y)
            end
            n = n + 1
        end
    end
    if FIX_RADAR_CIRCLE then
        for _, w in ipairs(C.radar) do
            if w ~= nil then
                local cx, cy = get_rt_xy(w)
                if not (type(cx) == "number" and math.abs(cx) < 1
                        and type(cy) == "number" and math.abs(cy - RADAR_CIRCLE_DY) < 1) then
                    fast_rt(w, 0, RADAR_CIRCLE_DY)
                end
                n = n + 1
            end
        end
    end
    -- visibility/opacity 兜底：移到慢车道（发现时+600 帧），不再每 20 帧写
    if slow then
        if C.keep ~= nil then
            pcall(function() C.keep.RenderOpacity = 1.0 end)
            pcall(function() C.keep.Visibility = 0 end)
        end
        if C.base ~= nil then
            pcall(function() C.base.RenderOpacity = 1.0 end)
            pcall(function() C.base.Visibility = 0 end)
        end
    end
    return n
end

-- ============ 锚定：一步收敛 ============
local function cal_use_fallback(why, name)
    local kx, ky = fallback_k(name)
    if kx == nil then kx = 0; ky = 0 end
    cal.kx, cal.ky = kx, ky
    cal.active = false
    print(string.format("[AC8-V129] [锚定] %s -> 回退机型表 K=(%d,%d)", why, kx, ky))
    assert_pins(true)   -- v108: 含慢车道（准星等世界投影元素）
    return true
end

local function cal_step()
    if not cal.active then return true end
    -- 预热：刚写入 K 后几何要下一帧才刷新，先丢掉前几次读数，避免按旧值重复补偿
    if cal.warm > 0 then
        cal.warm = cal.warm - 1
        return false
    end
    if FORCE_K_X ~= 0 or FORCE_K_Y ~= 0 then
        cal.kx, cal.ky = FORCE_K_X, FORCE_K_Y
        cal.active = false
        print(string.format("[AC8-V129] [锚定] FORCE_K 生效 K=(%d,%d)", cal.kx, cal.ky))
        assert_pins(true)   -- v108: 含慢车道（准星等世界投影元素）
        return true
    end
    if C.ts == nil or C.ta == nil or C.radar_main == nil then
        return cal_use_fallback("缺时速表/雷达圆，无法测量", cal.cur_fp)
    end
    local a  = abs_center(C.ts)
    local b  = abs_center(C.ta)
    local an = abs_center(C.radar_main)
    if a == nil or b == nil or an == nil then
        -- v108：几何通道失效时不无限空转（v107 日志里所有控件都读不到，
        -- 结果每 2 帧重试一次白烧 CPU）。累计失败到上限就认输。
        cal.fail = cal.fail + 1
        if cal.fail == 1 then
            print("[AC8-V129] [锚定] 几何读不到（GetPaint/Cached/TickSpaceGeometry 都失败）——"
                .. "将在 ~2 秒后放弃自动锚定，保持 K=机型表/0（v107 实测此状态下两机 HUD 均正常）")
        end
        if cal.fail >= CAL_FAIL_MAX then
            cal.active = false
            print(string.format("[AC8-V129] [锚定] 连续 %d 次读不到几何 -> 放弃自动锚定，K=(%.0f,%.0f) 保持",
                cal.fail, cal.kx, cal.ky))
        end
        return false
    end
    cal.fail = 0
    -- 测量空间判定（几何读数可能是"脚本单位"也可能是"像素"，自动识别）
    if cal.scale == nil then
        if math.abs(an.x - ANCHOR_EXP_X) <= SCALE_TOL and math.abs(an.y - ANCHOR_EXP_Y) <= SCALE_TOL then
            cal.scale = 1
        elseif math.abs(an.x - ANCHOR_EXP_X / 2) <= SCALE_TOL / 2
           and math.abs(an.y - ANCHOR_EXP_Y / 2) <= SCALE_TOL / 2 then
            cal.scale = 2   -- 读数单位是像素：×2 换算成脚本单位
        else
            print(string.format("[AC8-V129] [锚定] 雷达圆实测=(%.0f,%.0f)，偏离设计位(494,1746)太远"
                .. " -> 测量空间不可信，不盲纠", an.x, an.y))
            return cal_use_fallback("锚点异常", cal.cur_fp)
        end
        print(string.format("[AC8-V129] [锚定] 空间标定：几何读数=%s（雷达圆 %.0f,%.0f）",
            (cal.scale == 1) and "脚本单位(1=0.5px)" or "像素", an.x, an.y))
    end
    local s = cal.scale
    local mx = (a.x + b.x) / 2 * s
    local my = (a.y + b.y) / 2 * s
    local ax = an.x * s
    local ay = an.y * s
    local ex = (mx - ax) - DESIGN_DX
    local ey = (my - ay) - DESIGN_DY

    if math.abs(ex) < TOL_UNITS and math.abs(ey) < TOL_UNITS then
        cal.active = false
        print(string.format("[AC8-V129] [锚定] ★收敛 K=(%.0f,%.0f) 单位 =(%.0f,%.0f) px，%d 步完成",
            cal.kx, cal.ky, cal.kx / 2, cal.ky / 2, cal.iter))
        return true
    end
    if math.abs(cal.kx) > K_MAX or math.abs(cal.ky) > K_MAX then
        return cal_use_fallback("补偿量超上限", cal.cur_fp)
    end
    cal.iter = cal.iter + 1
    if cal.iter > CAL_MAX_ITER then
        return cal_use_fallback("迭代次数用尽", cal.cur_fp)
    end
    -- 误差没变小 -> 增益减半（防单位误判导致的反复震荡）
    if cal.pex ~= nil and cal.pey ~= nil then
        local pe = math.max(math.abs(cal.pex), math.abs(cal.pey))
        local ne = math.max(math.abs(ex), math.abs(ey))
        if ne > pe * 1.05 and cal.gain > 0.06 then
            cal.gain = cal.gain / 2
            print(string.format("[AC8-V129] [锚定] 误差未缩小 -> 增益减半为 %.3f", cal.gain))
        end
    end
    cal.kx = cal.kx - cal.gain * ex
    cal.ky = cal.ky - cal.gain * ey
    cal.pex, cal.pey = ex, ey
    assert_pins(true)   -- v108: 含慢车道（准星等世界投影元素）
    print(string.format("[AC8-V129] [锚定] 步%02d K=(%.0f,%.0f) 残差=(%.1f,%.1f) 单位",
        cal.iter, cal.kx, cal.ky, ex, ey))
    return false
end

-- ============ 补找缺失控件（RESET_LIST 里有些是条件生成的） ============
local function retry_missing()
    if C.wtsc == nil then return end
    for _, it in ipairs(RESET_LIST) do
        local pin = nil
        for _, q in ipairs(C.pins) do if q.tag == "RESET:" .. it.key then pin = q end end
        if pin ~= nil and pin.obj == nil then
            local w = find_desc(C.wtsc, it.pat, 12)
            if w ~= nil then
                pin.obj = w
                fast_rt(w, it.x, it.y)
                print(string.format("[AC8-V129] [补找] %s 出现，已钉 (%d,%d)", it.key, it.x, it.y))
            end
        end
    end
end

-- ============ 发现流程（只在需要时跑；贵操作全在这里面） ============
local function discover()
    print("[AC8-V129] === 发现流程开始（整套搜索只在这时跑）===")
    -- 先把旧缓存全部作废（旧 userdata 可能已失效）
    C.keep = nil; C.base = nil; C.wtsc = nil; C.maincv = nil; C.cp = nil
    C.ts = nil; C.ta = nil; C.vicon = nil; C.vel = nil; C.whisky = nil
    C.radar = {}; C.radar_main = nil; C.pins = {}
    C.resid = nil; C.prof = nil

    local uw = all_userwidgets()
    -- 保持暂停/菜单可见（原 v102 行为；只在发现时做一次）
    for _, w in ipairs(uw) do
        local nm = p(w)
        if type(nm) == "string" and not nm:find("Default__", 1, true)
            and not nm:find(".WidgetTree", 1, true) then
                local hit = false
                for _, k in ipairs({ "Pause", "Menu", "RootMenu" }) do
                    if nm:find(k, 1, true) then hit = true; break end
                end
                if hit then
                    local before = nil
                    pcall(function() before = w:IsInViewport() end)
                    if before == false then pcall(function() w:AddToViewport() end) end
                end
        end
    end

    local mfs = all_mainflights(uw)
    print(string.format("[AC8-V129] MainFlight 实例数 = %d", #mfs))
    if #mfs == 0 then
        print("[AC8-V129] !! 找不到 MainFlight（请确认已起飞进入任务），60 帧后重试")
        return false
    end
    local keep, keep_addr = nil, nil
    -- 逆順（最新に生成されたインスタンス順）でBaseCanvasを持つ生きた実体を探索
    for i = #mfs, 1, -1 do
        local mf = mfs[i]
        local test_base = find_desc(mf, "BaseCanvas", 6, true)
        if test_base ~= nil then
            keep = mf
            keep_addr = tostring(mf)
            print(string.format("[AC8-V129] ★ 有効な最新 MainFlight を捕捉: %s (Index=%d/%d)", p(mf), i, #mfs))
            break
        end
    end
    -- もし BaseCanvas 未初期化なら、最新のインスタンス (mfs[#mfs]) を選択
    if keep == nil then
        keep = mfs[#mfs]
        keep_addr = tostring(mfs[#mfs])
        print(string.format("[AC8-V129] 最新 MainFlight を選択: %s", p(keep)))
    end

    -- Viewport に入っていなければアタッチ
    local inv = nil
    pcall(function() inv = keep:IsInViewport() end)
    if inv ~= true then
        pcall(function() keep:AddToViewport() end)
    end

    -- ★ 危険な誤爆削除 (RemoveFromViewport) は完全に撤廃
    C.keep = keep

    pcall(function() keep.RenderOpacity = 1.0 end)
    pcall(function() keep.Visibility = 0 end)

    local base = find_desc(keep, "BaseCanvas", 6, true)
    if base == nil then
        print("[AC8-V129] !! BaseCanvas 未找到，60 帧后重试")
        return false
    end
    C.base = base
    pcall(function() base.RenderOpacity = 1.0 end)
    pcall(function() base.Visibility = 0 end)

    local blur = find_desc(base, "BlurEffectBox", 8)
    if blur then
        pcall(function() blur.EffectMaterial = nil end)
        pcall(function() blur:SetEffectMaterial(nil) end)
        pcall(function() blur.Visibility = 0 end)
        pcall(function() blur.RenderOpacity = 1.0 end)
    end

    local wtsc = find_desc(base, "WorldToScreenDrawCanvas", 3, true)
    if wtsc == nil then
        print("[AC8-V129] !! WorldToScreenDrawCanvas 未找到，60 帧后重试")
        return false
    end
    C.wtsc = wtsc
    C.maincv = find_desc(base, "MainCanvas", 3, true)
    C.cp = find_desc(wtsc, "ChroniclePersistent", 3)
    C.vicon  = find_desc(wtsc, "VelocityIcon", 12, true)
    C.vel    = find_desc(wtsc, "Velocity", 12, true)
    C.whisky = find_desc(wtsc, "WhiskyMarkPanel", 12, true)
    if C.whisky ~= nil then
        pcall(function() C.whisky:SetRenderScale({ X = 1.0, Y = 1.0 }) end)
    end
    C.ts     = find_desc(wtsc, "SpeedTachometerCenterPanel", 14, true)
    C.ta     = find_desc(wtsc, "AltitudeTachometerCenterPanel", 14, true)
    C.radar  = collect_radar(C.maincv)
    if #C.radar > 0 then
        -- 锚点优先选"可见"的那个
        for _, w in ipairs(C.radar) do
            local v = get_field(w, "Visibility")
            if v == nil or v == 0 or v == 3 or v == 4 then C.radar_main = w; break end
        end
        if C.radar_main == nil then C.radar_main = C.radar[1] end
    end

    -- ① 残留清扫+剖面捕获（在任何钉子之前）
    sweep_residual(false)
    match_tach_k()
    print(string.format("[AC8-V129] 机型指纹: %s", TACH_K_MATCH))

    -- ② 建钉子表（顺序即日志顺序）
    table.insert(C.pins, { obj = C.wtsc,   x = TW_X, y = TW_Y, tag = "WTSCanvas(副武器层)" })
    if C.cp ~= nil and SHIFT_VIA_PERSISTENT then
        table.insert(C.pins, { obj = C.cp, x = R0_X, y = R0_Y, tag = "ChroniclePersistent(中央HUD)+K", dyn = true })
    end
    if C.maincv ~= nil then
        table.insert(C.pins, { obj = C.maincv, x = MAIN_X, y = MAIN_Y, tag = "MainCanvas(雷达+弹药)" })
    end
    if C.vicon  ~= nil then table.insert(C.pins, { obj = C.vicon,  x = VICON_BASE_X, y = VICON_BASE_Y, tag = "VelocityIcon(基准)", slow = true }) end
    if C.vel    ~= nil then table.insert(C.pins, { obj = C.vel,    x = VELOCITY_X + VELOCITY_NUDGE_X, y = VELOCITY_Y + VELOCITY_NUDGE_Y, tag = "Velocity(主武器准星)", slow = true }) end
    if C.whisky ~= nil then table.insert(C.pins, { obj = C.whisky, x = WHISKY_X, y = WHISKY_Y, tag = "WhiskyMarkPanel(W)" }) end
    if C.ts     ~= nil then table.insert(C.pins, { obj = C.ts,     x = TACH_PULL + TACH_KX + TACH_NUDGE_X, y = TACH_Y + TACH_KY + TACH_NUDGE_Y, tag = "SpeedTachometer(左)+机型K" }) end
    if C.ta     ~= nil then table.insert(C.pins, { obj = C.ta,     x = -TACH_PULL + TACH_KX + TACH_NUDGE_X, y = TACH_Y + TACH_KY + TACH_NUDGE_Y, tag = "AltitudeTachometer(右)+机型K" }) end
    for _, it in ipairs(RESET_LIST) do
        local w = find_desc(wtsc, it.pat, 12)
        table.insert(C.pins, { obj = w, x = it.x, y = it.y, tag = "RESET:" .. it.key, slow = true })
    end

    -- ③ 首次应用（读回验证 + 打印，仅此一次）
    for _, pin in ipairs(C.pins) do
        if pin.obj ~= nil and not pin.dyn then
            set_rt(pin.obj, pin.x, pin.y, pin.tag, false)
        end
    end
    if C.cp ~= nil and SHIFT_VIA_PERSISTENT then
        set_rt(C.cp, R0_X + cal.kx, R0_Y + cal.ky, "ChroniclePersistent(中央HUD)+K", false)
    else
        -- 没有 cp 的老行为回退
        table.insert(C.pins, { obj = C.wtsc, x = CANVAS_X, y = CANVAS_Y, tag = "WTSCanvas(老行为回退)" })
        print("[AC8-V129] !! 无 ChroniclePersistent -> 回退 v102 老行为（无机型补偿）")
    end
    if FIX_RADAR_CIRCLE then
        for _, w in ipairs(C.radar) do
            set_rt(w, 0, RADAR_CIRCLE_DY, "RADARCIRCLE:" .. short_name(w), false)
        end
        print(string.format("[AC8-V129] 雷达圆共 %d 个节点，已全部钉 (0,%d)", #C.radar, RADAR_CIRCLE_DY))
    end
    pcall(function() wtsc.Visibility = 0 end)
    pcall(function() wtsc.RenderOpacity = 1.0 end)
    if C.maincv ~= nil then
        pcall(function() C.maincv.Visibility = 0 end)
        pcall(function() C.maincv.RenderOpacity = 1.0 end)
    end

    -- ④ 只读 GEO 快照（一次性诊断）
    print("[AC8-V129] === GEO 快照（实测中心，单位）===")
    for _, e in ipairs({ { C.radar_main, "雷达圆(锚点)" }, { C.ts, "时速表左" },
                         { C.ta, "高度表右" }, { C.vel, "准星" }, { C.whisky, "W" } }) do
        local c = abs_center(e[1])
        if c ~= nil then
            print(string.format("[AC8-V129]   %-12s center=(%.0f,%.0f) via=%s", e[2], c.x, c.y, c.via))
        else
            print(string.format("[AC8-V129]   %-12s 读不到（可能未绘制）", e[2]))
        end
    end

    -- ⑤ 启动锚定：K 起点取机型表（有就抄近路，没有就 0 起量）
    cal.kx, cal.ky = 0, 0
    local fkx, fky = fallback_k(cal.cur_fp)
    if fkx ~= nil then
        cal.kx, cal.ky = fkx, fky
        print(string.format("[AC8-V129] 机型表起点 K=(%d,%d)（锚定会在此基础上自纠）", fkx, fky))
    end
    cal.gain = CAL_GAIN0; cal.iter = 0; cal.scale = nil; cal.pex = nil; cal.pey = nil
    cal.warm = 3
    cal.active = true
    assert_pins(true)   -- v108: 含慢车道（准星等世界投影元素）

    C.ready = true
    print("[AC8-V129] === 发现完成，进入「缓存+廉价断言」模式；K 由运行时锚定 ===")
    return true
end

-- ============ 缓存活性校验（每 45 帧一次，成本=几个 pcall） ============
local function validate()
    for _, e in ipairs({ C.keep, C.base, C.wtsc, C.cp }) do
        if e ~= nil then
            local ok, v = pcall(function() return e:get_full_name() end)
            if not ok or v == nil or v == "<no full_name>" then
                print("[AC8-V129] !! HUD 缓存失效（控件已销毁），重新发现")
                C.ready = false
                return false
            end
        end
    end
    return true
end

-- ============ 机型变化检查（每 240 帧一次，成本=1 次 pawn 调用） ============
local function fingerprint_check()
    local nm = pawn_full_name()
    if nm == nil then return end
    if cal.cur_fp == nil then
        cal.cur_fp = nm
        print(string.format("[AC8-V129] 机型指纹 = %s", nm))
        return
    end
    if nm ~= cal.cur_fp then
        print(string.format("[AC8-V129] ★ 机型切换：%s -> %s（重新锚定 K）", cal.cur_fp, nm))
        cal.cur_fp = nm
        cal.kx, cal.ky = 0, 0
        local fkx, fky = fallback_k(nm)
        if fkx ~= nil then cal.kx, cal.ky = fkx, fky end
        cal.gain = CAL_GAIN0; cal.iter = 0; cal.scale = nil; cal.pex = nil; cal.pey = nil
        cal.warm = 3
        cal.active = true
        assert_pins()
    end
end

-- v126 修正：停动画相关代码整段前移到帧循环之前，且**自包含**——只用全局
--   （uevr/print/pcall/string）与下面 6 个前向声明的 local，绝不引用后定义的
--   local。v126 初版实锤教训（截图 Last Script Error: exception in
--   on_post_engine_tick: attempt to call a nil value）：初版只把开关前移了，
--   实现仍留在帧循环之后——cam_get_pcm() 内部调用更下方(1127行)才声明的
--   cam_get_pawn ⇒ 闭包里它是全局 nil ⇒ on_frame 每帧抛异常 ⇒
--   StopAllCameraAnims 从未执行 ⇒ "动画还在"的直接原因。
local CAM_ANIM_KILL = true     -- 逃逸开关：false = 不插手 PlayerCameraManager
local CAM_KILL_EVERY = 1       -- v126：每帧停一次（防动画被停后又被反复播回）
local cam_kill_oklog  = false  -- PM 成功日志只打一次
local cam_kill_faillog = false -- PM 未就绪提示只打一次
local cam_kill_path   = ""     -- 记录 PM 获取路径（只用于日志）
local function cam_get_pawn()
    local ok, p = pcall(function() return uevr.api:get_local_pawn(0) end)
    if ok and p ~= nil then return p end
    local ok2, p2 = pcall(function() return uevr.api:get_player_pawn() end)
    if ok2 and p2 ~= nil then return p2 end
    return nil
end
-- 每帧调用：找到 PlayerCameraManager 并停掉全部相机动画/震屏。
-- 返回 true=PM 拿到（并已尝试停止）；false=PM 暂不可得（菜单/加载中，稍后重试）。
local function cam_kill_anims()
    local pm = nil
    pcall(function()
        local a = uevr and uevr.api
        if a == nil then return end
        local ctrl = nil
        local pawn = cam_get_pawn()
        if pawn ~= nil then
            pcall(function() ctrl = pawn.Controller end)
            if ctrl == nil then
                pcall(function() ctrl = pawn:get_Controller() end)
                if ctrl ~= nil then cam_kill_path = "pawn:get_Controller" end
            else
                cam_kill_path = "pawn.Controller"
            end
        end
        if ctrl == nil then
            pcall(function()
                if a.get_player_controller ~= nil then ctrl = a:get_player_controller() end
            end)
            if ctrl ~= nil then cam_kill_path = "api:get_player_controller" end
        end
        if ctrl == nil then return end
        pcall(function() pm = ctrl.PlayerCameraManager end)
        if pm == nil then pcall(function() pm = ctrl:get_PlayerCameraManager() end) end
    end)
    if pm == nil then return false end
    -- UE5 的 StopAllCameraAnims(bool bImmediate) / StopAllCameraShakes(bool)
    -- 需要显式参数；v126 初版调用没带参数 ⇒ pcall 静默失败 ⇒ 等于没停。
    pcall(function() pm:StopAllCameraAnims(true) end)
    pcall(function() pm:StopAllCameraShakes(true) end)
    return true
end

local function is_flight_active()
    if not C.ready or C.keep == nil then return false end
    local ok, inv = pcall(function() return C.keep:IsInViewport() end)
    if not ok or inv ~= true then return false end
    local ok2, vis = pcall(function() return C.keep:GetVisibility() end)
    if ok2 and (vis == 1 or vis == 2) then return false end -- 1=Collapsed, 2=Hidden
    return true
end

-- ============ 帧循环（热路径：先取模，后干活） ============
local frame_n = 0
local retry_gap = 60      -- 未就绪时的重试间隔：60 -> 120 -> 240 -> 600 封顶（菜单里不刷搜索）
local last_pawn_obj = nil

local function on_frame()
    frame_n = frame_n + 1

    -- Pawn 变化检测（出击 / 换关 / 重生）：出击瞬间立刻重置重试计时，秒级加载HUD（彻底消除10秒延迟）
    local current_pawn = cam_get_pawn()
    if current_pawn ~= last_pawn_obj then
        last_pawn_obj = current_pawn
        if current_pawn ~= nil then
            retry_gap = 1
        end
    end

    if not is_flight_active() then
        if C.ready then
            print("[AC8-V129] !! 退出飞行状态，重置HUD缓存")
            C.ready = false
            C.keep = nil; C.base = nil; C.wtsc = nil; C.maincv = nil; C.cp = nil
            C.ts = nil; C.ta = nil; C.vicon = nil; C.vel = nil; C.whisky = nil
            C.radar = {}; C.radar_main = nil; C.pins = {}
        end
        if frame_n % retry_gap == 0 then
            if discover() then
                retry_gap = 60
            else
                retry_gap = math.min(retry_gap * 2, 600)
            end
        end
        return
    end
    if cal.active and (frame_n % CAL_STEP_EVERY == 0) then cal_step() end
    if frame_n % ASSERT_EVERY == 0 then assert_pins() end          -- 快车道：只静态容器
    if frame_n % VALIDATE_EVERY == 0 then if not validate() then return end end
    if frame_n % FINGERPRINT_EVERY == 0 then fingerprint_check() end
    if frame_n % MISSING_RETRY_EVERY == 0 then retry_missing() end
    if frame_n % MONITOR_EVERY == 0 then monitor_profiles() end   -- v118：降频后的布局监控
    if frame_n % HB_EVERY == 0 then
        assert_pins(true)   -- 慢车道：准星等世界投影元素，每 600 帧保底钉一次
        local ax, ay = get_rt_xy(C.cp)
        print(string.format("[AC8-V129] HB frame=%d 快钉=%d 慢钉=%d K=(%.0f,%.0f) 锚定=%s cp.RT=(%s,%s)",
            frame_n, #C.pins + #C.radar, #C.pins, cal.kx, cal.ky,
            cal.active and "进行中" or "已锁定", tostring(ax), tostring(ay)))
    end
    -- v126：动画源头压制（每帧停一次相机 anims/震屏，仅在飞行出击时执行，避免破坏机库相机）
    if CAM_ANIM_KILL and is_flight_active() and frame_n % CAM_KILL_EVERY == 0 then
        local okp = cam_kill_anims()
        if okp and not cam_kill_oklog then
            cam_kill_oklog = true
            print(string.format("[AC8-V129] [CAM] PlayerCameraManager 已找到(%s)，相机动画/震屏压制中（每帧）", cam_kill_path))
        elseif not okp and not cam_kill_faillog then
            cam_kill_faillog = true
            print("[AC8-V129] [CAM] 暂时取不到 PlayerCameraManager（菜单/加载中？），稍后自动重试")
        end
    end
end

-- ============ v119：相机刚性锚定座舱（修正 v118 的世界系偏移 bug） ============
-- UEVR 官方相机回调 on_early_calculate_stereo_view_offset：
--   · 每帧对左右眼各调一次；position/rotation 是"游戏基准相机"（单位=cm）
--   · UEVR 在该回调之后才叠加 HMD 头部跟踪偏移 ⇒ 覆写此处不影响头动
--     （DS-FreeCam / UEVR 官方示例同款机制）
-- v118 缺陷实锤：基准偏移按"世界固定向量"记录（相机位 - pawn位），飞机一转身，
--   座舱位置要绕机体转，相机却钉死在世界上那个点 ⇒ 任何杆量都把视角甩出座舱盖。
-- v119 修正：偏移按**机体本地坐标系**记录，每帧用 pawn 当前旋转转回世界：
--     本地偏移   := LessLess_VectorRotator(相机位 - pawn位, pawn旋转)     世界→机体
--     相机目标位 := pawn位 + GreaterGreater_VectorRotator(本地偏移, pawn旋转) 机体→世界
--     目标角     := pawn角 + 安装角差（捕获时的欧拉差）
--   算子与用法照抄 DS-FreeCam libfreecam.lua（GreaterGreater_VectorRotator =
--   本地→世界向量；LessLess_VectorRotator = 世界→本地向量）。每帧 2 次调用。
local CAM_ANCHOR    = true   -- 逃逸开关：false = 回到原生相机
local CAM_MAX_JUMP  = 120.0  -- 目标与游戏相机位置差上限(cm)：超=模型失配⇒该帧透传
local CAM_MAX_DROT  = 15.0   -- 旋转差上限(度)
local CAM_WARMUP    = 10     -- 稳定帧数：连续这么多帧偏差不超限才开始写（防出生动画瞬移）
local CAM_LOG_EVERY = 600    -- [CAM] 状态行间隔（帧）
-- v126：CAM_ANIM_KILL/CAM_KILL_EVERY/cam_get_pawn/cam_kill_anims 已整段前移到
-- 帧循环之前且自包含（否则 Lua 作用域规则让引用落空=代码从不执行/每帧异常）。
local cam = {
    pawn_id = nil,            -- pawn 标识（v124 起用对象地址，不再用 tostring）
    vobj = nil,               -- 机 Placeholder：v124 起不再跨帧持有 Kismet 返回的向量对象
    vx = 0, vy = 0, vz = 0,   -- 机体本地偏移标量（vx/vy/vz 为唯一有效存储）
    dp = 0, dyaw = 0, dr = 0, -- 安装角差（绕机体三轴，度）
    adx = 0, ady = 0, adz = 0, adp = 0, adyaw = 0, adr = 0, -- 最近一次消除的动画量
    mdx = 0, mdy = 0, mdz = 0, mdp = 0, mdyaw = 0, mdr = 0, -- 自上次日志以来的偏差峰值
    sx = 0, sy = 0, sz = 0, sp = 0, syaw = 0, sr = 0, -- post 回调收到的（动画后）位姿快照
    uax = 0, uay = 0, uaz = 0, uap = 0, uayaw = 0, uar = 0, -- 动画层偏差峰值（post-early）
    pp = 0, py = 0, pr = 0,   -- 当前 pawn 姿态快照（日志用）
    warm = 0, pass_n = 0, warned = false, valid = false, cap_n = 0,
    tx = nil, ty = nil, tz = nil, tp = nil, tyaw = nil, tr = nil, -- 本帧目标（双眼共用）
}
local cam_first_eye = true

local function wrap180(a)
    a = a % 360
    if a > 180 then a = a - 360 elseif a <= -180 then a = a + 360 end
    return a
end

-- KismetMathLibrary CDO（freecam 同款找法：api:find_uobject("Class /Script/...")）
local KM = nil
do
    local ok, cls = pcall(function() return uevr.api:find_uobject("Class /Script/Engine.KismetMathLibrary") end)
    if ok and cls ~= nil then
        local ok2, cdo = pcall(function() return cls:get_class_default_object() end)
        if ok2 and cdo ~= nil then KM = cdo else KM = cls end
    end
end
local function vec_local_to_world(v, r) -- 机体本地向量 -> 世界向量
    if KM == nil then return nil end
    local ok, w = pcall(function() return KM:GreaterGreater_VectorRotator(v, r) end)
    if ok and w ~= nil then return w end
    return nil
end
local function vec_world_to_local(v, r) -- 世界向量 -> 机体本地向量
    if KM == nil then return nil end
    local ok, w = pcall(function() return KM:LessLess_VectorRotator(v, r) end)
    if ok and w ~= nil then return w end
    return nil
end
-- v124：每次现算一个"零向量"再填值，避免跨帧持有 Kismet 返回的 userdata
-- （旧做法缓存返回的 Vector3 跨帧使用，下一帧 GreaterGreater 对失效对象调用
--   失败 ⇒ cam.valid=false ⇒ 每帧重捕 ⇒ warmup 永远清零 ⇒ 相机覆写从未发生过）
local function vec_make_zero(ref)
    local z = ref - ref
    return z
end
-- v124：pawn 稳定身份（UEVR 每次 get_local_pawn 返回新的 userdata 包装器，
-- tostring 拿到的是包装器地址、每帧都不同 ⇒ 误判"换pawn"每帧重捕）
local function cam_pawn_id(pawn)
    local ok, a = pcall(function() return pawn:get_address() end)
    if ok and a ~= nil then return "addr:" .. tostring(a) end
    local ok2, n = pcall(function() return pawn:get_fname():to_string() end)
    if ok2 and n ~= nil then return "fname:" .. tostring(n) end
    return nil
end
-- v126：cam_get_pcm / cam_kill_anims / cam_get_pawn 的实现已整段前移到帧循环
--   之前（见"停动画相关前向声明"段）。初版把它们拆散放在这里，闭包互相引用
--   后定义的 local，导致每帧异常。此处只留 pawn 几何工具。

local function pawn_loc_rot(pawn)
    local ok, loc = pcall(function() return pawn:K2_GetActorLocation() end)
    if not ok or loc == nil then return nil end
    local rot = nil
    pcall(function() rot = pawn:K2_GetActorRotation() end)
    if rot == nil then pcall(function() rot = pawn:GetActorRotation() end) end
    if rot == nil then return loc, nil, 0, 0, 0 end
    local p1 = rot.Pitch or rot.x or 0
    local y1 = rot.Yaw  or rot.y or 0
    local r1 = rot.Roll  or rot.z or 0
    return loc, rot, p1, y1, r1
end

local function rot_fields(rotation) -- 回调旋转对象的欧拉读数（兼容两种字段名）
    return (rotation.Pitch or rotation.x or 0),
           (rotation.Yaw  or rotation.y or 0),
           (rotation.Roll  or rotation.z or 0)
end
local function set_rot(rotation, p, y, r) -- 写回转调旋转对象（字段名两种都试）
    pcall(function() rotation.Pitch = p end); pcall(function() rotation.x = p end)
    pcall(function() rotation.Yaw  = y end); pcall(function() rotation.y = y end)
    pcall(function() rotation.Roll = r end); pcall(function() rotation.z = r end)
end

local function cam_capture(pawn, position, rotation, why)
    local loc, rot, p1, y1, r1 = pawn_loc_rot(pawn)
    if loc == nil or rot == nil or KM == nil then
        if not cam.warned then
            cam.warned = true
            print("[AC8-V129] [CAM] 取不到 pawn 旋转或 KismetMathLibrary 算子不可用——相机锚定停用，画面为原生相机")
        end
        CAM_ANCHOR = false
        return
    end
    local vl = vec_world_to_local(position - loc, rot)
    if vl == nil then
        if not cam.warned then
            cam.warned = true
            print("[AC8-V129] [CAM] LessLess_VectorRotator 调用失败——相机锚定停用，画面为原生相机")
        end
        CAM_ANCHOR = false
        return
    end
    cam.vobj = nil       -- v124：不跨帧持有 Kismet 返回的 Vector3 userdata（会被回收/失效）
    cam.vx, cam.vy, cam.vz = vl.x, vl.y, vl.z
    local rp, ry, rr = rot_fields(rotation)
    cam.dp   = wrap180(rp - p1)
    cam.dyaw = wrap180(ry - y1)
    cam.dr   = wrap180(rr - r1)  -- 仅记录：v120 起 roll 通道透传不写（防污染 HUD 投影）
    cam.pawn_id = cam_pawn_id(pawn)  -- v124：稳定身份（对象地址），不再用 tostring
    cam.valid = true
    cam.warm = 0
    cam.pass_n = 0
    cam.cap_n = cam.cap_n + 1
    -- v124 自诊断：捕获次数异常=身份判定仍失效（warmup 永远清零⇒锚定从未生效）
    if cam.cap_n == 20 then
        print("[AC8-V129] [CAM] !!! 已重捕 20 次仍无状态行输出=身份判定仍在误触，锚定未生效，请回报日志")
    end
    cam.tx = nil -- 捕获帧不写，等 warmup 通过
    print(string.format("[AC8-V129] [CAM] 基准已确立（%s） 机体本地偏移=(%.1f,%.1f,%.1f)cm 安装角差=(%.1f,%.1f,%.1f)度",
        why, cam.vx, cam.vy, cam.vz, cam.dp, cam.dyaw, cam.dr))
end

local cam_log_n = 0
local function on_cam_stereo(device, view_index, world_to_meters, position, rotation, is_double)
    if not CAM_ANCHOR or not is_flight_active() then
        cam.valid = false
        cam.warm = 0
        cam.tx = nil
        return
    end
    if cam_first_eye then
        -- 左眼：查 pawn、算本帧目标（每帧一次，双眼共用）
        cam_first_eye = false
        local pawn = cam_get_pawn()
        if pawn ~= nil then
            local pid = cam_pawn_id(pawn)
            if (not cam.valid) or (pid ~= nil and pid ~= cam.pawn_id) then
                cam_capture(pawn, position, rotation, "首次/换pawn")
            else
                local loc, prot, p1, y1, r1 = pawn_loc_rot(pawn)
                if loc ~= nil and prot ~= nil then
                    -- v124：每帧现造偏移向量（不跨帧持有 Kismet 返回值）
                    local vb = vec_make_zero(position)
                    vb.x, vb.y, vb.z = cam.vx, cam.vy, cam.vz
                    local w = vec_local_to_world(vb, prot)
                    if w == nil then
                        cam.valid = false
                    else
                        local tv = loc + w
                        local tx, ty, tz = tv.x, tv.y, tv.z
                        local rp, ry, rr = rot_fields(rotation)  -- 原生座舱 roll 读数（约0）
                        local tp   = wrap180(p1 + cam.dp)
                        local tyaw = wrap180(y1 + cam.dyaw)
                        -- v120：roll 通道禁用——v119 曾把 pawn 滚转角写进基准相机，而座舱原生
                        -- roll 恒为 0（倾斜的是世界不是相机）。HUD 投影基准会采样 view
                        -- rotation，横滚时注入的 roll≠0 会把 HUD 带歪（HUD 朝向有平滑延迟，
                        -- 表现为"概率倾斜、数秒回正"）。这里直接透传原生 roll（≈0），
                        -- 与 v108 基线完全一致，HUD 永不受污染。
                        local tr   = rr
                        local jump = math.abs(position.x - tx) + math.abs(position.y - ty) + math.abs(position.z - tz)
                        local drot = math.abs(wrap180(rp - tp)) + math.abs(wrap180(ry - tyaw)) + math.abs(wrap180(rr - tr))
                        if jump > CAM_MAX_JUMP or drot > CAM_MAX_DROT then
                            -- 模型失配（出生/过场动画/座舱挂点与 pawn 不同体）⇒ 该帧透传保命
                            cam.pass_n = cam.pass_n + 1
                            cam.warm = 0
                            cam.tx = nil
                            if cam.pass_n > 1800 then -- 连续 ~30 秒失配
                                print("[AC8-V129] [CAM] 连续失配（座舱模型与 pawn 不同体）——锚定自动停用，画面为原生相机")
                                CAM_ANCHOR = false
                            end
                        else
                            cam.pass_n = 0
                            cam.warm = cam.warm + 1
                            -- 记录本帧消除的动画量（诊断用）
                            cam.adx, cam.ady, cam.adz = position.x - tx, position.y - ty, position.z - tz
                            cam.adp   = wrap180(rp - tp)
                            cam.adyaw = wrap180(ry - tyaw)
                            cam.adr   = wrap180(rr - tr)
                            -- 偏差峰值（自上次日志以来）与 pawn 姿态快照
                            if math.abs(cam.adx)   > cam.mdx   then cam.mdx   = math.abs(cam.adx)   end
                            if math.abs(cam.ady)   > cam.mdy   then cam.mdy   = math.abs(cam.ady)   end
                            if math.abs(cam.adz)   > cam.mdz   then cam.mdz   = math.abs(cam.adz)   end
                            if math.abs(cam.adp)   > cam.mdp   then cam.mdp   = math.abs(cam.adp)   end
                            if math.abs(cam.adyaw) > cam.mdyaw then cam.mdyaw = math.abs(cam.adyaw) end
                            if math.abs(cam.adr)   > cam.mdr   then cam.mdr   = math.abs(cam.adr)   end
                            cam.pp, cam.py, cam.pr = p1, y1, r1
                            -- v126：删去 v121/v122 的基准拖动（慢速重锚/持久性判定）——
                            -- 用户实测 lerp 会把机头动画吸回基准（动画复活），且没解决侧移。
                            -- v120 干净态：基准只在进场/换 pawn 时捕获，之后永不改动；
                            -- 侧移若残留由源头停 anims（on_frame）+ post 只读探针定位。
                            cam.tx, cam.ty, cam.tz = tx, ty, tz
                            cam.tp, cam.tyaw, cam.tr = tp, tyaw, tr
                        end
                    end
                else
                    cam.valid = false
                end
            end
        end
        cam_log_n = cam_log_n + 1
        if cam.valid and cam_log_n % CAM_LOG_EVERY == 0 then
            -- v126：nil 守卫——tx/sx 未就绪时打 n/a，绝不再做 nil 算术
            -- （v125 报错 arithmetic on a nil value(field 'tx') 就是这里）
            local layer = "n/a(未就绪)"
            if cam.tx ~= nil and cam.sx ~= nil then
                layer = string.format("(%.1f,%.1f,%.1f)cm (%.2f,%.2f,%.2f)度",
                    cam.sx - cam.tx, cam.sy - cam.ty, cam.sz - cam.tz,
                    wrap180(cam.sp - cam.tp), wrap180(cam.syaw - cam.tyaw), wrap180(cam.sr - cam.tr))
            end
            print(string.format("[AC8-V129] [CAM] 状态 动画量=(%.1f,%.1f,%.1f)cm 角度=(%.2f,%.2f,%.2f)度 动画层(实测)=%s",
                cam.adx, cam.ady, cam.adz, cam.adp, cam.adyaw, cam.adr, layer))
            print(string.format("[AC8-V129] [CAM] 峰值 |Δ|pos=(%.1f,%.1f,%.1f)cm |Δ|ang=(%.2f,%.2f,%.2f)度 层峰=(%.1f,%.1f,%.1f)cm (%.2f,%.2f,%.2f)度 基准=(%.0f,%.0f,%.0f) pawn=(%.0f,%.0f,%.0f) warm=%d pass=%d 捕获=%d",
                cam.mdx, cam.mdy, cam.mdz, cam.mdp, cam.mdyaw, cam.mdr,
                cam.uax, cam.uay, cam.uaz, cam.uap, cam.uayaw, cam.uar,
                cam.vx, cam.vy, cam.vz, cam.pp, cam.py, cam.pr, cam.warm, cam.pass_n, cam.cap_n))
            cam.mdx, cam.mdy, cam.mdz = 0, 0, 0
            cam.mdp, cam.mdyaw, cam.mdr = 0, 0, 0
            cam.uax, cam.uay, cam.uaz = 0, 0, 0
            cam.uap, cam.uayaw, cam.uar = 0, 0, 0
        end
    end
    -- 双眼都写（UEVR 每帧重置 position）；warmup 未过/刚捕获 = 透传不写
    if cam.valid and cam.warm >= CAM_WARMUP and cam.tx ~= nil then
        position.x, position.y, position.z = cam.tx, cam.ty, cam.tz
        set_rot(rotation, cam.tp, cam.tyaw, cam.tr)
    end
end

local function cam_reset_first_eye()
    cam_first_eye = true
end

-- v123/v124：post 回调曾在此二次覆写"按住动画"——v124 实锤错误：
-- post 收到的是**叠加 HMD 头动之后的最终视图**，在这里写绝对坐标会把头部
-- 跟踪一起干掉（用户实测：转头无效、画面钉死在头显里；日志里所谓"动画层"
-- 几十上百 cm/55° 其实是头部运动而非动画）。post 只读不写，保留函数仅为
-- 将来做"增量 delta 施加"留接口（需先能读到 HMD 位姿相减，暂不可行）。
local CAM_POST_WRITE = false -- 逃逸开关：false = post 完全不碰画面（当前唯一正确值）
local function on_cam_stereo_post(device, view_index, world_to_meters, position, rotation, is_double)
    if not CAM_ANCHOR or not is_flight_active() then return end
    -- 快照永远做（只读探针）：侧移诊断要看 post 收到的最终位姿 与 early 刚性目标 之差
    local qp, qy, qr = rot_fields(rotation)
    cam.sx, cam.sy, cam.sz = position.x, position.y, position.z
    cam.sp, cam.syaw, cam.sr = qp, qy, qr
    if not CAM_POST_WRITE then return end
    if cam.valid and cam.warm >= CAM_WARMUP and cam.tx ~= nil then
        local ux = position.x - cam.tx
        local uy = position.y - cam.ty
        local uz = position.z - cam.tz
        local up   = wrap180(qp - cam.tp)
        local uyaw = wrap180(qy - cam.tyaw)
        local ur   = wrap180(qr - cam.tr)
        if math.abs(ux)   > cam.uax   then cam.uax   = math.abs(ux)   end
        if math.abs(uy)   > cam.uay   then cam.uay   = math.abs(uy)   end
        if math.abs(uz)   > cam.uaz   then cam.uaz   = math.abs(uz)   end
        if math.abs(up)   > cam.uap   then cam.uap   = math.abs(up)   end
        if math.abs(uyaw) > cam.uayaw then cam.uayaw = math.abs(uyaw) end
        if math.abs(ur)   > cam.uar   then cam.uar   = math.abs(ur)   end
        position.x, position.y, position.z = cam.tx, cam.ty, cam.tz
        set_rot(rotation, cam.tp, cam.tyaw, cam.tr)
    end
end
-- ============ 启动 ============
print("[AC8-V129] === 首次发现 ===")
local ok0, err0 = pcall(discover)
if not ok0 then print("[AC8-V129] !!!! discover 异常: " .. tostring(err0)) end

local function register_tick()
    local cbs = uevr and uevr.sdk and uevr.sdk.callbacks
    if cbs and cbs.on_post_engine_tick then
        local ok2, e2 = pcall(function() cbs.on_post_engine_tick(on_frame) end)
        if ok2 then print("[AC8-V129] tick 注册成功（热循环已启用）"); return true end
        print("[AC8-V129] tick 注册失败: " .. tostring(e2))
    end
    return false
end
local okr, errr = pcall(register_tick)
if not okr then print("[AC8-V129] tick 注册异常: " .. tostring(errr)) end

-- v119：相机刚性锚定（UEVR 官方相机回调；渲染前最后一刻覆写基准相机）
local function register_cam()
    local cbs = uevr and uevr.sdk and uevr.sdk.callbacks
    if cbs == nil then return false end
    local okp, ep = pcall(function() cbs.on_pre_engine_tick(cam_reset_first_eye) end)
    if not okp then print("[AC8-V129] [CAM] pre_tick 注册失败: " .. tostring(ep)) end
    if cbs.on_early_calculate_stereo_view_offset ~= nil then
        local okc, ec = pcall(function() cbs.on_early_calculate_stereo_view_offset(on_cam_stereo) end)
        if okc then
            print("[AC8-V129] [CAM] 相机刚性锚定已启用（early 回调；逃逸开关 CAM_ANCHOR）")
        else
            print("[AC8-V129] [CAM] early 相机回调注册失败: " .. tostring(ec))
        end
    else
        print("[AC8-V129] [CAM] 本版 UEVR 无 on_early_calculate_stereo_view_offset，相机锚定不可用")
    end
    if cbs.on_post_calculate_stereo_view_offset ~= nil then
        local okc2, ec2 = pcall(function() cbs.on_post_calculate_stereo_view_offset(on_cam_stereo_post) end)
        if okc2 then
            print("[AC8-V129] [CAM] post 回调已注册为只读探针（不写画面：post含HMD头动，写了会杀头动）")
        else
            print("[AC8-V129] [CAM] post 相机回调注册失败: " .. tostring(ec2))
        end
    else
        print("[AC8-V129] [CAM] 本版 UEVR 无 post 回调，动画层无法二次覆写（仅 early）")
    end
    return true
end
local okc2, errc2 = pcall(register_cam)
if not okc2 then print("[AC8-V129] [CAM] 注册异常: " .. tostring(errc2)) end

print("[AC8-V129] ------------------------------------------------------------")
print("[AC8-V129] v108 = v107 + 准星闪烁修复 + 准星微调旋钮")
print("[AC8-V129]  1) 准星(Velocity)/VelocityIcon/GunReticle 等世界投影元素移入慢车道：")
print("[AC8-V129]     只在发现时+每600帧钉一次，热循环(20帧)不再和游戏每帧抢位置")
print("[AC8-V129]     => 治'跳动闪烁'；静态容器(cp/磁带/雷达/W)仍20帧断言，位置不受影响")
print("[AC8-V129]  2) 准星微调：VELOCITY_NUDGE_X/Y（每2单位=1px）")
print("[AC8-V129]     实测(截图09:21)：W标(1899,982)、准星环(1892,1027) -> 环比W低45单位")
print("[AC8-V129]     默认 (6,-46) = 环上移与W重叠；想归中屏幕正中可用 (27,43)")
print("[AC8-V129]  3) 机型补偿 K 保持 v107 的相对锚定；几何通道失效则2秒后认输保持现状")
print("[AC8-V129] 逃生门：FORCE_K_X/Y 非 0 = 强制补偿，跳过自动锚定")
print("[AC8-V129] v109 = v108 + 机型指纹磁带补偿（几何锚定失效时的兜底）")
print("[AC8-V129]  4) 机型补偿 fallback：几何通道全灭时，用 sweep 读到的原生残留 RT 当机型指纹")
print("[AC8-V129]     (F-18=(689,630)->K(0,0)；F-16=(1026,938)->K(-330,-174) 两轮实测)。v110 实测：")
print("[AC8-V129]     F-16 该残留层清零后会被游戏恢复（sweep 对其无效但无害）——指纹匹配不受影响")
print(string.format("[AC8-V129]     补偿只叠到速度/高度磁带面板，不影响 W/准星/雷达。当前: %s", TACH_K_MATCH))
print("[AC8-V129]     新机型漂移时：日志会打 [PROF] 剖面（未清零层RT和 S）——发那几行即可；")
print("[AC8-V129]     S非0=RT层型(可自动抵消)；S≈0但有偏移=slot层型，给 TACH_K_TABLE 加一行")
print("[AC8-V129] v119~v120 = 相机刚性锚定(机体本地系) + roll透传修HUD歪斜")
print("[AC8-V129]   v120 = 当前基线：位置锚定/pitch/yaw/头动/HUD钉固全部验收过")
print("[AC8-V129] v121~v125（基准拖动/post覆写/20帧停anims）全部推翻：")
print("[AC8-V129]   lerp吸回动画、post写杀死头动、v125停anims因Lua作用域bug从未执行")
print("[AC8-V129] v126 = v120 干净态 + 修两个'从未执行'的bug（截图报错实锤）")
print("[AC8-V129]   ①停anims代码引用后声明的local=>每帧异常、从未跑过=>整段前移自包含")
print("[AC8-V129]   ②StopAllCameraAnims 补 UE5 必需的 bool 参数（没带=pcall静默失败）")
print("[AC8-V129]   侧移对策：每帧 StopAllCameraAnims 掐源头；post只读探针出数据")
print("[AC8-V129] 基准进场/换pawn捕获后永不动；头动不受影响；逃逸开关CAM_ANCHOR")
print("[AC8-V129] ------------------------------------------------------------")
print("[AC8-V129] v127~v128 FPS 实验（已移出主脚本，详见全局脚本 fps_stat_v1.lua）：")
print("[AC8-V129]   v127: uevr.execute_command 不存在 -> 失败（本 fork 无此 API，防御检查拦下）")
print("[AC8-V129]   v128: uevr.api:execute_command 实锤路径 -> exec 成功但头显无显示")
print("[AC8-V129]         结论：exec 链路已通，疑点在引擎侧（stats 剥离 / 非 HUD 捕获层）")
print("[AC8-V129]   v129 = v126 干净态：主脚本不再携带 FPS 功能，其余零改动")
print("[AC8-V129] ------------------------------------------------------------")
print("[AC8-V129] SCRIPT DONE")
