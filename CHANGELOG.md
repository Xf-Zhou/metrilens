# 更新日志

本项目的显著变更记录在此。版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增

- 可重复执行的发布前后验收清单。
- 缺陷报告与功能建议 Issue 表单。

## [0.2.0] - 2026-07-26

### 新增

- “关于 Metrilens”窗口、隐私安全的诊断信息复制功能和常用键盘快捷键。
- VoiceOver 标签、指标值和设置控件辅助功能支持。
- 正式 App 图标、产品截图和完整安装、卸载说明。
- 偏好损坏自动恢复、恢复默认设置入口及对应测试。
- Apple Silicon CI、确定性 ZIP 打包、SHA-256 校验和 GitHub Release workflow。

### 更改

- GitHub Actions 成为 Release、草稿和资产的唯一写入者，避免本地发布与 workflow 并发覆盖。

## [0.1.0] - 2026-07-26

### 新增

- 首个 Apple Silicon 菜单栏版本。
- CPU 总占用与最近 60 秒折线。
- Metrilens 内存占用、电池当前/历史最高温度和系统热状态。
- 1 秒、2 秒和 5 秒刷新频率，以及登录启动和菜单栏主指标设置。

[未发布]: https://github.com/Xf-Zhou/metrilens/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Xf-Zhou/metrilens/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Xf-Zhou/metrilens/releases/tag/v0.1.0
