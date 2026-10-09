@echo off
chcp 65001 >nul
title CodeArts Accounts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.codearts2api\manage-accounts.ps1"
