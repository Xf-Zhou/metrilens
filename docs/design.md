# Metrilens 产品与技术设计方案

- 文档版本：0.1
- 更新日期：2026-07-26
- 状态：方案草案
- 核心原则：轻量优先、数据诚实、无侵入、可降级

## 1. 产品定位

Metrilens 是一款常驻 macOS 菜单栏的轻量系统状态查看器。第一版聚焦用户最常查看、且能低成本稳定采集的指标：

- CPU 总占用
- 内存占用与内存压力
- 电池实时温度与电池历史最高温度
- macOS 系统热状态

应用默认不联网、不上传数据、不写入长期历史、不扫描进程列表、不请求管理员权限，也不启动 `top`、`vm_stat`、`powermetrics` 等外部进程。

“实时”指适合人类观察的准实时更新，而不是以高频轮询追求传感器级实时性。所有采样频率都要服从轻量和低能耗目标。

## 2. 已确认的产品决策

### 2.1 技术形态

- 使用 Swift + AppKit。
- 使用 `NSStatusItem` 提供菜单栏入口。
- 使用 `NSPopover` 或轻量 `NSPanel` 展示详情。
- 设置 `LSUIElement = true`，不显示 Dock 图标。
- 单进程运行，第一版不引入 helper、daemon 或 XPC 服务。
- 不使用 Electron、WebView、SwiftUI Charts、第三方图表库或遥测 SDK。
- 建议最低支持 macOS 13，以便使用 `SMAppService` 管理登录时启动。

### 2.2 温度定义

界面必须明确区分以下三类数据，不能统称为“电脑温度”：

| 数据 | 第一版策略 | 说明 |
| --- | --- | --- |
| 电池实时温度 | 支持 | 从 `AppleSmartBattery` 的 IORegistry 属性读取；无需管理员权限 |
| 电池历史最高温度 | 支持 | 从电池寿命数据读取；仅在启动、唤醒等低频时机刷新 |
| 系统热状态 | 支持 | 使用公开的 `ProcessInfo.thermalState`，显示正常、偏热、严重、危急 |
| CPU/GPU 精确温度 | 不作为基础版承诺 | macOS 没有受支持的公开摄氏温度 API；仅作为官网增强版的实验能力 |

电池 IORegistry 字段并不是 Apple 承诺稳定的高层业务 API，因此必须在运行时探测能力。字段不存在、格式变化或数值异常时，界面显示“不可用”，不得猜测或伪造数据。

### 2.3 电池温度采样策略

电池温度变化较慢，默认不采用每 5 秒持续轮询。确认采用以下自适应策略：

| 场景 | 刷新间隔 |
| --- | ---: |
| 弹窗打开且正在查看温度 | 10 秒 |
| 菜单栏当前显示电池温度 | 30 秒 |
| 温度未显示、应用仅后台运行 | 60 秒 |
| 系统处于低电量模式 | 120 秒 |
| 系统睡眠 | 停止采样 |
| 系统唤醒或电源状态变化 | 立即读取一次 |

实现要求：

- 不为电池温度创建独立高频定时器。
- 复用统一采样时钟，到达对应计数时才读取温度，从而避免额外系统唤醒。
- 电池历史最高温度仅在应用启动、系统唤醒和明确的电池状态变化后读取。
- 系统热状态使用通知驱动，不定时轮询。
- 每个温度样本记录 `sampledAt`，界面可判断数据是否过期。

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
- 内存显示已用、总量和压力状态，并在说明中明确统计口径。
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
- 告警通知和复杂阈值系统

## 4. 数据采集设计

### 4.1 CPU

- 使用 Mach `host_statistics` 与 `HOST_CPU_LOAD_INFO`。
- 对连续两次累计 tick 做差值，计算总 CPU 占用。
- 首次启动、睡眠唤醒、计数器回退时仅建立基线，不输出异常瞬时值。
- 默认每 1 秒采样；用户选择 2 秒或 5 秒时同步调整。

### 4.2 内存

- 使用 `host_statistics64`、`HOST_VM_INFO64` 和物理内存总量。
- 需要明确处理 active、wired、compressed、cached、purgeable 等概念。
- 产品文案不承诺与“活动监视器”逐字节一致。
- 内存压力比单纯“剩余内存”更适合作为告警依据。

### 4.3 电池温度

优先通过 IOKit API 直接读取 IORegistry，而不是启动 `ioreg` 子进程。

当前测试机已验证：

- `AppleSmartBattery.Temperature` 可无管理员权限读取。
- 当前温度原始值常见为 0.1 K，可按 `raw / 10 - 273.15` 换算为摄氏度。
- `BatteryData.LifetimeData.MaximumTemperature` 可提供历史最高温度。
- 2026-07-26 实机读取到的示例为约 35.9°C，历史最高温度为 40°C。

由于属性语义未形成稳定高层 API，实现必须包含：

- 属性存在性检查
- 数值类型检查
- 合理范围检查
- 机型能力探测
- 单位与换算验证
- 失败后的明确降级

### 4.4 系统热状态

- 使用 `ProcessInfo.processInfo.thermalState`。
- 监听 `thermalStateDidChangeNotification`。
- 展示四档状态：正常、偏热、严重、危急。
- 系统热状态不等同于某个传感器温度，界面不得将它换算成摄氏度。

### 4.5 CPU/GPU 精确温度

Apple 没有提供受支持的 CPU/GPU 摄氏温度 API。后续若产品选择官网签名、公证分发，可单独进行以下能力验证：

- AppleSMC
- IOHID 传感器事件
- 其他未文档化的 IOKit 路径

这些路径可能无需 root，但会随 macOS、SoC 和机型变化。必须使用独立 Provider、能力探测和公开热状态降级，不能进入基础数据模型的必填字段。

`powermetrics` 需要管理员权限且采样本身较重，不进入常驻采集链路。

## 5. 软件架构

```text
AppDelegate
├── StatusItemController
├── PopoverController
├── PreferencesController
└── MetricSampler
    ├── CPUProvider
    ├── MemoryProvider
    ├── BatteryTemperatureProvider
    ├── ThermalStateProvider
    └── EnhancedSensorProvider（可选）
            │
            ▼
      SystemSnapshot
            │
            ▼
       RingBuffer
       ├── 菜单栏
       └── 状态弹窗
```

架构要求：

- `MetricSampler` 在单一串行 utility 队列上运行。
- 采用带 tolerance/leeway 的 `DispatchSourceTimer`。
- 每轮生成不可变 `SystemSnapshot`，一次性派发到主线程。
- 单个 Provider 失败不能影响其他指标。
- 上一轮未完成时跳过本轮，不能积压采样任务。
- 历史数据使用固定容量环形缓冲，避免持续内存分配。
- 弹窗关闭后不更新隐藏图表，只更新当前菜单栏指标。
- 折线使用 Core Graphics 或单个 `CAShapeLayer` 绘制。

建议的数据状态：

```text
available(value, sampledAt)
unavailable(reason)
stale(lastValue, sampledAt)
unsupported
```

## 6. 轻量化验收标准

以下指标以 Release 构建、弹窗关闭、默认采样配置为准：

| 项目 | 目标 |
| --- | ---: |
| 平均 CPU 占用 | ≤ 0.3% |
| 稳态常驻内存 | 目标 ≤ 25 MB，上限 40 MB |
| App 包体积 | ≤ 10 MB |
| 常规系统唤醒 | 不超过统一采样时钟频率 |
| 网络请求 | 0 |
| 采样期间磁盘写入 | 0 |
| 外部采集进程 | 0 |
| 冷启动到菜单栏出现 | 目标 ≤ 300 ms |

稳定性要求：

- 连续运行 24 小时，常驻内存不持续增长。
- 睡眠期间无采样，唤醒后两个 CPU 周期内恢复正常。
- 低电量模式下降低非关键指标采样频率。
- 无电池、字段缺失和传感器异常都不能导致崩溃。

## 7. 错误处理与数据诚实

- 读取失败时不能用 `0` 代替真实数据。
- 数值明显越界或突变时丢弃该样本。
- 连续失败后将旧值标为过期，而不是永久显示最后一次数据。
- 所有温度必须标明对象，例如“电池温度”。
- CPU/GPU 私有传感器需要显示来源和兼容性说明。
- 不把历史最高温度当成当前温度。
- 不把系统热状态描述为精确温度。

## 8. 测试计划

### 8.1 单元测试

- CPU tick 差值、首次采样和计数器回退
- 内存计算口径
- 电池温度单位换算和异常范围
- 固定容量环形缓冲
- 采样频率状态机
- 指标 available、stale、unsupported 状态转换

### 8.2 集成测试

- Apple Silicon MacBook 电池温度读取
- 无电池设备的降级表现
- 电源接入与拔出
- 低电量模式
- 睡眠与唤醒
- 菜单栏切换不同主指标
- 登录时启动及需要用户批准的状态

### 8.3 性能测试

- Instruments Energy Log
- Time Profiler
- Allocations 与 Leaks
- 24 小时常驻测试
- 1、2、5 秒采样配置对比
- 30、60、120 秒电池温度策略对比

## 9. 迭代路线

### V1：轻量核心

- CPU
- 内存
- 电池实时温度
- 电池历史最高温度
- 系统热状态
- 菜单栏与弹窗
- 登录时启动
- 自适应温度采样

### V1.1：公开指标扩展

- 电池电量、循环次数与健康状态
- 网络速率
- 磁盘容量与读写速率
- 基础阈值提示

### V2：官网增强版实验能力

- CPU/GPU 传感器温度
- 风扇 RPM 只读
- 功耗估算
- 按机型维护的传感器映射

V2 仍不默认引入管理员权限，也不做风扇写控制。

## 10. 待确认事项

以下决策尚未锁定，不阻碍 V1 公共核心开发：

1. 仅供自己使用、官网签名公证分发，还是必须进入 Mac App Store。
2. 第一版仅优先支持 Apple Silicon，还是同步支持 Intel Mac。
3. 菜单栏默认只显示一个指标，还是允许 CPU、内存、温度组合显示。
4. 是否把 CPU/GPU 精确温度列为 V2 的明确目标。

当前推荐默认值：

- 官网签名、公证分发
- Apple Silicon 优先
- 菜单栏默认单指标
- CPU/GPU 精确温度仅作为可失败的增强能力

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
