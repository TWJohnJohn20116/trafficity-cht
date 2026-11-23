# AGENTS.md

給 AI 編碼代理的專案指引。動工前先讀完這一頁。

## 這個 repo 是什麼

這是 Steam 遊戲 *Trafficity*（AppID 5185750，Electron 應用）的**繁體中文介面漢化補丁**。
它在遊戲既有的語言清單裡**新增**一個 `zht` 語系（442 條字串），不覆蓋簡體中文，
也不碰存檔、成就或任何其他遊戲檔案。

本 repo **不包含任何遊戲檔案**，只有腳本與譯文資料。

## 目錄結構

| 路徑 | 用途 |
| --- | --- |
| `src/zht.json` | 譯文的唯一真實來源。鍵是遊戲的 i18n key，**永遠不要改 key**。 |
| `src/patch.ps1` | 安裝器：錨點檢查、字串注入、asar 重建、語言設定。 |
| `src/restore.ps1` | 把 `app.asar.orig` 還原回 `app.asar`。 |
| `src/installer/Installer.cs` | C# 啟動器，內嵌上面三個檔案並呼叫 PowerShell。 |
| `src/installer/build.ps1` | 用 .NET Framework `csc.exe` 編譯 `dist/Trafficity-CHT-Setup.exe`。 |
| `tools/build-asar.mjs` | 開發工具：原始 `app.asar` + `zht.json` 產生漢化版封裝。 |
| `tools/inspect-asar.mjs` | 列出或解出任意 asar 內容。 |
| `.github/workflows/release.yml` | **所有建置都在這裡做。** 驗證 → zip → exe → 冒煙測試 → 發佈。 |

## 硬性不變條件

違反下面任一條，遊戲會在沒有錯誤訊息的情況下壞掉。

1. **asar 標頭佈局。** 檔案開頭是四個小端序 `uint32`：
   `4 | headerSize | payloadSize | jsonLen`，JSON 標頭從位移 **16** 開始。
   `payloadSize = 4 + jsonLen`（補齊到 4 的倍數），`headerSize = 4 + payloadSize`。
   檔案資料從 `8 + headerSize` 開始。
   標頭寫錯時，隨便寫的解析器仍可讀取，但遊戲會在啟動約 3 秒後直接退出、不報錯。
2. **偏移量是相對資料區**，在標頭裡以**字串**儲存；必須依照寫入順序重新計算。
3. **unpacked 條目**（`unpacked: true`，例如 `steamworks.js` 原生模組）沒有 offset，
   打包時必須跳過；它們的位元組存在 `app.asar.unpacked/`。
4. **五個字串錨點**必須全部找到才可開始寫入。缺任何一個就中止，且不得修改檔案。
   錨點清單在 `src/patch.ps1`。
5. **PowerShell 檔必須有 UTF-8 BOM。** 少了它，Windows PowerShell 5.1 會以 ANSI 解讀，
   中文字面量會直接讓解析器爆掉。
6. **不要提交** `*.asar`、`*.exe`、`dist/`、`node_modules/`，`.gitignore` 已經擋好。

## 翻譯規則

每個值裡這幾種標記必須**逐字保留**：

| 標記 | 範例 | 說明 |
| --- | --- | --- |
| `{var}` | `{count} 位居民` | 由遊戲代入，前後順序可調整 |
| `[key:action]` | `按 [key:elevationUp]` | 會換成玩家自訂的按鍵 |
| `__i18n.key__` | `__toolbar.grid__` | 底線包住的 i18n key，會替換成另一個譯名 |
| 換行 | 少數字串 | 某些 UI 標籤靠換行排版，不可刪 |

用台灣用語，不要中國用語：設定／載入／儲存／車道／圓環／交通號誌／地塊／覆蓋層／行程／全螢幕。
完整對照表在 `CONTRIBUTING.md`。

## 如何驗證改動

```bash
# 1. 譯文表是合法 JSON 且數量正確
node -e "const z=require('./src/zht.json');console.log(Object.keys(z).length)"

# 2. 重建結果與已知良好版本逐位元組相同
#    來源必須是「原始」app.asar，不能是已漢化過的
node tools/build-asar.mjs /path/to/app.asar.orig /tmp/out.asar
sha256sum /tmp/out.asar
```

參考雜湊（每次升級遊戲版本都要重新記錄一組）：

| 遊戲 build | 參考雜湊 |
| --- | --- |
| 6969441617（1.0 首發） | `ca036a04933fd319014d362356ae868bb657f1f2b047b3f778f10e96ecd7e9b8` |
| 26866133（2026-11 更新） | `62c1a30a8fe1ba4d96f4228871a22795c21548fdb1d8f966a46f843241ec1391` |

2026-11 更新只動了 `Router.*.js`、worker bundle 與執行檔，i18n 主程式
`dist/transit-city-game.225ce3d0.js` 的雜湊完全沒變，因此譯文與錨點全部沿用。

如果你刻意改了 `zht.json`，雜湊當然會不同；但若封裝大小或偏移佈局有非預期的變化，
代表 asar 寫入邏輯回歸了。

有裝遊戲時的實機測試：關閉遊戲 → 執行安裝器 → 從 Steam 啟動 → 確認 設定 → 語言
有「繁體中文」，主選單顯示 開始教學 / 新遊戲 / 載入遊戲。

## 建置與發佈

- **不要在本地編譯安裝器**，一律由 CI（`windows-latest`）負責。
- 發版由 tag 驅動：`git tag v1.2 && git push origin v1.2` 會跑驗證、打包 zip、
  `csc` 編譯、PE 標頭冒煙測試，最後建立 GitHub Release。
- `src/installer/build.ps1` 會先把輸入複製到「沒有空白字元」的暫存目錄，因為
  `csc /resource:` 解析含空格路徑會出錯。重構時請保留這個處理。
- 本機只保留打包便利指令：`build-release.ps1 -Tag vX.Y` 產生 zip。

## 風格

- 註解與使用者可見文字用繁體中文；程式識別字用英文。
- `patch.ps1` 必須維持 Windows PowerShell 5.1 相容（不能用 `??`、三元運算子、`-Parallel`）。
- 寧可透過 `Fail()` 明確報錯並中止，也不要做「盡力而為」的修復。
- 要新增其他語言時，照 `zht` 的模式複製：一個語系物件、名稱表一筆、Steam 語言表一筆、
  語系代碼表一筆、偵測分支一段。
