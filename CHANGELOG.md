# Changelog

## v1.1 — 2026-11-23

- 新增單檔 `Trafficity-CHT-Setup.exe`：內嵌腳本與譯文，雙擊即安裝，支援 `--restore`
- 安裝器會自動尋找 Steam 遊戲目錄（registry + libraryfolders.vdf + 常見路徑）
- 所有建置（zip / exe）移到 GitHub Actions，Release 同時附上兩種形式
- CI 加入譯文完整性檢查、錨點檢查、PE 標頭冒煙測試
- 新增 `AGENTS.md`（繁體中文）說明 asar 格式與不可違反的規則
- 驗證 2026-11 遊戲更新（build 26866133）：i18n 主程式雜湊未變，錨點與 442 條譯文全部沿用，重新套用後實機確認繁中正常

## v1.0 — 2026-11-23

首個公開版本。

- 新增 zht 繁中語系，442 條譯文
- 語言選單顯示「繁體中文」，簡體中文保留
- zh-TW / zh-HK / zh-MO / zh-Hant 自動對應
- 一鍵安裝 / 還原腳本（PowerShell，無外部依賴）
- 錨點檢查：版本不相容時安全中止
- 安裝時自動備份 app.asar.orig，安裝後自動將語言切為繁中
- 以遊戲 1.0（build 6969441617）實機驗證
