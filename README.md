# Metrilens

Metrilens 是一个仅支持 Apple Silicon、常驻 macOS 菜单栏的轻量系统状态查看器。

V1 显示：

- CPU 总占用与最近 60 秒折线
- “Metrilens 占用”口径的内存使用量
- AppleSmartBattery 电池当前温度与历史最高温度
- macOS 系统热状态

它不联网、不启动外部采集进程、不请求管理员权限，也不承诺 CPU/GPU 精确摄氏温度。

## 构建

要求 macOS 13 或更高版本、Apple Silicon 和 Xcode 16。

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  build
```

运行本地 Release 构建及 smoke test：

```bash
./scripts/build_local_release.sh
```

产物位于：

```text
.build/DerivedData/Build/Products/Release/Metrilens.app
```

## 测试

```bash
xcodebuild \
  -project Metrilens.xcodeproj \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/DerivedData \
  test
```

完整轻量化门禁要求工作树无未提交修改，并把结果绑定到 commit、Release 可执行文件 SHA-256、机型与系统版本，避免混用旧产物。门禁分为标准与低电量两个场景，总计约 45 分钟。磁盘写入检查使用测试工具 `fs_usage`，开始前先缓存一次管理员授权：

```bash
sudo -v
./scripts/measure_lightweight.sh standard
```

然后保持接入电源并开启 macOS 低电量模式：

```bash
sudo -v
./scripts/measure_lightweight.sh low-power
./scripts/measure_lightweight.sh finalize
```

每个稳态场景都会在开始、结束、每个 5 秒采样点和 App 报告中验证实际电源状态，启动门禁也会在每轮前后验证，确保启动、标准和低电量结果不会混用电池供电数据；网络与子进程分别使用独立的 100 ms 固定节拍监控。外部脚本与 App 共享同一个 monotonic 测量起点，CPU/RSS 窗口端点与两次 wakeups 计数读取前后的完整区间偏差均不得超过 100 ms，磁盘监控则提前启动并完整包住该 600 秒窗口。每轮 App 产生的原始 task-power JSON 和 `fs_usage` 日志都会单独保存，`finalize` 会校验日志摘要、窗口对齐、每轮结果与资源样本并复算汇总。状态不符合场景、原始数据不完整或诊断工具不可用时都会失败。

详细产品与技术约束见 [设计方案](docs/design.md)。
