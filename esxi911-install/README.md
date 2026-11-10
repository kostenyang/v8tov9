# ESXi 9.1.1 全新安裝 Step-by-Step（原廠 ISO、實體伺服器情境）

從 ISO 開機 → 安裝精靈 → DCUI 設定管理網路 → Host Client 初始設定（NTP / DNS / VMFS datastore / 重產主機憑證）→ 安裝後驗證與驗收表，全程 **60 張實機截圖**。

文字以**實體伺服器**安裝為前提寫（BMC 遠端主控台 / Virtual Media 情境）；截圖取自外層 vCenter 上的 nested VM `esx911-demo`，安裝程式、DCUI、Host Client 畫面與實體機完全相同。

實測日期 2026-10-27，`VMware-VMvisor-Installer-9.1.1.0.25714478.x86_64.iso`。

---

## 檔案

| 檔案 | 內容 |
|------|------|
| [`ESXi-9.1.1-Install-Step-by-Step.md`](ESXi-9.1.1-Install-Step-by-Step.md) | 主文（中文）：規劃值表 → 安裝前準備 → ISO 開機 → 安裝精靈 → DCUI → Host Client → 驗證 → 常見問題 |
| [`ESXi-9.1.1-Install-Step-by-Step-en.md`](ESXi-9.1.1-Install-Step-by-Step-en.md) | 主文英文版（同結構、同截圖） |
| 📄 [`doc/ESXi-9.1.1-Install-Step-by-Step.docx`](doc/) | ★ **交付文件**（中文 39 頁）。同目錄有 PDF，以及英文版 `-EN.docx` / `-EN.pdf`（38 頁） |
| [`img/`](img/) | 60 張原始截圖：安裝程式與 DCUI 為 VM console 擷取（4:3），Host Client 為瀏覽器截圖 |
| [`scripts/`](scripts/) | `k.sh`（govc 送按鍵 / 字串 + 抓 console）、`cap-loop.sh`（每 N 秒抓 console、同畫面去重，用來抓安裝進度等過場畫面）、`md2docx-stepbystep.js`（主文 md → docx，`MD2DOCX_LANG=en` 出英文版） |

> 🔑 腳本內的密碼已改為 `<PASSWORD>`；主文不列 root 密碼，IP 為 RFC1918 私網。

---

## 實測踩到的坑（都已寫進主文）

- **NTP 啟動原則**：Host Client 啟用 NTP 後，NTP Daemon 的啟動原則仍是 *Start and stop manually* → 主機重開機 NTP 不會自動起來。要到 Services 把 ntpd 改成 *Start and stop with host*。
- **重產主機憑證**：安裝完的自簽憑證 CN 停在 `localhost.localdomain`。跑 `/sbin/generate-certificates` 並重啟 hostd / vpxa 後，443 仍送舊憑證 —— **還要重啟 rhttpproxy（9.x 是 Envoy）** 才會換新。要加入 vCenter / VCF 前必做。
- **不在支援清單的 CPU**：Broadwell Xeon E5-2682 v4 在 9.1.1 安裝程式會跳 `CPU_SUPPORT WARNING`（KB 82794），可強制繼續安裝；正式環境請用 Compatibility Guide 上的硬體。
- **BMC HTML5 主控台的 F11**：常被瀏覽器攔成全螢幕，要用主控台工具列的虛擬鍵盤或按鍵巨集送出。

---

## 截圖怎麼抓（安裝程式 / DCUI 沒有瀏覽器可用）

用 `govc` 對 VM console 送按鍵、抓畫面：

```bash
govc vm.keystrokes -vm esx911-demo -c KEY_F11            # 送功能鍵（KEY_ENTER / KEY_DOWN / KEY_F2 ...）
govc vm.keystrokes -vm esx911-demo -s "text"             # 送字串
govc vm.console -capture E:/path/NN-name.png esx911-demo # 擷取 console 成 PNG
```

- Windows 版 govc 的輸出路徑要寫 `E:/...`，不能寫 `/e/...`（`MSYS_NO_PATHCONV=1` 下不會轉）。
- 兩個 `-capture` 同時打會回 409，`k.sh shot` 內建重試。
- 過場畫面（Scanning、安裝進度、重開機）用 `cap-loop.sh <間隔秒> <持續秒>` 連拍再挑。
- Host Client 畫面用 CDP 接有頭 Chrome 截圖（repo 其他資料夾同一套做法）。
