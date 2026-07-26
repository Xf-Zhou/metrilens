# Metrilens 产品与技术设计方案

- 文档版本：0.6
- 更新日期：2026-07-26
- 状态：0.6 已实施并通过 L2 双轮独立审查
- 核心原则：轻量优先、数据诚实、无侵入、可降级

## 0.5 阶段扩展（2–9）

本阶段在不改变 Apple Silicon、单进程、无管理员权限、运行时不联网的边界下增加：

- 菜单栏单项/紧凑组合模式；只为实际显示的指标维持后台采样，开启提醒时 CPU 与内存例外。
- 跟随系统、简体中文和 English 三种界面语言。
- CPU 与内存各自保存最近 60 秒、最多 64 个样本，展示平均值、峰值和折线悬停读数。
- 电池当前温度、本次运行最高温度、设备寿命最高温度三者明确区分；本次运行最高温度可重置为当前值。
- 温度与系统热状态使用系统语义色；不可用状态展示具体、可本地化的原因。
- 设置按显示、采样、提醒和系统分组。
- 本地提醒默认关闭。开启后才申请系统通知权限；CPU/内存必须以新鲜样本持续超过用户阈值 30/60/120 秒才提醒，系统热状态严重或危急则立即提醒，同类提醒冷却 10 分钟。应用位于前台时仍展示横幅并播放提示音。
- 诊断报告可以复制或保存，只输出白名单字段：设置、采样状态、实际周期、指标状态、60 秒汇总和最近 5 条去重错误。
- `accept_release.sh` 默认重新下载 GitHub Release 资产，再校验摘要、包结构、版本、架构、签名和大小；可选执行隔离的短启动检查。

上述扩展不引入长期历史数据库、遥测、进程扫描、外部采集进程或后台网络访问。提醒和更多菜单栏指标会激活各自需要的 Provider：CPU、内存、电池或磁盘提醒会激活对应采样；网络目前没有提醒，仅在弹窗打开或菜单栏显示网络时采样。界面需明确这些能力由用户主动启用。

## 0.6 轻量公开指标与诊断扩展（1、2、3、5、6、9）

本阶段增加电池详情、网络速率、磁盘容量、显示排序与格式、提醒 2.0、CI 加固和异常发热诊断：

- 电池详情读取电量、充电/外接电源状态、循环次数和系统提供的健康状态。电池详情与温度共用 10/30/120 秒调度，但温度字段不支持时仍可继续读取其他电池信息。
- 网络速率用 `SCDynamicStore` 确定 IPv4/IPv6 主接口，通过 `sysctl` 的 `NET_RT_IFLIST2`/`RTM_IFINFO2` 读取 `if_data64` 64 位累计字节，再用单调时间差分。首次读取、接口切换和计数器回退只建立新基线，不发起连接。
- 启动磁盘明确锚定根路径 `/`；总量与空闲量来自 `FileManager.attributesOfFileSystem`，可用量优先使用根卷的 `volumeAvailableCapacityForImportantUsage`，缺失时才回退到空闲量。弹窗可见、菜单栏显示磁盘或磁盘提醒启用时每 60 秒读取一次，低电量模式为 120 秒。
- 弹窗卡片和紧凑菜单栏指标按用户顺序排列；菜单栏支持圆点、竖线、空格分隔符及 0/1 位小数。弹窗打开时所有卡片都需要数据；弹窗关闭后，只有菜单栏已显示或提醒已启用的对应 Provider 继续采样，其余 Provider 暂停。
- 提醒总开关默认关闭；CPU、内存、系统热状态、低电量、电池高温、磁盘空间不足各有独立开关。阈值提醒只接受 fresh 样本、共用持续时间和每类 10 分钟冷却；设置页展示通知权限并提供测试通知与系统设置入口。
- 发热诊断只分析系统热状态、CPU 当前值/60 秒汇总、电池温度和充电状态，输出稳定的 evidence/recommendation code 与本地化建议。它不枚举进程、不猜测具体 App；CPU 高负载时建议用户在“活动监视器”确认来源。
- CI 使用中英文两个测试环境，失败时上传 `xcresult`；发布 workflow 检查 tag commit 与实际检出提交一致，并更新 GitHub Actions 主版本。

这些能力仍不引入后台主动联网、进程扫描、外部命令、管理员权限、长期数据库或额外常驻定时器。

## 1. 产品定位

Metrilens 是一款常驻 macOS 菜单栏的轻量系统状态查看器。第一版聚焦用户最常查看、且能低成本稳定采集的指标：

- CPU 总占用
- 内存占用
- 电池实时温度与电池历史最高温度
- macOS 系统热状态

应用默认不联网、不上传数据、不写入长期历史、不扫描进程列表、不请求管理员权限，也不启动 `top`、`vm_stat`、`powermetrics` 等外部进程。

“实时”指适合人类观察的准实时更新，而不是以高频轮询追求传感器级实时性。所有采样频率都要服从轻量和低能耗目标。

## 2. 已确认的产品决策

### 2.1 技术形态

- 使用 Swift + AppKit。
- 使用 `NSStatusItem` 提供菜单栏入口。
- 使用 `NSPopover` 展示详情。
- 设置 `LSUIElement = true`，不显示 Dock 图标。
- 单进程运行，第一版不引入 helper、daemon 或 XPC 服务。
- 不使用 Electron、WebView、SwiftUI Charts、第三方图表库或遥测 SDK。
- 最低支持 macOS 13。

V1 发布基线已经锁定：

| 项目 | V1 决策 |
| --- | --- |
| 运行架构 | 仅 `arm64`，不构建或承诺 Intel `x86_64` |
| 构建产物 | 本地可运行的 Debug/Release App |
| 分发 | 不进入 V1；不做 Developer ID 分发签名、公证或 Mac App Store 提交 |
| 本地签名 | 可运行产物仅使用 Xcode 的 “Sign to Run Locally”；`CODE_SIGNING_ALLOWED=NO` 只用于无签名编译门禁 |
| App Sandbox | V1 关闭；分发方案确定后重新评估 |
| 菜单栏默认值 | 单指标 `CPU`；组合指标不进入 V1 |
| CPU/GPU 精确温度 | 完全移出 V1，只保留在 V2 技术验证范围 |

登录时启动仍使用 `SMAppService.mainApp`。V1 只验证本地构建下的注册、取消注册和 `.requiresApproval` 状态，不把分发签名、公证作为完成条件。

### 2.2 温度定义

界面必须明确区分以下三类数据，不能统称为“电脑温度”：

| 数据 | 第一版策略 | 说明 |
| --- | --- | --- |
| 电池实时温度 | 支持 | 从 `AppleSmartBattery` 的 IORegistry 属性读取；无需管理员权限 |
| 电池历史最高温度 | 支持 | 从电池寿命数据读取；仅在启动、唤醒等低频时机刷新 |
| 系统热状态 | 支持 | 使用公开的 `ProcessInfo.thermalState`，显示正常、偏热、严重、危急 |
| CPU/GPU 精确温度 | 不进入 V1 | macOS 没有受支持的公开摄氏温度 API；仅保留为 V2 独立技术验证 |

电池 IORegistry 字段并不是 Apple 承诺稳定的高层业务 API，因此必须在运行时探测能力。字段不存在、格式变化或数值异常时，界面显示“不可用”，不得猜测或伪造数据。

### 2.3 电池温度采样策略

电池温度变化较慢，默认不采用每 5 秒持续轮询。确认采用以下自适应策略，重叠状态严格按表中从上到下的优先级决定：

| 优先级 | 状态 | 电池温度刷新间隔 |
| ---: | --- | ---: |
| 1 | 系统睡眠 | 停止采样 |
| 2 | 系统处于低电量模式 | 120 秒 |
| 3 | 弹窗打开且正在查看温度 | 10 秒 |
| 4 | 菜单栏当前显示电池温度 | 30 秒 |
| 5 | 温度未显示、应用仅后台运行 | 暂停 |

额外事件规则：

- 系统唤醒或实际电源来源变化后立即读取一次。
- 唤醒后的 2 秒合并窗口内，电源来源通知不能触发第二次重复读取。
- 电量百分比变化不视为“电源来源变化”，不得因此刷新历史最高温度。
- 低电量模式下，CPU/内存有效采样周期固定为 `max(用户设置, 5 秒)`，即 1 秒或 2 秒配置会降为 5 秒，5 秒配置保持不变。

实现要求：

- 不为电池温度创建独立高频定时器。
- 使用一个基于单调时钟的 `DispatchSourceTimer`。每个 Provider 保存下一次 monotonic deadline，调度器始终重排到最早 deadline，不使用 tick 计数。
- 状态变化时重新计算 deadline；定时器 leeway 取 `min(200 ms, 当前最短周期的 10%)`。
- 电池历史最高温度仅在应用启动、系统唤醒和明确的电池状态变化后读取。
- 系统热状态使用通知驱动，不定时轮询。
- 每个温度样本记录 `sampledAt`，界面可判断数据是否过期。
- 使用 `NSWorkspace.willSleepNotification`、`NSWorkspace.didWakeNotification`、`ProcessInfo.powerStateDidChangeNotification` 和 `IOPSNotificationCreateRunLoopSource`。
- 所有通知先投递到 `MetricSampler` 的串行队列；通知回调不得直接修改模型或 UI。
- observer、IOPowerSources run-loop source 和定时器都必须在生命周期结束时成对清理。

## 3. 第一版功能范围

### 3.1 菜单栏

默认只显示一个主指标，避免长期占用过多菜单栏空间：

```text
CPU 23%
```

用户可以切换为：

```text
MEM 61%
BAT 35.9°
```

要求：

- 使用等宽数字，避免数值变化造成宽度跳动。
- 颜色默认跟随系统菜单栏，仅在确有告警时使用语义色。
- 不使用持续动画。
- 菜单栏项目不可见或被系统挤出时，不增加采样频率。

### 3.2 状态弹窗

建议初始尺寸约为 300 × 260 点：

```text
┌────────────────────────────┐
│ Metrilens               ⚙︎ │
│                            │
│ CPU             23%  ▁▂▃▆ │
│ 内存       9.8 / 16 GB 61% │
│ 电池温度            35.9°C │
│ 电池历史最高          40°C │
│ 系统热状态            正常 │
│                            │
│ 更新于              12:34 │
└────────────────────────────┘
```

要求：

- CPU 显示最近 60 秒轻量折线。
- 内存显示 Metrilens 口径的已用、总量和百分比，并提供口径说明。
- 电池温度必须明确标注“电池”，不能显示成“设备温度”或“CPU 温度”。
- 没有电池的桌面 Mac 自动隐藏电池模块。
- 不支持的指标显示 `—` 或“不支持”，不能显示 `0`。

### 3.3 设置

第一版只保留必要设置：

- 菜单栏主指标
- CPU/内存刷新间隔：1、2、5 秒
- 登录时启动
- 是否显示 CPU 微型折线
- 数据来源与温度能力说明

设置使用 `UserDefaults` 保存。除用户主动修改设置外，采样过程不写磁盘。

### 3.4 第一版明确不做

- 单进程 CPU/内存排行榜
- 长期历史、数据库和导出
- 网络同步、账号和云功能
- GPU 使用率与功耗
- CPU/GPU 精确温度的稳定承诺
- 风扇控制
- 常驻 `powermetrics`
- 管理员权限与特权 helper
- 多级告警编排、跨设备通知和自定义通知动作

## 4. 数据采集设计

### 4.1 CPU

- 使用 Mach `host_statistics` 与 `HOST_CPU_LOAD_INFO`。
- 对连续两次累计 tick 做差值，计算总 CPU 占用。
- 首次启动、睡眠唤醒、计数器回退时仅建立基线，不输出异常瞬时值。
- 默认每 1 秒采样；用户选择 2 秒或 5 秒时同步调整。

### 4.2 内存

- `totalBytes = ProcessInfo.processInfo.physicalMemory`。
- 使用 `host_statistics64(HOST_VM_INFO64)` 获取 `vm_statistics64_data_t`，并使用 `host_page_size` 获取页大小。
- 所有 page counter 先转换为 `UInt64`；加法和乘法必须使用溢出检查。任何溢出返回 `unavailable(.counterOverflow)`，不得截断或回绕。
- 当前 Xcode 16.4 / macOS 15.5 SDK 的 `vm_statistics.h` 明确说明 `speculative_count` 已计入 `free_count`，因此 V1 公式不直接使用 `free_count`、`speculative_count` 或 `external_page_count`，避免重复计数或假设字段集合互斥。
- 定义：

```text
occupiedPages =
    internal_page_count
  + wire_count
  + compressor_page_count

usedBytes      = clamp(occupiedPages * pageSize, 0, totalBytes)
availableBytes = totalBytes - usedBytes
usedPercent    = usedBytes / totalBytes * 100
purgeableBytes = purgeable_count * pageSize
```

- `internal_page_count` 表示匿名页，`wire_count` 表示 wired 页，`compressor_page_count` 表示压缩器实际占用的物理页；V1 只对这三个 SDK 明确定义的物理占用计数求和。
- `purgeable_count` 只单独换算为 `purgeableBytes` 供口径说明，不从主值扣除，因为 SDK 没有在该结构中保证它与上述集合的包含/互斥关系。
- UI 主值命名为“Metrilens 占用”，使用 `usedBytes / totalBytes`；`purgeableBytes` 不进入主卡片。
- 这是保守且可重复的 Metrilens 口径，不承诺与“活动监视器”逐字节一致。
- `clamp` 仅是异常保护。单元和实机 fixture 必须证明正常快照在 clamp 前满足 `occupiedPages * pageSize <= totalBytes`。
- V1 不展示“内存压力”。公开 Mach VM 统计不能直接给出与活动监视器等价的压力值，避免用推导值冒充系统压力。

### 4.3 电池温度

优先通过 IOKit API 直接读取 IORegistry，而不是启动 `ioreg` 子进程。

当前测试机已验证：

- `AppleSmartBattery.Temperature` 可无管理员权限读取。
- 当前温度原始值常见为 0.1 K，可按 `raw / 10 - 273.15` 换算为摄氏度。
- `BatteryData.LifetimeData.MaximumTemperature` 可提供历史最高温度。
- 2026-07-26 实机读取到的示例为约 35.9°C，历史最高温度为 40°C。

由于属性语义未形成稳定高层 API，V1 只支持下面这份版本化解码契约：

#### 当前温度

- 硬件匹配：`IOServiceMatching("AppleSmartBattery")`。
- 键路径：顶层 `Temperature`。
- 类型：只接受可无损转换为整数的 `CFNumber`。
- 原始范围：`2532...3731`，单位固定按 0.1 K 解释。
- 换算：`celsius = raw / 10.0 - 273.15`。
- 换算后再次校验 `-20...100°C`。

#### 历史最高温度

- 键路径：`BatteryData.LifetimeData.MaximumTemperature`。
- 类型：只接受可无损转换为整数的 `CFNumber`。
- 单位：直接按摄氏度解释，允许范围 `0...100°C`。
- 它使用独立解码器，绝不能复用当前温度的 0.1 K 换算。

#### 能力与拒绝规则

- 能力探测分别记录：`hardwarePresent`、`fieldPresent`、`decoderSupported`，不能合并成一个布尔值。
- 未识别的键路径、CF 类型、单位或量级一律返回 `unsupported(.unsupportedEncoding)`，不得根据数值大小猜单位。该状态停止常规定时读取，只在唤醒或硬件拓扑变化后重新探测。
- `BatteryTemperatureProvider` 维护独立的 `pendingCandidate(value, firstSeenAt, expiresAt)`，候选 TTL 为 `max(120 秒, 2 × 当前有效温度周期 + 5 秒)`。
- 当前温度在 120 秒内相对最后有效样本跳变超过 15°C 时，拒绝该样本并创建候选值。
- 候选存在时，下一次有效读取若与候选相差不超过 2°C，则确认新水平；否则用最新读数替换候选并重新开始 TTL。候选存在期间不能绕过此规则直接接受新值。
- 候选期间：已有最后有效值时对外输出 `stale(lastValue, sampledAt)`；从未成功时输出 `unavailable(.outlierJump)`。异常候选不增加 IOKit 失败计数。
- 候选到期、系统睡眠、Provider 暂停、硬件拓扑变化、字段/decoder 支持状态变化时立即清空。
- 这个规则只拒绝、替换或确认样本，不插值、不平滑、不改写数值。
- 新 macOS 或新机型只有经过匿名 fixture 测试和至少一台实机交叉验证后，才能加入支持矩阵。
- `io_service_t`、`CFTypeRef` 及其嵌套对象必须按 IOKit/Core Foundation ownership 规则释放。

### 4.4 系统热状态

- 使用 `ProcessInfo.processInfo.thermalState`。
- 监听 `thermalStateDidChangeNotification`。
- 展示四档状态：正常、偏热、严重、危急。
- 系统热状态不等同于某个传感器温度，界面不得将它换算成摄氏度。

### 4.5 CPU/GPU 精确温度

Apple 没有提供受支持的 CPU/GPU 摄氏温度 API。该能力完全不属于 V1 的 target、源文件、设置、测试或验收范围。V2 若选择官网签名、公证分发，可单独进行以下能力验证：

- AppleSMC
- IOHID 传感器事件
- 其他未文档化的 IOKit 路径

这些路径可能无需 root，但会随 macOS、SoC 和机型变化。必须使用独立 Provider、能力探测和公开热状态降级，不能进入基础数据模型的必填字段。

`powermetrics` 需要管理员权限且采样本身较重，不进入常驻采集链路。

## 5. 软件架构

```text
AppDelegate
├── LifecycleEventBridge
├── StatusItemController
├── PopoverController
│   └── HeatDiagnosisAnalyzer
├── PreferencesController
├── MetricAlertController
└── MetricSampler
    ├── CPUProvider
    ├── MemoryProvider
    ├── BatteryTemperatureProvider
    ├── BatteryStatusProvider
    ├── NetworkProvider
    ├── DiskCapacityProvider
    ├── ThermalStateProvider
    ├── ProviderDeadlineScheduler
    ├── MetricHistoryBuffer（CPU、内存各一个）
    └── SystemSnapshot
            │
            ▼
      主线程 UI、提醒与诊断报告
```

架构要求：

- `MetricSampler` 在单一串行 utility 队列上运行。
- `LifecycleEventBridge` 只负责把 AppKit、Foundation、IOPowerSources 事件转交给采样队列。
- `ProviderDeadlineScheduler` 维护各 Provider 的单调时钟 deadline，并只持有一个带 leeway 的 `DispatchSourceTimer`。
- 每轮生成不可变 `SystemSnapshot`，一次性派发到主线程。
- 单个 Provider 失败不能影响其他指标。
- 上一轮未完成时跳过本轮，不能积压采样任务。
- V1 不包含 `EnhancedSensorProvider` 或任何 CPU/GPU 私有传感器文件。
- 折线使用 Core Graphics 或单个 `CAShapeLayer` 绘制。

### 5.1 需求驱动采样

| UI/系统状态 | CPU | 内存 | 电池详情与温度 | 网络 | 启动磁盘 |
| --- | --- | --- | --- | --- | --- |
| 弹窗打开 | 用户设置的 1/2/5 秒 | 用户设置的 1/2/5 秒 | 10 秒 | 用户设置的 1/2/5 秒 | 60 秒 |
| 弹窗关闭 | 菜单栏显示或 CPU 提醒启用时按用户周期，否则暂停 | 菜单栏显示或内存提醒启用时按用户周期，否则暂停 | 菜单栏显示或任一电池提醒启用时 30 秒，否则暂停 | 菜单栏显示时按用户周期，否则暂停 | 菜单栏显示或磁盘提醒启用时 60 秒，否则暂停 |
| 低电量模式 | 活跃时至少 5 秒 | 活跃时至少 5 秒 | 活跃时 120 秒 | 活跃时至少 5 秒 | 活跃时 120 秒 |
| 睡眠 | 停止 | 停止 | 停止 | 停止 | 停止 |

系统热状态始终由通知驱动，不参与轮询。

行为约束：

- 打开弹窗或切换主指标只能向 `ProviderDeadlineScheduler` 提交需求，UI 不得直接调用 Provider。
- CPU/内存的 UI 请求最小间隔等于当前有效周期；已有未过期值时立即展示缓存值并保留既有 deadline，不能提前读取。
- 电池温度的 UI 请求最小间隔为 10 秒。进入弹窗可以把后续周期改为 10 秒，但若最近 10 秒内已读取，不得再次调用 IOKit。
- 同一 Provider 同时最多一个 in-flight 请求；重复需求合并，完成后按 monotonic deadline 安排下一轮。
- CPU 从暂停恢复时，第一次读取只建立 tick 基线；下一个周期才生成占用率。
- CPU 基线建立最多执行一次；首个有效周期前的重复 UI 事件不得重建基线。
- CPU 不可见且弹窗关闭时停止采样，这是轻量优先的明确取舍。
- 因暂停导致没有完整历史时，曲线显示“正在收集”，不得伪造缺失区间。
- CPU 与内存都维护最近 60 秒、最多 64 点的内存环形缓冲；暂停或有效周期变化时清空，避免把不连续区间误画成连续历史。
- 隐藏状态停止图层重绘；模型变更也不能触发隐藏图表布局。
- 唤醒和实际电源来源变化属于强制刷新，可以越过普通 UI cooldown，但仍受 2 秒事件合并窗口和单 in-flight 约束。

### 5.2 CPU 与内存历史缓冲

- CPU 与内存分别持有一个 `MetricHistoryBuffer`，不共享样本或状态。
- 只保存带 monotonic timestamp 的有效 CPU/内存样本。
- 每次写入和读取时删除早于当前时间 60 秒的样本。
- 固定容量上限为 64 个点；达到上限时覆盖最旧点，不发生持续分配。
- 1/2/5 秒周期分别最多展示约 61/31/13 个点，时间跨度始终按 timestamp 解释，而不是按点数推断。
- 切换周期、主指标和弹窗状态时不补采样、不插值。
- scheduler 拒绝早于有效周期的重复 CPU/内存样本；UI 事件不能通过快速切换向缓冲写入额外点。

## 6. 轻量化验收标准

以下指标以当前 arm64 测试机、Release 构建、接入电源、关闭低电量模式、弹窗关闭、菜单栏显示 CPU、CPU 周期 1 秒为标准场景：

| 项目 | 通过条件 |
| --- | ---: |
| 平均 CPU 占用 | 三次 10 分钟测量的中位数 ≤ 0.3%，且单次平均值不超过 0.5% |
| 稳态 RSS | 三次测量的中位数目标 ≤ 25 MB，任意样本 ≤ 40 MB |
| App 包体积 | Release `.app` ≤ 10 MB |
| 稳态 wakeups | 平均 ≤ 1.2 次/秒；低电量模式平均 ≤ 0.25 次/秒 |
| App 主动网络连接 | 0 |
| 稳态 App 主动磁盘写入 | 0 |
| App 启动的子进程 | 0 |
| 新进程启动到菜单栏就绪（允许系统文件缓存） | 20 次测量中位数 ≤ 300 ms |

测量协议：

1. 每次稳态性能测试使用全新进程，先暖机 60 秒。
2. CPU、RSS 和 wakeups 连续测量 10 分钟，共运行 3 次，报告每次值及中位数。
3. 使用 Release 配置，不连接 Xcode debugger，不打开弹窗，不操作 UI。
4. 保持接入电源，开启低电量模式后另跑一次相同协议，验证有效周期和 wakeups。
5. 性能门禁仅接受干净工作树；结果记录测试机型号、macOS 版本、commit、Release 可执行文件 SHA-256、供电状态和有效采样设置。启动、标准与低电量结果只有这些身份字段和协议版本完全一致，启动测量每轮前后、稳态测量每个 5 秒采样点、每轮开始/结束与 App 报告均为 AC 供电时才可汇总。

24 小时稳定性协议：

- 每 60 秒记录一次 RSS，前 30 分钟作为暖机不计入趋势。
- 暖机后任意 RSS 不得超过 40 MB。
- 最后 60 分钟 RSS 中位数减去最初 60 分钟中位数不得超过 2 MB。
- 对暖机后的样本做线性回归，增长斜率不得超过 0.1 MB/小时。
- 睡眠期间不得出现 Provider 采样；唤醒后两个 CPU 有效周期内恢复。

测试阶段允许使用 `xctrace`、`fs_usage`、`lsof` 等外部诊断工具；这些工具不得进入 App 的运行路径。

## 7. 指标状态、失败策略与数据诚实

统一状态模型：

```text
available(value, sampledAt)
stale(lastValue, sampledAt)
unavailable(reasonCode)
unsupported(reasonCode)
```

状态转移：

| 触发 | 新状态 |
| --- | --- |
| 启动时没有对应硬件 | `unsupported(.noHardware)` |
| 电池温度能力探测确认当前机型没有候选字段 | `unsupported(.fieldMissing)`；只在唤醒或硬件拓扑变化后重试能力探测 |
| 已支持的 Provider 读取缺少必填字段 | `unavailable(.fieldMissing)`，后续按有效周期重试 |
| 有硬件但首次读取失败 | `unavailable(reasonCode)` |
| 曾成功后一次读取失败 | `stale(lastValue, sampledAt)` |
| stale 达到 Provider TTL 或失败次数阈值 | 丢弃旧值并进入 `unavailable(reasonCode)` |
| 任意失败状态后读取成功 | 立即进入 `available` 并清零失败计数 |

Provider 阈值：

| Provider | stale 结束条件（先到者生效） |
| --- | --- |
| CPU | 连续 3 次失败，或距最后成功达到 `max(10 秒, 3 × 有效周期)` |
| 内存 | 连续 3 次失败，或距最后成功达到 `max(10 秒, 3 × 有效周期)` |
| 电池温度 | 连续 2 次失败，或距最后成功达到 `max(60 秒, 2 × 有效周期)` |
| 电池历史最高温度 | 连续 2 次失败，或距最后成功达到 3600 秒 |
| 电池详情 | 连续 2 次失败，或距最后成功达到 `max(120 秒, 3 × 有效周期)` |
| 网络速率 | 连续 3 次失败，或距最后成功达到 `max(10 秒, 3 × 有效周期)` |
| 启动磁盘容量 | 连续 2 次失败，或距最后成功达到 `max(180 秒, 3 × 有效周期)` |

错误码至少包括：

```text
noHardware
fieldMissing
unsupportedEncoding
counterOverflow
outOfRange
outlierJump
iokitFailure(code)
machFailure(code)
```

`reasonCode` 仅用于测试和本地诊断；UI 只显示稳定的“无电池”“暂不可用”“数据已过期”“当前机型不支持”等文案，不展示原始错误或硬件标识。

数据诚实要求：

- 读取失败时不能用 `0` 代替真实数据。
- stale 状态使用次要颜色并显示最后更新时间；TTL 到期后必须丢弃旧数值，并显示稳定、本地化的失败原因占位文本，不能继续保留旧数值或旧严重度颜色。
- 数值越界或未确认突变只能被拒绝，不能自动改写、平滑或插值成看似真实的数据。
- 所有温度必须标明对象，例如“电池温度”。
- 不把历史最高温度当成当前温度。
- 不把系统热状态描述为精确温度。

## 8. 测试计划

### 8.1 单元测试

- CPU tick 差值、首次采样、暂停恢复、计数器回退及除数为零。
- 电池详情的电量、供电状态、循环次数、健康度、字段缺失与无电池降级。
- 电池当前温度 fixture：有效整数、缺键、错误 CF 类型、未知量级、raw 边界和溢出。
- 历史最高温度 fixture：有效摄氏整数、误传 deci-Kelvin、缺少嵌套字典和越界。
- 网络主接口的 IPv4/IPv6 选择、首次基线、接口切换、计数器回退，以及超过 `UInt32` 的 64 位累计值。
- 启动磁盘根路径、容量关系校验和失败状态。
- 发热诊断的 CPU、电池温度、充电、严重/危急系统热状态，以及危急建议在 UI 三条截断前的优先级。
- 温度突变候选固定覆盖：
  - `35 → 60`：拒绝 60，对外保持 stale 35，候选为 60。
  - `35 → 60 → 60`：第二个 60 确认，输出 available 60。
  - `35 → 60 → 45 → 45`：45 替换候选 60，第二个 45 确认。
  - 候选 TTL 到期：清空候选；下一样本重新相对最后有效值判断。
  - 睡眠、暂停和能力状态变化：清空候选。
  - raw `3731` 可进入最终摄氏校验，`3732` 必须拒绝为 outOfRange。
- CPU 环形缓冲的 60 秒裁剪、64 点上限和 1/2/5 秒切换。
- 所有重叠采样状态、运行时切换、唤醒去重和 monotonic deadline 重排。
- UI 事件风暴：1 秒内模拟至少 100 次弹窗开关与 CPU/MEM/BAT 切换；断言始终只有一个 timer、每个 Provider 最多一个 in-flight、调用次数不超过 cooldown 允许值、CPU 基线最多建立一次、缓冲最多增加一个点，deadline 不得被提前到 cooldown 之前。
- 每个 Provider 的 available、stale、unavailable、unsupported 全部状态边。

内存公式使用固定 page size 4096 和 total 100 pages，至少覆盖：

| Fixture | internal/wired/compressor | purgeable（仅说明） | 期望 |
| --- | --- | --- | --- |
| 常规 | 40/20/10 | 5 | used 70 pages，available 30 pages，70% |
| 空闲 | 0/0/0 | 0 | used 0 pages，available 100 pages，0% |
| 计数超出物理总量 | 80/30/10 | 5 | pre-clamp 120 pages，异常保护后 used 100 pages |
| 溢出 | 任一参与计数为 `UInt64.max` | 0 | `unavailable(.counterOverflow)` |

另加入 2026-07-26 当前实机同一时刻的匿名 fixture：page size 16384、total 16 GiB、internal 247172、wired 272556、compressor 345157、purgeable 3264。期望 pre-clamp `usedBytes = 14170275840`、`usedPercent ≈ 82.48%`，并断言 `usedBytes < totalBytes`，证明正常样本不依赖 clamp。

### 8.2 集成测试

- Apple Silicon MacBook 电池温度读取
- 无电池设备的降级表现
- 电源接入与拔出
- 低电量模式
- 睡眠与唤醒
- 菜单栏切换不同主指标
- 主指标切换后 CPU 基线重建和“正在收集”曲线
- 磁盘严重度转入占位状态时恢复普通文本颜色
- 弹窗关闭后按菜单栏指标和提醒开关暂停无需求 Provider
- 登录时启动及需要用户批准的状态

### 8.3 性能测试

- 实施阶段先运行 `xcrun xctrace list templates`，确认本机存在 Time Profiler、Allocations、Leaks 和 System Trace 模板。Xcode 16.4 当前不再列出独立的 Energy Log；若未来工具版本提供则作为补充，不作为 V1 门禁依赖。
- `scripts/build_local_release.sh` 生成固定路径 `.build/DerivedData/Build/Products/Release/Metrilens.app` 的 arm64 ad-hoc 签名 App，并依次执行 `codesign --verify --deep --strict`、启动、PID 探测和退出 smoke test。
- 启动门禁的正式名称是“新进程启动到菜单栏就绪”，不是“冷启动”。它允许 macOS 和文件系统已有缓存，但每轮都必须创建新的 Metrilens 进程，不清空系统缓存，也不能复用已运行实例。
- `scripts/measure_launch.py` 在外部测试进程中使用 monotonic clock 记录起点，随后直接 `posix_spawn` Release 包内的 `Contents/MacOS/Metrilens`，因此计时包含进程创建、dyld、Swift/Objective-C runtime 与 App 初始化。测试进程预先创建 pipe，并通过 `METRILENS_PERF_READY_FD` 传入可继承的写端。
- `StatusItemController` 创建出非空 `NSStatusItem.button` 后，使用无缓冲 `write(2)` 向 ready pipe 写入一次固定 token。测试进程收到完整 token 的 monotonic 时刻为终点；App 内部计时只能作为诊断，不能用于门禁。
- 启动测试先确认不存在其他 Metrilens 进程；每轮使用 2 秒 ready 超时，收到 token 后只终止本轮 `posix_spawn` 返回的精确子 PID 并等待退出。连续运行 20 次并计算中位数；已有实例、token 错误、EOF、超时、子进程异常退出、样本不足或中位数超过 300 ms 均返回非零。
- `scripts/measure_lightweight.sh standard` 执行第 6 节标准协议：先拒绝既有 Metrilens 实例，验证 arm64、接入电源且低电量模式关闭，再启动 Release App、记录其精确 PID 和随机 launch token、暖机 60 秒、每 5 秒采样 `%CPU` 与 RSS、运行 10 分钟并输出原始数据，共重复 3 次。Perf mode 使用独立易失配置，强制菜单栏 CPU、配置周期 1 秒，不读取或改写用户偏好。
- `scripts/measure_lightweight.sh low-power` 要求保持接入电源且低电量模式已经开启，独立运行一次相同 10 分钟窗口并使用 `≤ 0.25 wakeups/s` 门槛。启动测量在每轮前后、稳态测量在每个 5 秒采样点记录并校验供电环境，禁止中途切换供电后恢复 AC 的结果混入汇总。`finalize` 只有在标准场景、低电量场景、启动门禁和磁盘监控结果全部存在且通过时才生成成功 summary；场景状态不符或结果缺失必须非零退出。
- wakeups 的唯一门禁数据源是 App 对自身 `mach_task_self_` 调用公开 Mach API `task_info(..., TASK_POWER_INFO, ...)` 得到的 `task_power_info_data_t`，不依赖 `powermetrics` 输出格式。外部脚本在启动 App 前生成一个未来的绝对 monotonic 起点，通过 `METRILENS_PERF_START_UPTIME` 传入；App 的 TaskPowerProbe 和外部 CPU/RSS 采样都等待该共享起点。每次 `task_info` 读取前后都记录 uptime，整个读取区间必须位于对应资源窗口端点的 100 ms 容差内，报告起止时间固定为读取区间中点；不能只比较窗口时长或单个时间戳。磁盘监控在共享起点前完成启动确认，并覆盖到外部窗口结束之后。10 分钟结束后使用实际窗口秒数计算：

```text
interruptWakeupsPerSecond =
  checkedSubtract(end.task_interrupt_wakeups,
                  start.task_interrupt_wakeups)
  / elapsedMonotonicSeconds
```

- 第 6 节的 wakeups 阈值只比较 `task_interrupt_wakeups` 的上述平均速率。`task_platform_idle_wakeups`、`task_timer_wakeups_bin_1` 和 `task_timer_wakeups_bin_2` 同时记录为诊断字段，但不参与 V1 门禁。
- `TaskPowerProbe` 只在 `METRILENS_PERF_MODE=1` 且同时存在有效 `METRILENS_PERF_REPORT_FD`、未来的共享 monotonic 起点时启用；结束后通过继承 pipe 写出共享请求起点、两次读取区间及其中点、launch token、进程 PID、两次原始累计值、实际时长、计算结果，以及窗口开始/结束时的主指标、配置周期、有效周期、低电量模式和供电来源的固定版本 JSON 行，不写磁盘、不联网。测试脚本只接受自己启动的精确 PID 和 token 对应的报告，避免 PID 复用或串入其他实例，并将 pipe 收到的原始字节按轮次单独保存，供汇总结果追溯。
- `task_info` 返回失败、结构体 count 不足、累计计数回退、算术溢出、时长非正、报告缺失或报告版本未知，都归类为测量设施失败并返回非零，不能当成产品 wakeups 回归。单元测试固定覆盖正常累计差值、计数回退、短结构、Mach 错误、不完整时长、错误 PID/token 和溢出。
- 网络门禁在完整 10 分钟窗口内由独立线程按 monotonic 固定起点以 95 ms 为目标节拍使用 `lsof` 监视目标精确 PID 的网络 socket；每次执行前检查距上次真实开始时间不得超过 100 ms，调度晚醒不能被下一轮快速执行掩盖。再配合静态禁用 `URLSession`、`NWConnection` 与 BSD socket 创建调用；发现任一 App 主动连接即失败。诊断工具自身流量不得计入 App；`lsof` 缺失、返回异常状态或无法维持 100 ms 上限，都属于测量设施失败，不能按“无网络”通过。
- 子进程门禁由另一个独立线程按相同 95 ms 目标节拍执行 `pgrep -P "$METRILENS_PID"`，不与 `lsof` 串行；任意相邻两次真实开始时间不得超过 100 ms。任意时刻出现子 PID即失败。`pgrep` 缺失、返回约定以外的状态或无法维持节拍同样属于测量设施失败，不能按“无子进程”通过。再配合静态禁用 `Process/NSTask/popen/system` 的检查，覆盖短时执行路径。
- 暖机后由脚本通过已缓存的 `sudo -v` 授权启动 `fs_usage`，先确认进程仍在运行，再开始 600 秒 CPU/RSS 窗口；窗口结束时再次要求 `fs_usage` 仍存活，随后等待其带尾部余量正常结束，确保完整包住测量窗口并保存原始日志。启动确认或测量期间即使以状态 0 提前退出，也视为测量设施失败。除用户主动修改设置外，Metrilens 任意主动文件写入均失败。测试工具需要的管理员权限不属于 App 权限。
- `scripts/measure_lightweight.sh standard` 必须先重新构建固定的 Release 产物；完整门禁拒绝脏工作树，并以 commit、可执行文件 SHA-256、机型、macOS 版本和协议版本作为结果身份。脚本汇总 launch、CPU、RSS、wakeups、网络、子进程、磁盘写入和包体积，把原始数据写入 `/tmp/metrilens-perf/<commit>/`。`finalize` 必须重新读取每轮 JSON、对应原始 task-power 文件和带 SHA-256 的 `fs_usage` 日志，校验固定样本数量、600 秒测量时长及 5 秒上限容差、两次 `task_info` 完整读取区间与资源窗口端点的 100 ms 对齐、上下文、累计计数与计算速率，并从原始样本复算每轮和场景汇总；任一文件缺失、日志被修改、嵌入报告不一致、样本截断、身份不匹配或协议版本不识别时返回非零。
- 包体积固定使用 MiB：`du -sk` 的结果必须 `<= 10240` KiB。
- 使用 Allocations/Leaks 和第 6 节 RSS 协议执行 24 小时稳定性测试。

## 9. 实施阶段与门禁

本节是最初 V1 到当前 0.6 的实施记录，不作为当前架构或 Provider 清单；当前结构、采样周期和失败策略分别以第 5、5.1、7 节为准。各阶段实施时单独提交；没有数据库或持久化迁移，阶段回滚边界为撤销对应阶段提交。

| 阶段 | 主要文件/Target | 依赖 | 完成条件 |
| --- | --- | --- | --- |
| 1. 工程骨架 | `Metrilens.xcodeproj`、App target、Unit Test target、`main.swift`、`AppDelegate.swift`、Info.plist | 无 | macOS 13、arm64、AppKit、LSUIElement、Debug/Release scheme 可构建 |
| 2. 纯模型 | `Model/MetricState.swift`、`SystemSnapshot.swift`、`CPUHistoryBuffer.swift` | 阶段 1 | 无 IOKit/AppKit 的单元测试通过 |
| 3. CPU/内存 Provider | `Metrics/CPUProvider.swift`、`MemoryProvider.swift` | 阶段 2 | tick、VM 公式、错误注入测试通过 |
| 4. 电池与热状态 | `BatteryTemperatureProvider.swift`、`BatteryFixtures.swift`、`ThermalStateProvider.swift` | 阶段 2 | 解码契约、无电池、未知格式和实机读取通过 |
| 5. 调度与生命周期 | `Sampling/MetricSampler.swift`、`ProviderDeadlineScheduler.swift`、`LifecycleEventBridge.swift` | 阶段 3、4 | 状态优先级、deadline、睡眠唤醒、低电量、事件合并测试通过 |
| 6. UI 与设置 | `UI/StatusItemController.swift`、`PopoverController.swift`、`SparklineView.swift`、`PreferencesController.swift` | 阶段 5 | 三种主指标、缺失/过期态、曲线和 UserDefaults 行为通过 |
| 7. 登录启动 | `LoginItemController.swift` | 阶段 6 | 本地签名构建可注册、取消注册并处理 requiresApproval |
| 8. 性能与 V1 门禁 | `Diagnostics/TaskPowerProbe.swift`、`scripts/build_local_release.sh`、`measure_launch.py`、`measure_lightweight.sh`、`monitor_runtime.sh`、`monitor_children.sh`、性能记录 | 阶段 7 | 脚本自动执行第 6、8 节全部阈值，保存原始数据；任一失败返回非零；生成并 smoke-test 本地 Release App |
| 9. 0.6 指标与诊断扩展 | `BatteryStatusProvider.swift`、`NetworkProvider.swift`、`DiskCapacityProvider.swift`、`HeatDiagnosis.swift`、提醒与指标管理 UI | 阶段 8 | 需求驱动采样、状态降级、双语言 UI、提醒和诊断回归测试通过；不新增外部进程、主动网络、管理员权限或常驻定时器 |

工程初始化固定配置：

```text
PRODUCT_NAME = Metrilens
MACOSX_DEPLOYMENT_TARGET = 13.0
ARCHS = arm64
SUPPORTED_PLATFORMS = macosx
App Sandbox = Off
Hardened Runtime = Off（V1 本地构建）
```

基础验证命令：

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  build
```

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  test
```

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

这个 `CODE_SIGNING_ALLOWED=NO` 命令只证明 Release 配置可以编译，不把产物作为可运行交付物。V1 可运行 Release App 由 Xcode 的 “Sign to Run Locally” 生成；Developer ID、Hardened Runtime、公证和商店签名均不进入 V1。

本地可运行的 ad-hoc Release 构建与 smoke test：

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_IDENTITY=- \
  build
```

```bash
METRILENS_APP_PATH=.build/DerivedData/Build/Products/Release/Metrilens.app
codesign --verify --deep --strict --verbose=2 "$METRILENS_APP_PATH"
open -na "$METRILENS_APP_PATH"
pgrep -x Metrilens
```

`scripts/build_local_release.sh` 封装以上命令，并只终止它本次启动且已记录 PID 的 Metrilens 进程。登录启动集成测试使用这个固定产物，不依赖 Xcode UI 的临时运行状态。

Release 体积：

```bash
du -sk .build/DerivedData/Build/Products/Release/Metrilens.app
```

静态约束检查：

```bash
rg -n 'URLSession|NWConnection|Process\(|NSTask|popen|system\(' Metrilens
```

期望无匹配；若 Apple SDK 类型名造成误报，必须逐项解释并增加更精确规则。

## 10. 后续路线与非 V1 决策

V1 的架构、最低系统、菜单栏默认形式和本地交付方式已经锁定，不再包含阻止开工的待确认项。

### V1.1：公开指标扩展

- 已完成：电池电量、循环次数与健康状态
- 已完成：网络速率
- 已完成：磁盘容量
- 已完成：基础阈值提醒与异常发热建议
- 后续候选：磁盘实时读写速率（需先确认公开 API、准确性与能耗）

### V2：独立技术验证

- 分发渠道、Developer ID 签名、公证与 App Sandbox 策略
- CPU/GPU 传感器温度
- 风扇 RPM 只读
- 功耗估算
- 按机型维护的传感器映射

V2 的私有传感器探索必须在独立分支和独立 Provider 中进行，不能降低 V1 的公开热状态降级能力。仍不默认引入管理员权限，也不做风扇写控制。

## 11. 参考资料

- [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [ProcessInfo.thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- [Apple DTS：没有受支持的 CPU 温度读取机制](https://developer.apple.com/forums/thread/743133)
- [host_statistics](https://developer.apple.com/documentation/kernel/1502546-host_statistics)
- [host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64)
- [IOPowerSources](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo)
- [macOS 软件分发](https://developer.apple.com/macos/distribution/)
- [Mac App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
