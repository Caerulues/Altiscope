# Volanta 应用界面与 Tracking（飞行追踪）详解

> **资料范围** ：本文依据 Volanta 官方网站、公开网页版、Orbx 官方产品页、Xbox 官方使用指南，以及开发者发布在 App Store / Google Play 的应用说明与截图整理。资料核对日期为 **2026 年 9 月 26 日** 。桌面端、网页端、移动端和 Xbox 端的功能范围并不完全一致；界面文字、图标位置也可能随版本、窗口宽度和账号权限变化。

## 一、Volanta 是什么

### 1. 产品定位

**Volanta** 是 Orbx 面向飞行模拟用户开发的飞行追踪、地图、日志和社区应用。它把来自 Microsoft Flight Simulator、X-Plane、Prepar3D、DCS、FlightGear 等模拟器的飞行数据集中到同一账户中，并围绕一张持续存在的航空地图组织界面。官方把这种低准备成本的使用方式称为 **“get in and fly”**：只要桌面客户端正在运行并成功连接模拟器，追踪可以自动开始，不要求用户在每次起飞前手动创建一份完整记录。（来源：[Volanta Features](https://volanta.app/features/)、[Orbx Direct 产品页](https://orbxdirect.com/product/volanta)）

### 2. 界面的核心思想

**地图不是 Volanta 的一个普通栏目，而是大部分页面共用的底层工作区。** 官方明确说明，几乎所有页面都以全屏地图为基础；机场、航路点、航路和在线航班由 GPU 渲染，以便在同一画面中容纳大量对象。（来源：[Volanta Features — Map](https://volanta.app/features/)）

因此，理解 Volanta 时不宜把它想成“侧边栏加若干表单”的传统日志软件。更准确的结构是：

```text
应用外壳
├─ 顶部或主导航：Map / Flights / Aircraft / Activities / Schedules …
├─ 全屏地图：机场、航路、航点、天气、在线流量、自己的航迹
├─ 左侧上下文面板：当前选中的航班、机场、飞机或历史记录
├─ 右侧地图工具：流量筛选、图层、显示方式、天气
└─ 账户与连接状态：UTC 时间、用户、模拟器/网络连接、通知
```

这里的面板内容会随用户当前选中的对象变化，而地图通常保持在背景中。这种结构让“查看当前飞行”“检查机场”“回看历史航班”和“观察其他在线飞行”共享同一套空间语境。

## 二、整体视觉与页面骨架

### 1. 视觉风格

**Volanta 以深色界面为主** ，地图采用低亮度底图，信息面板使用接近黑色或深灰色的层级，重要操作和选中状态则使用紫色、蓝紫色或较高亮度的线条。这样处理的主要结果是：

1. 航迹、飞机图标、机场点位和天气色块比底图更突出。
2. 长时间与飞行模拟器并排使用时，界面不会像大面积白色面板那样刺眼。
3. 紫色强调色把“自己的航班、主要按钮、已选择项目”与普通在线流量区分开。

以上颜色和层级来自官方商店截图及官方宣传图的直接观察；具体色值并未在公开文档中披露。（截图来源：[Google Play 上的 Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)、[Volanta 官方功能页](https://volanta.app/features/)）

### 2. 主导航

桌面版公开截图中常见的一级入口包括 **Map、Flights、Aircraft、Activities、Schedules** 。不同版本会增减栏目，窄窗口或移动端会把部分入口折叠为底部导航、图标或菜单，因此不应把某一张旧截图中的栏目顺序视为永久不变。（来源：[Orbx 官方 Volanta 发布帖](https://forum.orbxdirect.com/topic/201295-introducing-volanta-your-personal-flight-tracker/)、[Orbx Direct 产品页](https://orbxdirect.com/product/volanta)）

这些入口分别承担以下任务：

| 区域 | 主要对象 | 典型内容 | 与 Tracking 的关系 |
|---|---|---|---|
| **Map** | 当前世界状态 | 地图、在线流量、机场、天气、图层 | 当前航班追踪的主要画布 |
| **Flights** | 单次飞行记录 | 当前航班、历史航班、航线、统计、截图和笔记 | 保存并回看 Tracking 产生的数据 |
| **Aircraft** | 持续存在的机体 | 注册号、当前位置、飞行历史、累计时间和统计 | Tracking 会自动匹配或创建机体 |
| **Activities** | 挑战与探索目标 | 国家、机场、活动、Aerocaches 等 | 让飞行记录参与进度计算 |
| **Schedules** | 未来的飞行计划 | 真实航班时刻、筛选、Roster | 可作为下一次 Tracking 的计划来源 |

### 3. 搜索、时间与账户区

公开网页版顶部提供 **Search for airports, flights or users** 搜索框，说明搜索对象至少覆盖机场、航班和用户；界面还显示当前 **UTC/Zulu 时间** 。账户入口通常与头像、设置或订阅状态相邻。搜索结果不是离开地图的新页面，而更接近把目标调入当前地图上下文。（来源：[Volanta Web App](https://fly.volanta.app/)）

## 三、Tracking 的准确含义

### 1. Tracking 不是单独的一张静态表格

**Tracking（飞行追踪）** 在 Volanta 中同时指三个层面：

1. **数据采集过程** ：桌面客户端或 Xbox 工具栏从模拟器获取位置和飞行状态。
2. **实时地图状态** ：自己的飞机、已飞航迹、计划航路、机场和其他流量同时显示在地图上。
3. **活动航班面板** ：显示呼号、机型、起降机场、实时数值、剩余时间、天气、图表等信息。

因此，Tracking 更像一种贯穿应用的活动状态，而不是必须从导航栏进入、用完后再退出的孤立页面。官方“启动 Volanta 后自动追踪”的说明，以及网页版以地图为主、侧面展开航班详情的结构，都支持这种理解。（来源：[Volanta Features — Intelligent Tracking](https://volanta.app/features/)、[Volanta Web App](https://fly.volanta.app/)）

### 2. 数据流

```text
飞行模拟器
   ↓ 位置、姿态、速度、高度、发动机/地面状态等
桌面客户端或 Xbox Volanta 工具栏
   ↓ 识别当前飞行并持续上传
Volanta 账户中的活动航班
   ├─ 本机地图上平滑显示
   ├─ 网页/移动端远程查看
   └─ 飞行结束后转为永久日志与统计
```

公开资料没有列出客户端采集的全部变量，上图中的字段范围仅按界面实际显示的数据归纳。不能据此认定 Volanta 保存了模拟器能够提供的所有遥测量。

## 四、Tracking 主界面的详细构成

### 1. 地图主画布

Tracking 状态下，**地图承担空间定位和进度表达** 。用户通常可以同时看到：

1. **自己的飞机图标** ：显示当前位置和朝向，是当前飞行的视觉焦点。
2. **实际航迹** ：把已经飞过的位置连接为轨迹，用于观察绕飞、等待、偏航和进近路径。
3. **计划航路** ：来自已导入或生成的飞行计划，可与实际航迹并列查看。
4. **航路点与航路** ：在适当缩放级别显示，帮助判断飞机相对计划的位置。
5. **出发与到达机场** ：作为航线两端的锚点；放大机场后可查看更细的机场底图。
6. **其他航空器** ：可来自 Volanta、VATSIM、IVAO、PilotEdge、APOC、AI Traffic 等网络或数据源。
7. **天气及环境覆盖层** ：包括天气图层、昼夜分界和可选卫星底图等。

官方说明支持 **2D 与 3D 地图** ，也支持查看计划航路和完整的 **3D 飞行路径** ；公开网页版则直接列出了当前可切换的网络与显示图层。（来源：[Volanta Premium](https://volanta.app/premium/)、[Volanta Web App](https://fly.volanta.app/)、[App Store 上的 Volanta](https://apps.apple.com/app/volanta/id1633883119)）

### 2. 活动航班标题区

选中自己的活动航班后，航班面板顶部通常先回答“这是谁、驾驶什么、飞往哪里”：

- **呼号或航班号** ，例如 VOL1、JST319。
- **机型代码** ，例如 A320。
- **注册号** ，例如 VH-XXC。
- **运营方或网络身份** ，在相应航班数据可用时显示。
- **出发机场与到达机场** ，同时给出 ICAO / IATA 代码。

这些字段形成航班的身份层；下方的实时遥测、路线和天气都属于这一身份下的具体信息。字段组合来自开发者发布的官方移动端截图和应用说明，桌面端的排版更宽，但信息层次相近。（来源：[Google Play 上的 Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)、[App Store 上的 Volanta](https://apps.apple.com/app/volanta/id1633883119)）

### 3. 核心实时数值

**Tracking 面板最重要的一组信息是六个左右的大号关键数值** 。官方商店截图可观察到以下项目：

| 类别 | 英文界面常见名称 | 表达的含义 |
|---|---|---|
| 飞行状态 | **Altitude** | 当前高度，常用英尺显示 |
| 飞行状态 | **Heading** | 当前航向，以度数显示 |
| 飞行状态 | **Ground Speed** | 相对地面的速度，常用节显示 |
| 进度预测 | **Time Left** | 按当前数据估计的剩余时间 |
| 进度预测 | **Arrival Time / ETA** | 预计抵达时间，通常使用 Zulu 时间 |
| 进度预测 | **Distance Remaining** | 距到达点的剩余距离，常用海里显示 |

部分桌面截图还显示 **Squawk** 和 **Vertical Speed** 等次级数值。它们是否出现取决于当前数据源、页面版本和窗口空间，因此更适合视为补充项，而不是每种设备上固定存在的六宫格内容。（截图来源：[Google Play 上的 Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)）

### 4. 航班详情标签页

活动航班面板会把高频信息放在顶部，把详细内容拆入标签页。公开页面和官方应用说明可确认的主要类别包括：

#### Flight Plan

- 显示计划航路、航路点顺序和航路字符串。
- 计划路线可叠加在地图上，与实际飞行路径比较。
- Volanta 支持通过 **SimBrief** 生成或导入计划；Premium 的 Persistent Flight Plans 会保存过去的 SimBrief 计划。（来源：[Orbx Direct 产品页](https://orbxdirect.com/product/volanta)、[Volanta Premium](https://volanta.app/premium/)）

#### Statistics

- 显示高度、地速等随时间变化的数据。
- 官方移动端截图使用折线/面积图把 **飞行高度** 与 **地形高度** 放在同一时间轴上。
- 图表和大号实时数字共同构成“当前状态 + 变化过程”两层阅读方式。（来源：[Google Play 上的 Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)）

#### Notes、Screenshots 或 Misc

- **Notes** 用于给单次飞行补充文字记录。
- **Screenshots** 用于浏览与该航班关联的截图；云端截图可以带地理位置并显示在地图上。
- 某些移动端版本把不适合放入前两栏的内容归入 **Misc** ，而桌面或网页端可能直接拆成 Notes、Screenshots 等独立标签。（来源：[Volanta Premium](https://volanta.app/premium/)、[App Store 上的 Volanta](https://apps.apple.com/app/volanta/id1633883119)）

### 5. 出发地、目的地与天气

航班详情会并列呈现 **Departure** 与 **Arrival** 机场。官方移动端说明明确提到可查看出发和到达机场以及天气；截图中常见的信息包括机场代码、机场名称、温度、气压、风向/风速和飞行规则类别。这里的设计目的不是替代完整航图或气象简报，而是在追踪画面中提供足够的到达情境。（来源：[Google Play 上的 Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)）

### 6. 地图筛选与图层面板

公开网页版当前把地图设置分成若干组。以下项目来自页面直接暴露的界面文字，而不是对截图的猜测。（来源：[Volanta Web App](https://fly.volanta.app/)）

#### Flight Filters / Networks

- **Volanta** ：可进一步区分 Everyone else、Friends、Teams、Party。
- **VATSIM、IVAO、PilotEdge、APOC** ：显示对应网络上的航空器。
- **AI Traffic** ：显示可获得的模拟器 AI 流量。
- **VATSIM ATC Coverage、IVAO ATC Coverage** ：显示在线管制覆盖。
- **VATSIM FIR Boundaries** ：显示飞行情报区边界。

#### Airports

- **Airports** ：普通机场点位。
- **Helipads** ：直升机场或停机坪点位。

#### Display

- **3D Mode** ：在二维俯视与三维地图表达之间切换。
- **Day/Night Line** ：显示昼夜分界。
- **Screenshots** ：显示带地理位置的航班截图。
- **Satellite Mode** ：切换卫星影像底图。
- **Emergency Planes** ：突出显示处于紧急状态的航空器。
- **Points of Interest** ：显示兴趣点。
- **Stronger Borders** ：增强行政或区域边界的可见性。
- **Show Labels** ：控制航空器标签；页面提示标签会在缩放足够近、不会使地图过度拥挤时出现。

#### 快捷工具

地图边缘还提供 **overlays、layers、weather** 等快捷入口。它们的作用是把高密度设置从主画面收起，需要时再展开，从而让飞行路径始终保持视觉中心。

### 7. Tracking 状态与刷新精度

免费层使用会根据飞机行为变化的 **动态更新频率** 。Premium 的 **Real-Time Tracking** 在机动过程中可每秒更新位置，本地客户端中的视觉更新还可以更快；其他设备会更频繁地接收位置并利用预测路径获得更平滑的移动。用户可以关闭实时追踪，或设置在应用失去焦点、最小化时停止本地或预测更新。（来源：[Volanta Premium — Real-Time Tracking](https://volanta.app/premium/)、[Volanta Xbox Guide](https://volanta.app/console/)）

这意味着地图上飞机图标的“连续移动”不应被理解为模拟器每一帧都完整上传到服务器。实际表现由本地采样、网络更新和客户端插值共同构成；官方没有公开完整算法，后半句属于基于官方刷新说明的技术分析。

## 五、一次飞行中的 Tracking 生命周期

### 1. 未连接或等待模拟器

此时地图仍可用于浏览公开流量、机场和图层，但自己的飞机不会进入活动追踪。桌面端需要确认模拟器已被检测、所需插件已安装，并保证 Volanta 与模拟器处在相同权限级别。网页版自身不能替代桌面采集客户端。（来源：[Volanta Web App — Simulator Connection Guide](https://fly.volanta.app/)）

### 2. 建立连接并自动识别飞行

模拟器开始运行后，Volanta 会尝试自动建立活动航班。若账户中已有与当前信息匹配的飞机，系统会把本次飞行分配给它；否则可以自动创建一架新飞机。这个过程让 Aircraft 页面中的累计时间、位置和历史记录与每次 Tracking 连续起来。（来源：[Volanta Features — Aircraft](https://volanta.app/features/)）

### 3. 地面滑行与起飞

地图在机场尺度上显示自己的位置，实际航迹从地面阶段开始积累。机场、跑道或更细的机场图层是否出现取决于缩放级别、底图和可用的数据连接。Tracking 不只记录空中航段；最终的 **block time** 与 **flight time** 是不同指标，说明系统会区分从停机位操作到空中飞行的时间范围。（来源：[Volanta Features — Flights](https://volanta.app/features/)）

### 4. 爬升、巡航与下降

飞行过程中，用户主要在三种信息尺度之间切换：

1. **宏观位置** ：飞机在整条航线上的位置、剩余距离和预计到达时间。
2. **即时状态** ：高度、航向、地速，以及可用时的垂直速度等。
3. **趋势变化** ：高度和地速图表、计划航路与实际航迹的偏差。

Premium 用户还可以设置 **Scheduled Pause** ，触发条件可为下降顶点、距目的地的距离、某个航路点或指定时间；远程设备可以同步该设置。（来源：[Volanta Premium — Scheduled Pause](https://volanta.app/premium/)）

### 5. 进近、落地与结束

接地后，Volanta 可以记录飞机在跑道上的实际接地点，并给出 **landing rate、ground speed、wind direction、wind speed** 等落地上下文。飞行完成后，实时面板的内容转入永久航班记录，可从 Flights 时间线重新打开。（来源：[Volanta Features — Flights](https://volanta.app/features/)）

### 6. 飞行后回看

飞行记录可展示：

- **完整 3D 航迹** ；
- **block time、flight time、fuel burned** ；
- 落地点与落地数据；
- 高度、地速等统计图；
- 飞行计划、笔记和关联截图；
- 该航班对机场、航线、飞机与账户累计统计的贡献。

这也是 Tracking 与普通实时地图的根本差异：它不只告诉用户“飞机现在在哪里”，还把一段实时过程整理为可检索、可比较、可长期累计的日志对象。（来源：[Volanta Features](https://volanta.app/features/)）

## 六、不同设备上的 Tracking

| 端 | 是否采集模拟器数据 | 主要界面形态 | Tracking 中的角色 | 关键限制 |
|---|---:|---|---|---|
| **桌面端** | 是 | 宽屏地图 + 侧面详情面板 + 完整导航 | 主要采集端，也是功能最完整的操作端 | 必须正确检测模拟器或安装相应插件 |
| **网页端** | 否 | 响应式地图 + 浮动/抽屉式面板 | 远程查看地图、航班和账户数据 | 单独打开网页不能从 PC 模拟器采集飞行 |
| **移动端** | 否 | 地图、底部导航、纵向航班详情 | 查看当前航班、天气、统计、图表、截图与笔记 | 官方说明要求桌面版正在运行；移动伴侣功能属于 Premium 范围 |
| **Xbox 工具栏端** | 是，作为发射端 | 模拟器内小型连接窗口 | 生成连接码并把当前飞行传给外部设备 | 工具栏窗口必须保持打开；每次飞行或重新打开工具栏都要重新连接 |

（来源：[Volanta Xbox Guide](https://volanta.app/console/)、[Volanta Premium](https://volanta.app/premium/)、[App Store 上的 Volanta](https://apps.apple.com/app/volanta/id1633883119)）

### Xbox 的特殊连接流程

1. 在 MSFS 2024 工具栏中打开 **Volanta** 图标。
2. 工具栏窗口显示一次性 **Unique Connection Code** 。
3. 在手机、平板或电脑上登录 `fly.volanta.app`，选择 **Start a flight with code** 。
4. 输入连接码后，Xbox 窗口状态变为 **Tracking** ，飞机位置开始出现在外部设备的地图上。
5. 工具栏窗口必须保持打开；可以移动它，但不能关闭。（来源：[Volanta Xbox Guide](https://volanta.app/console/)）

## 七、官方截图中的 Tracking 信息层级

### 1. 实时航班地图

下面的开发者商店截图展示了移动端的实时航班地图。可以观察到深色地图、紫色航迹、飞机位置、出发/到达信息和航班详情标签。

![Volanta 官方商店截图：实时航班地图](https://play-lh.googleusercontent.com/agMXmAAqASePB_CsWRJtAtdHZL6EkSwVKndljElH99dfMFj83dtbl1e4RL1FfZKlZhK4=w1280-h720)

截图来源：[Google Play — Volanta，由 Orbx 发布](https://play.google.com/store/apps/details?id=com.orbx.volanta)

### 2. 实时统计与高度图

下面的开发者商店截图展示了统计页：航班身份位于顶部，中间是高度、航向、地速、剩余时间、预计到达时间和剩余距离，底部用时间序列显示飞行高度与地形高度。

![Volanta 官方商店截图：实时统计和高度图](https://play-lh.googleusercontent.com/FGDir_eKCQTlD8e-VJ3Jw6FBDfV-7vzL6NUjd9p1cUHQfR46_Pd2GxaPqKyYi4mPTg=w1280-h720)

截图来源：[Google Play — Volanta，由 Orbx 发布](https://play.google.com/store/apps/details?id=com.orbx.volanta)

## 八、已知事实与界面分析

### 1. 已知客观事实

1. **地图是大多数页面的基础** ，并能显示机场、航路点、航路和航班。（来源：[Volanta Features](https://volanta.app/features/)）
2. **桌面追踪可以自动开始** ，不要求每次先完成冗长设置。（来源：[Volanta Features](https://volanta.app/features/)）
3. **活动航班包含实时状态、剩余进度、机场天气、航路和图表** 。（来源：[Google Play 上的 Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)）
4. **历史航班可长期访问** ，并保留 3D 航迹、时间、燃油和落地数据。（来源：[Volanta Features](https://volanta.app/features/)）
5. **免费层与 Premium 的刷新精度不同** ，Premium 提供更高频率的实时追踪。（来源：[Volanta Premium](https://volanta.app/premium/)）

### 2. 基于事实的分析

1. **Tracking 是界面的状态中枢，而不是功能孤岛。** 地图、飞机、航班日志、截图、天气和社区流量都围绕“当前或曾经发生的一次飞行”建立联系。
2. **信息采用由近到远的层级。** 大号数字回答“飞机现在怎样”，图表回答“刚才怎样变化”，地图回答“在空间中的哪里”，日志回答“整次飞行结果如何”。
3. **右侧筛选器用于控制环境噪声。** 当 Volanta、多个联飞网络、AI 流量、机场和天气同时出现时，用户必须能快速隐藏与当前任务无关的对象。
4. **自动追踪降低了忘记记录的风险，但也提高了连接状态的重要性。** 如果客户端、插件或权限级别出现问题，用户可能以为正在记录，实际却只是在查看地图。因此连接状态应被视为 Tracking 的第一项检查，而不是辅助设置。
5. **桌面端负责采集，其他端负责延伸。** 网页和移动端让用户离开主机后仍能观察航班，但它们通常不是 PC 模拟器遥测的独立来源；Xbox 版本则通过工具栏窗口承担采集端角色。

## 九、容易混淆的边界

### 1. Tracking 与 Flight Plan 不相同

**Flight Plan** 是预期要走的路线，**Tracking** 是实际发生的飞行过程。两者可以叠加比较，但导入一份 SimBrief 计划不等于已经开始记录，实际航迹也不保证完全贴合计划航路。

### 2. 本地平滑移动与云端更新不相同

Premium 页面把本地客户端的快速显示、上传到其他设备的位置更新、以及预测路径分别描述。这三者共同影响“看起来是否流畅”，但不是同一个刷新频率。（来源：[Volanta Premium](https://volanta.app/premium/)）

### 3. 移动端不是独立追踪器

官方商店说明明确指出，移动应用本身不采集飞行，需要桌面 Volanta 正在运行；它的主要任务是远程查看和控制。（来源：[App Store 上的 Volanta](https://apps.apple.com/app/volanta/id1633883119)）

### 4. 在线流量不等于自己的飞行日志

用户即使没有开始自己的 Tracking，也可能在地图上看到 Volanta 或其他网络的航空器。只有自己的活动航班被成功识别并记录后，才会形成账户中的飞行历史、统计和落地分析。

## 十、资料局限与核对建议

### 1. 资料局限

- 官方没有公开一份覆盖当前所有平台、逐控件说明的完整 UI 手册。
- 官方功能页中的桌面截图、商店中的移动端截图和当前网页端可能来自不同版本。
- 未登录的公开网页版能确认地图控制项和连接引导，但不能完整展示个人 Tracking 数据。
- 部分字段会受模拟器、插件、在线网络、飞行计划、订阅和窗口宽度影响。

### 2. 阅读本文时应采用的版本边界

本文描述的是 **截至 2026 年 9 月可由官方公开资料核实的稳定界面概念** ，而不是对某一个构建版本进行逐像素复刻。用于产品分析或原型设计时，可以把信息架构、追踪生命周期和字段分组视为高置信度内容；图标位置、标签名称、面板宽度和具体色值则应以目标版本的实机截图再次校准。

## 十一、主要参考资料

1. [Volanta — Features](https://volanta.app/features/)：地图、自动追踪、历史航班、飞机、联飞网络与内置浏览器。
2. [Volanta — Premium](https://volanta.app/premium/)：实时追踪、云截图、定时暂停、远程暂停、持久化飞行计划等。
3. [Volanta Web App](https://fly.volanta.app/)：当前公开地图筛选器、图层、连接提示与网页端结构。
4. [Volanta for Xbox](https://volanta.app/console/)：Xbox 工具栏、连接码、Tracking 状态和限制。
5. [Orbx Direct — Volanta](https://orbxdirect.com/product/volanta)：产品定位、SimBrief、Navigraph、统计和平台支持。
6. [Google Play — Volanta](https://play.google.com/store/apps/details?id=com.orbx.volanta)：开发者发布的移动端功能说明和界面截图。
7. [Apple App Store — Volanta](https://apps.apple.com/app/volanta/id1633883119)：移动端功能、版本说明和平台边界。
8. [Orbx 官方论坛 — Introducing Volanta](https://forum.orbxdirect.com/topic/201295-introducing-volanta-your-personal-flight-tracker/)：早期官方界面与产品结构参考。
