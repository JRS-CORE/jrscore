@echo off
chcp 65001 >nul
title JRS Core - Installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1"
