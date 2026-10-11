@echo off
chcp 65001 >nul
title 小学作业生成器 - Web 版启动器
echo ============================================
echo  小学作业生成器 Web 版
echo  正在启动本地服务... 请稍候
echo  启动后浏览器将自动打开，不要关闭本窗口
echo ============================================
echo.

cd /d "%~dp0"

REM 查找可用的 Python 命令（python / py / python3）
set "PYCMD="
where python >nul 2>nul && set "PYCMD=python"
if not defined PYCMD where py >nul 2>nul && set "PYCMD=py"
if not defined PYCMD where python3 >nul 2>nul && set "PYCMD=python3"
if not defined PYCMD (
    echo [错误] 未找到 Python，请先安装 Python 3（https://www.python.org/downloads/）
    echo 安装时勾选 "Add Python to PATH"
    pause
    exit /b 1
)

REM 起 HTTP 服务（127.0.0.1 仅本机访问）
start "" "http://127.0.0.1:8765"
"%PYCMD%" -m http.server 8765 --bind 127.0.0.1
pause