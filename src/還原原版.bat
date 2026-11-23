@echo off
chcp 65001 >nul
title Trafficity 還原原版
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore.ps1"
