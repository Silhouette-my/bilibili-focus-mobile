# 文档索引

| 目录 | 内容 |
|---|---|
| `guides/` | 长期有效的操作说明 |
| `architecture/` | 架构边界与升级路线 |
| `records/` | 按开始日期命名的专项工作记录（`YYYY-MM-DD-主题.md`），只追加，不回改结论 |
| `design/` | 设计稿与设计系统 |

版本变化见仓库根目录的 [CHANGELOG](../CHANGELOG.md)。

## 指南

- [测试与同步检查](guides/testing.md)：分层测试、运行时与 API 契约同步、本地产物与清理
- [在线 API Smoke](guides/online-smoke.md)：真实账号只读检查，需显式 opt-in

## 架构

- [升级路线图](architecture/upgrade-roadmap.md)

## 工作记录

- [2026-10-16 性能与稳定性基础修复](records/2026-10-16-performance-foundation.md)
- [2026-10-17 动态详情返回：滚动位置专项](records/2026-10-17-dynamic-scroll-return-fix.md)
- [2026-10-17 起 性能后续优化与评论分页](records/2026-10-17-performance-followup.md)
- [2026-10-29 双端主力客户端改进](records/2026-10-29-client-maturity.md)

> 记录中引用的 `build/…` 证据路径是当时的本地产物，已于 2026-11-02 清理，不再随仓库提供。

## 设计

- [设计系统](design/design-system.html)
