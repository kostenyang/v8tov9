# ESXi 升級：獨立主機 (vLCM) / ISO 手動路 / VCF 納管規則

本資料夾補足主 README「③ ESXi 8.0.3 → 9.1」只講 `esxcli software profile update` 的部分，
收錄另外兩條實測過的路，以及**主機納管回 VCF 的產品規則**（決定你到底能不能用 LCM 升）。

實測日期 2026-09-08 ~ 2026-09-14，環境為 nested ESXi 9.1.0 → 9.1.1。

---

## 檔案

| 檔案 | 內容 |
|------|------|
| [`host-onboarding-and-standalone-upgrade.md`](host-onboarding-and-standalone-upgrade.md) | 主文（含 3 個附錄）：VCF commission 規則 / 單主機叢集 / **從 vCenter 用 vLCM 升獨立主機完整步驟** / Fleet Manager 對外部單機的能力邊界 / 1G NIC 與單條 uplink |
| [`ESXi91-ISO-Upgrade-Steps.md`](ESXi91-ISO-Upgrade-Steps.md) | ISO 掛載手動升級（`Upgrade ESXi, preserve VMFS datastore`），含 nested lab workaround |

---

## 三條升級路徑怎麼選

| 路徑 | 適用 | 文件 |
|------|------|------|
| `esxcli software profile update` | 有 depot、主機脫離 LCM、CPU 不受支援 | 主 README ③ |
| **vLCM image（獨立主機）** | 主機掛在 vCenter 下、不在 VCF 裡 | 本資料夾主文「從 vCenter 用 vLCM 升級『獨立主機』」 |
| **ISO 開機升級** | 沒有 vCenter、或要保留 VMFS 重裝 | `ESXi91-ISO-Upgrade-Steps.md` |

---

## 幾個會卡死人的實測結論

### 🔴 commission 時 ESXi build 必須「完全等於」VCF 當下的 BOM 版本
不是「大於等於」。主機比 BOM 新或舊都會被擋，得先把主機**降/升到剛好等於** BOM 再 commission。
解法（含直接從 depot 抓對應 build 升上去）在主文「擋點 2 的解法」。

### 🔴 VCF 不允許單主機叢集
所以「commission 一台單機進 VCF 再用 LCM 升級」這條路走不通 —— 產品規則擋死，不是參數問題。
單機只能改走 vCenter vLCM 或 ISO。

### 🔴 帶著開機中 VM 的主機要進 cluster
擋點與正解（unregister 即可、**不必刪 VM**）在主文「實測結果 B」，有可直接講給客戶的結論段。

### 🔴 depot token 要放在 URL **path** 裡
catalog 沒列出來的 ESX `-depot.zip` 其實抓得到；download tool 會 403 是因為它走**沒有 token** 的 URL。

```
https://dl.broadcom.com/<TOKEN>/PROD/COMP/ESX_HOST/<檔名>
```

### 🔴 vLCM API 走不完最後一哩：EULA
desired image 可以純 API 設定，但 remediate 前的 EULA 接受**只能 UI 點**。
主文記了 vSphere 9 UI 自動化的坑。

### ❌ Fleet Manager 管不到掛在 VCF 外面的獨立主機
能監控、能當 depot 提供升級素材，**但不能做 lifecycle / 升級**。
精靈 Step 5「Select Standalone Hosts」實際打開後的答案在主文「補完」段。

### 1G NIC 主機也能 commission
擋點在 operationsmanager 的 `HostHardwareValidator`，關掉速度檢查即可：

```properties
enable.speed.of.physical.nics.validation=false
```

⚠ 注意同一把 property **domainmanager 與 operationsmanager 各自讀自己的 application.properties**，
放錯檔案不會生效 —— 對照表在附錄 3。

---

> ⚠ Lab / 研究用途。這裡的 validation bypass 會讓環境脫離受支援狀態，正式環境請走官方流程。
