# Channel Traffic Analytics - 发布包

轻量级自建流量统计系统，通过渠道编码区分来源，统计 PV/UV/IP/PV比，单二进制部署。

## 一键部署

### Docker (推荐)

```bash
curl -fsSL https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/install-docker.sh | bash
```

自定义参数：

```bash
curl -fsSL https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/install-docker.sh | bash -s -- --port 9090 --password MyPass123
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | 8080 | 映射到宿主机的端口 |
| `--dir` | /opt/site-analytics | 数据和配置存储目录 |
| `--password` | (随机生成) | 管理员密码 |
| `--name` | site-analytics | 容器名称 |

或者手动运行：

```bash
docker run -d \
  --name site-analytics \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /opt/site-analytics/data:/app/data \
  -v /opt/site-analytics/config.yaml:/app/config.yaml:ro \
  ghcr.io/tianchengdemo/channel-traffic-analytics:latest
```

### Linux / macOS (二进制)

```bash
curl -fsSL https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/install.sh | bash
```

自定义参数：

```bash
curl -fsSL https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/install.sh | bash -s -- --port 9090 --password MyPass123
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--port` | 8080 | 监听端口 |
| `--dir` | /opt/site-analytics | 安装目录 |
| `--password` | (随机生成) | 管理员密码 |
| `--user` | admin | 管理员用户名 |

### Windows

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tianchengdemo/channel-analytics-releases/main/install.ps1" -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File install.ps1
```

自定义参数：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Port 9090 -Password MyPass123 -AsService
```

## 支持平台

| 文件 | 系统 | 架构 |
|------|------|------|
| site-analytics-linux-amd64 | Linux | x86_64 |
| site-analytics-linux-arm64 | Linux | ARM64 |
| site-analytics-darwin-amd64 | macOS | Intel |
| site-analytics-darwin-arm64 | macOS | Apple Silicon |
| site-analytics-windows-amd64.exe | Windows | x86_64 |

## 脚本做了什么

1. 检测当前系统和 CPU 架构
2. 从 GitHub Releases 下载对应平台的最新版本二进制
3. 生成 config.yaml（自动生成随机密码和 JWT 密钥）
4. Linux: 注册 systemd 服务并启动
5. Windows: 添加防火墙规则，可选注册 Windows 服务
6. 验证服务是否启动成功
7. 打印后台地址和登录凭据

## 手动下载

前往 [Releases](https://github.com/tianchengdemo/channel-analytics-releases/releases) 页面下载对应平台的二进制文件。

## 功能概览

- 高并发埋点采集（HyperLogLog 去重 + 内存 Buffer + 批量刷盘）
- 渠道管理 CRUD + JWT 鉴权后台
- 多维统计查询（总览 / 渠道列表 / 渠道详情 / 实时数据）
- 4 种接入方式（异步 JS / 同步 JS / IMG 像素 / API）
- CSV 数据导出（全渠道 + 单渠道日/小时级）
- 来源维度分析（搜索引擎 / 社交媒体 / 直接访问 / 外部链接）
- 服务端批量上报接口
- 明细采集（设备分辨率 / 语言 / 访问记录）
- 后台管理界面（TailwindCSS + Chart.js）
- 系统设置（时区 / 刷盘参数 / 管理员改密）
- 单二进制部署（Go embed + SQLite，无需 Nginx/Redis/MySQL）
