# Channel Traffic Analytics 一键部署脚本 (Windows)
# 用法: powershell -ExecutionPolicy Bypass -File install.ps1
# 或:   powershell -ExecutionPolicy Bypass -File install.ps1 -Port 8080 -InstallDir C:\site-analytics -Password admin123

param(
    [int]$Port = 8080,
    [string]$InstallDir = "C:\site-analytics",
    [string]$AdminUser = "admin",
    [string]$Password = "",
    [switch]$AsService
)

$ErrorActionPreference = "Stop"
$Repo = "tianchengdemo/channel-analytics-releases"
$Binary = "site-analytics-windows-amd64.exe"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Channel Traffic Analytics 一键部署" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  平台:     windows/amd64"
Write-Host "  安装目录: $InstallDir"
Write-Host "  端口:     $Port"
Write-Host "==========================================" -ForegroundColor Cyan

# ========== 获取最新版本 ==========
Write-Host "`n[1/5] 获取最新版本..." -ForegroundColor Yellow
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
    $Latest = $release.tag_name
} catch {
    Write-Host "[ERROR] 无法获取最新版本: $_" -ForegroundColor Red
    exit 1
}
Write-Host "  最新版本: $Latest"

# ========== 下载 ==========
Write-Host "`n[2/5] 下载 $Binary..." -ForegroundColor Yellow
$DownloadUrl = "https://github.com/$Repo/releases/download/$Latest/$Binary"
$TmpFile = Join-Path $env:TEMP "site-analytics-download.exe"

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $DownloadUrl -OutFile $TmpFile -UseBasicParsing
$ProgressPreference = 'Continue'
Write-Host "  下载完成: $([math]::Round((Get-Item $TmpFile).Length / 1MB, 1)) MB"

# ========== 安装 ==========
Write-Host "`n[3/5] 安装到 $InstallDir..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\data" | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\logs" | Out-Null
Copy-Item -Path $TmpFile -Destination "$InstallDir\site-analytics.exe" -Force
Remove-Item -Path $TmpFile -Force

# ========== 生成配置 ==========
Write-Host "`n[4/5] 生成配置文件..." -ForegroundColor Yellow
if (-not $Password) {
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    $Password = -join (1..16 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    Write-Host "  [自动生成密码] $Password" -ForegroundColor Green
}
$TokenSecret = -join (1..32 | ForEach-Object { "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"[(Get-Random -Maximum 62)] })

$ConfigFile = "$InstallDir\config.yaml"
if (-not (Test-Path $ConfigFile)) {
    @"
server:
  port: $Port
  host: "0.0.0.0"

database:
  path: "$($InstallDir -replace '\\', '/')/data/stats.db"

admin:
  username: "$AdminUser"
  password: "$Password"
  token_secret: "$TokenSecret"

reporting:
  token: ""
  max_batch_size: 500

detail:
  enabled: false
  retention_days: 30

proxy:
  trusted_proxies:
    - "127.0.0.1/32"

buffer:
  flush_interval: 10s
  flush_threshold: 1000

log:
  level: "info"
  path: "$($InstallDir -replace '\\', '/')/logs/app.log"
"@ | Out-File -FilePath $ConfigFile -Encoding UTF8
    Write-Host "  配置已写入: $ConfigFile"
} else {
    Write-Host "  配置已存在，跳过覆盖: $ConfigFile"
}

# ========== 防火墙规则 ==========
Write-Host "`n[5/5] 配置防火墙..." -ForegroundColor Yellow
try {
    $rule = Get-NetFirewallRule -DisplayName "Site Analytics" -ErrorAction SilentlyContinue
    if (-not $rule) {
        New-NetFirewallRule -DisplayName "Site Analytics" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
        Write-Host "  已添加防火墙规则: 允许 TCP $Port"
    } else {
        Write-Host "  防火墙规则已存在"
    }
} catch {
    Write-Host "  [WARN] 需要管理员权限添加防火墙规则，请手动开放端口 $Port" -ForegroundColor DarkYellow
}

# ========== 注册 Windows 服务 (可选) ==========
if ($AsService) {
    Write-Host "`n注册 Windows 服务..." -ForegroundColor Yellow
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssm) {
        & nssm install SiteAnalytics "$InstallDir\site-analytics.exe" "-config" "$ConfigFile"
        & nssm set SiteAnalytics AppDirectory "$InstallDir"
        & nssm start SiteAnalytics
        Write-Host "  服务已注册并启动 (使用 nssm)"
    } else {
        sc.exe create SiteAnalytics binPath= "`"$InstallDir\site-analytics.exe`" -config `"$ConfigFile`"" start= auto | Out-Null
        sc.exe start SiteAnalytics | Out-Null
        Write-Host "  服务已注册并启动 (使用 sc.exe)"
    }
} else {
    Write-Host "`n启动服务..." -ForegroundColor Yellow
    Start-Process -FilePath "$InstallDir\site-analytics.exe" -ArgumentList "-config", $ConfigFile -WorkingDirectory $InstallDir -WindowStyle Hidden
    Start-Sleep -Seconds 2
}

# ========== 验证 ==========
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:${Port}/admin/login.html" -UseBasicParsing -TimeoutSec 5
    if ($resp.StatusCode -eq 200) {
        Write-Host "`n  验证通过" -ForegroundColor Green
    }
} catch {
    Write-Host "`n  [WARN] 服务可能需要几秒启动" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  部署完成" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  后台地址: http://服务器IP:${Port}/admin/"
Write-Host "  用户名:   $AdminUser"
Write-Host "  密码:     $Password" -ForegroundColor Green
Write-Host "  配置文件: $ConfigFile"
Write-Host "  数据目录: $InstallDir\data\"
Write-Host ""
Write-Host "  管理命令:"
Write-Host "    停止: taskkill /IM site-analytics.exe /F"
Write-Host "    启动: Start-Process $InstallDir\site-analytics.exe -ArgumentList '-config','$ConfigFile'"
Write-Host "==========================================" -ForegroundColor Cyan
