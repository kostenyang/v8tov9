# 把既有的 VCF Operations + License Server 併入 VCF 9.1.1 管理網域

> 實測環境:home.lab 巢狀實驗室 · VCF Installer **9.1.1.0.25713928** · 2026-10-05
> 全程 UI 操作,附精靈自己產生的 deployment spec 作為佐證。

## 結論(先講答案)

| 既有的東西 | 做法 | 結果 |
|---|---|---|
| **License Server** | 什麼都不用做,走 converge 路徑時**連欄位都不會出現** | ✅ 自動繼承 |
| **VCF Operations 9.1.1** | `Plan → Step 1 Existing Component` 勾「I have an existing VCF Operations 9.1 instance」 | ✅ UI 原生支援 |
| **Operations 所在的 vCenter** | 上一項勾下去會**自動勾選並鎖定**,不能不選 | ✅ 強制一併併入 |
| 只有裸 ESXi 主機 | Existing Component 什麼都不勾,走 greenfield | ⚠ 主機必須乾淨 |
| 既有 vSphere 叢集(想變 **workload domain**) | VCF Operations → Import a vCenter | — 不同流程 |

**🔑 開關在 `Plan` 階段的第一步,不在 `Prepare`。**
精靈分成 `Introduction → Plan → Prepare → Deploy`。跳過 Plan 直接進 Prepare,
精靈就是純 greenfield,對既有環境一定過不了驗證。

## Plan → Step 1 Existing Component

```
[v] I have an existing VCF Operations 9.1 instance
[v] I have an existing vCenter instance            ← 🔒 勾上面那個會自動勾選 + DISABLED
[ ] The vCenter instance is registered with NSX Manager
[v] I have an existing VCF Automation instance or I will deploy later   ← 跳過 VCFA,省 15.67 GB
```

勾完之後 **Prepare 從 9 步變 6 步**:

| Prepare 階段 | Greenfield | Converge |
|---|---|---|
| 步數 | 9 步 | **6 步** |
| Hosts | 填 4 台 FQDN + root 密碼 + 確認指紋 | ~~沒有這一步~~ |
| Storage | 選 vSAN 架構 / FTT / datastore 名稱 | ~~沒有這一步~~ |
| Distributed Switch | 選 profile、配 uplink、設 5 個 portgroup | ~~沒有這一步~~ |
| Networks | 7 個網段 + 2 個 IP pool | **只要 1 個**:VCF Management Services IP Pool |
| 驗證項目 | 16 項 | 12 項(多了 `Existing Components`、`Brownfield VCF Management Services validation`) |

## 兩條路徑產生的 spec 差異

精靈自己產生的(Review 頁 → DOWNLOAD JSON SPEC),不是手改的 —— 見 [`spec/`](spec/)。

```jsonc
// converge(勾了既有元件)
"vcfOperationsSpec": { "useExistingDeployment": true,
                       "nodes": [{ "hostname": "...ops01...", "type": "master" }] },  // 單節點就夠
"vcenterSpec":       { "useExistingDeployment": true, ... },
"sddcManagerSpec":   { "useExistingDeployment": false },   // 新部署
"nsxtSpec":          { "nsxtManagers": [ 1 台 ], "useExistingDeployment": false }
// licenseServerSpec / vcfAutomationSpec / hostSpecs / clusterSpec /
// datastoreSpec / dvsSpecs / networkSpecs  ← 這些 key 整個不存在
```

對照 greenfield:`useExistingDeployment` 全是 `false`,而且 Operations **強制兩節點**
(primary + replica),hostSpecs / clusterSpec / dvsSpecs / networkSpecs 全都要自己填。

## 驗證與部署結果

12 項驗證 → 10 Succeeded、2 可確認的 Warning、**零失敗**。精靈回報:

```
Successfully detected VCF Operations vcf-m03-ops01.home.lab.
Successfully detected vCenter vcf-m03-vc01.home.lab.
Selected cluster vcf-m03-cl01 as the deployment destination.
```

部署的五個里程碑(共 158 個子任務),最後兩個就是答案:

| 里程碑 | 子任務 |
|---|---|
| Deploy SDDC Manager | 16 |
| **Convert the existing vCenter to a new VCF instance** | 42 |
| Deploy and configure NSX | 70 |
| Deploy and configure VCF Management Platform | 21 |
| **Join the existing operations appliance** | 9 |

## 🔴 踩到的坑

| 症狀 | 真因 | 解法 |
|---|---|---|
| 既有環境餵進精靈,驗證六項全掛 | 跳過了 Plan 階段,走成純 greenfield | Plan → Step 1 勾選既有元件 |
| 填了既有 vCenter 的 FQDN 卻報 `IP_NOT_IN_USE` | greenfield 路徑把 FQDN 當成「要新部署的目標」 | 同上;`useExistingDeployment` 不必手改 JSON |
| offline depot 接不上(`VMWARE_DEPOT_OFFLINE_INVALID_URL`) | **只吃裸 IP 不吃 FQDN**;訊息講 query/fragment 是誤導 | URL 改成 `https://<IP>` |
| 主機瘦身後 appliance 開不了機 | HA admission control 的 25% 失效移轉保留吃不下 | 關掉該叢集的 HA 或 admission control |
| nested vMotion 卡在 0% | CPU 超配造成收端被餓死(**不是網路**) | 降低 vCPU 總量 |

**差點出事**:DNS 裡別的測試留下的殘影 `vcf-m03-nsx01b/c` 指向 `10.0.1.59`/`10.0.1.60`
—— 那正是本次環境的 esx04 與 vCenter。NSX 在 HA 模式三節點是必填,照著部下去會直接打到
正在跑的機器。**部署前務必逐一確認要用的 FQDN 沒有指到活著的機器。**

### greenfield 路徑的「乾淨主機」定義(實測錯誤碼)

| 錯誤碼 | 要求 |
|---|---|
| `MANAGEMENT_VSWITCH_VMNIC_IN_USE` | vmnic0 掛在 `vSwitch0`,剛好 1 張 |
| `VMNIC_IN_USE` | 其餘 vmnic 未指派 |
| `MORE_THAN_ONE_VMKERNEL_CONFIGURED` | 只能有 vmk0 |
| `VSAN_PARTITION_FOUND_ON_HOST` | 磁碟不能有 vSAN partition |
| `VSAN_ZERO_SSD_DISKS_VALIDATION` | 至少一顆標記成 SSD |
| `VSWITCH_EXISTS` | 不能有同名的 VDS |

`scripts/Check-CleanHosts.ps1` 就是照這六項寫的檢查工具。

## 目錄

```
doc/        完整報告 docx(29 頁 / 36 圖)+ 產生它的 build script
diagrams/   三張自製示意圖的 HTML 原始檔與 PNG
shots/      79 張 UI 逐步截圖
spec/       精靈產生的 deployment spec(converge / greenfield 對照,密碼已遮蔽)
scripts/    部署與檢查腳本(PowerShell / Python / bash)
```

### scripts/ 重點

| 檔案 | 用途 |
|---|---|
| `Check-CleanHosts.ps1` | 照 Installer 的六項標準檢查主機是否「乾淨」 |
| `Deploy-M03B-NestedESXi.ps1` | 從 OVA 部一批全新乾淨的 nested ESXi |
| `Shrink-OldM03.ps1` | 把 nested 主機瘦身(避免 CPU 超配) |
| `pw.py` / `iw.py` | Playwright 接現有 Chrome 操作 VCF UI 的小工具 |
| `pw_wizard_m03b.py` | 一次填完 Deployment Wizard 的 Prepare 各步 |
| `watch-deploy.py` / `watch-validation.py` / `watch-binaries.py` | 進度輪詢 |

> 所有腳本的密碼都改成讀環境變數(`LABPASS` / `VIPASS` / `ESXPASS` / `DEPOT_PASS`),
> spec 裡的密碼欄位已遮成 `<REDACTED>`,截圖裡的 registration key 已塗黑。

## UI 自動化筆記

本文的操作與截圖以 **Python Playwright 連上既有的有頭 Chrome(CDP 9222)** 完成。
自己刻 CDP 事件會踩到的坑(Playwright 全部自動處理):

- 下拉選單(ACTIONS、DEPLOYMENT WIZARD)**只吃鍵盤 Enter**,而且要含 `char` 事件
- 選單「項目」反過來只吃 DOM 事件序列
- `Input.insertText` 不會讓 Angular form control 變 dirty → 驗證永遠 invalid
- 🔴 逐字 `dispatchKeyEvent` 拿 `charCodeAt` 當 VK:`.` 是 46,**VK 46 = Delete**
  → `home.lab` 會打成 `homelab`
- 對話框會非同步重新排版,座標要在點之前重量
- modal 內容不會出現在 `document.body.innerText` → 容易誤判「精靈沒開」而疊開好幾個
- NEXT 按鈕的 class 每一步都不同,DOM 文字是 `" Next "`(大寫是 CSS `text-transform`)
