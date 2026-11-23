@echo off
chcp 65001 >nul
title Trafficity 繁體中文安裝
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1"
