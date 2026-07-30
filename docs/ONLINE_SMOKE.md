# 在线 API Smoke

`Scripts/run_online_smoke.mjs` 只对契约目录中的
`https://api.bilibili.com/x/web-interface/nav` 发起一次只读 `GET`，验证登录健康分类和
WBI 启动字段的最小形状。脚本不会执行点赞、收藏、历史上报等写操作。

## 安全边界

- 默认跳过；只有 `FOCUS_ONLINE_SMOKE=1` 才会访问网络。
- Cookie 只从 `FOCUS_BILIBILI_COOKIE` 环境变量读取，不接受命令行参数，也不会打印。
- URL 不带 Cookie、关键词、签名或其他查询参数。
- 输出只有固定状态，不输出昵称、mid、Cookie、响应正文、URL 或原始异常。
- CI 只运行默认跳过路径，不配置或保存账号 Cookie。

## 本地运行

在可信终端中静默读取 Cookie header 的值（不要包含 `Cookie:` 前缀）：

```bash
read -rs FOCUS_BILIBILI_COOKIE
export FOCUS_BILIBILI_COOKIE
FOCUS_ONLINE_SMOKE=1 node Scripts/run_online_smoke.mjs
unset FOCUS_BILIBILI_COOKIE
```

成功输出为：

```text
PASS online smoke: login_health=healthy; wbi_bootstrap=available
```

其他固定状态包括 `not_logged_in`、`session_expired`、`missing_csrf`、
`wbi_risk_controlled`、`network_unavailable` 和 `unknown`。脚本对不健康状态返回非零；
配置错误返回退出码 2。
