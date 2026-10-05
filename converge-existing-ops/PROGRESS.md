# m03「既有 VCF Operations + License Server 進管理網域」實作進度

> 2026-10-05。全程 UI 實作 + 逐步截圖(39 張,E:\9.1\doc-shots\m03-ops\)。

## 已完成
| 項目 | 結果 |
|------|------|
| DNS 正反解(15 + inst01 共 16 筆) | ✅ |
| 4 台 nested ESXi | ✅ 9.1.1.0.25714478 |
| vCenter `vcf-m03-vc01` 10.0.1.60 | ✅ 9.1.1.0.25712839 |
| 叢集 + VDS + vSAN 4000 GB + DRS/HA + 專用 vMotion(MTU 9000) | ✅ |
| VCF Operations `vcf-m03-ops01` 10.0.1.61 | ✅ 9.1.1.0.25679751,Online |
| **License Server `vcf-m03-lic01` 10.0.1.62** | ✅ 9.1.1.0.25679819,**Connected** |
| VCF Installer `vcf-m03-inst01` 10.0.1.71 | ✅ 已登入,精靈已開到 Prepare |

## 關鍵驗證(回答「既有 vROps + lic 怎麼轉 mgmt domain」)
精靈 **Introduction → Deployment Paths** 頁明寫:

> **Converging Existing Components** — If you intend to converge existing components
> (vCenter, NSX Manager or **VCF Operations**) into your newly deployed VCF fleet,
> subsequent steps will guide you.

所以答案是:**不是「import」,而是在「Deploy a new VCF fleet」這條路徑裡,
於後續 Prepare 步驟把既有元件指進去**。三個選項的 radio id 直接佐證:

| UI 標題 | radio id | 用途 |
|---|---|---|
| Deploy a new VCF fleet | `worload-type-VCF` | ← 本次用這個(可 converge 既有元件) |
| Deploy a new VCF Instance | `worload-type-VCF_EXTEND` | 已有 fleet,再加一個 VCF Instance |
| Deploy deferred components | `worload-type-VCF_COMPLETE` | 補裝初次部署時延後的元件 |

Prepare 階段 9 步:General Information / Hosts / Networks / **VCF Management** /
**vCenter** / Storage / Distributed Switch / NSX Manager / SDDC Manager
→ 既有 Operations 在「VCF Management」、既有 vCenter 在「vCenter」步驟指定。

## 待辦
1. Installer 的 depot 設定(目前 General Information 頁警告
   "Unable to determine the supported versions from the depot configuration")
2. Prepare 9 步填完 → Deploy(約 5 小時)

## 這一輪的新發現
1. **registration key 不需連外**:Operations → Manage → Licensing →
   Licenses & Registration → Register & License VCF Operations → START,
   本地就產生 base64 registration key(內含憑證 + `"hosts":["vcf-m03-ops01.home.lab"]`)。
   OVA 部署時貼進 "Unique Registration Key",開機後 appliance 自己回連 Operations。
   結果:License Servers 清單出現 `vcf-m03-lic01.home.lab / 9.1.1.0.25679819 /
   Not Registered / **Connected**`(Not Registered 指的是還沒跟 Broadcom 取授權,
   不是沒跟 Operations 接上)。
2. **重新進頁面會產生「新的」registration key,但不會讓舊的失效** —— 實測用舊 key
   部署的 appliance 照樣接得上。
3. **License Server 完全不需要連網際網路**:OVA 屬性說明原文寫
   "The license server does not connect to the internet, and only needs a network
   proxy if one is required to connect to VCF Operations"。
4. **9.1.1 SDDC Manager OVA 的 vami 屬性**:`ToHashTable()` 攤平後的 key 是
   `vami.ip0.SDDC-Manager`,但 PowerCLI 物件路徑是 `$ovf.vami.SDDC_Manager.ip0`
   —— 順序不同,照攤平 key 去 index 會拿到沒有 `.Value` 的物件。
   另外 `ip_address_version` 只收 `'IPv4'` 或 `'IPv4 and IPv6'`(大小寫敏感)。

## 🔴 CDP 自動化的三個坑(這次新踩)
| 症狀 | 真因 | 解法 |
|---|---|---|
| vSphere/Installer 的 ACTIONS、DEPLOYMENT WIZARD 下拉選單點不開 | Clarity 的 dropdown toggle 不吃 CDP 合成滑鼠 | `el.focus()` 後送**鍵盤 Enter**,而且要含 `char` 事件(只送 rawKeyDown/keyUp 無效) |
| 選單開了但選項點不下去 | 選單項目不吃 `Input.dispatchMouseEvent` | 用 DOM 事件序列 pointerover→pointerdown→pointerup→click→`el.click()` |
| VCF Installer 登入按鈕按了沒反應 | 同上,且 Angular 表單要真實輸入 | 欄位用 `Input.insertText` 真打字,然後在密碼欄按 **Enter** 送出 |

另外:OVF 精靈其實每次都有開起來,只是 `document.body.innerText` 讀不到 modal 內容
→ 一度連開了 4 個精靈疊在一起。判斷精靈是否開啟要查 `input[type=url]` 或截圖,不要信 innerText。

## 環境
- 只留 m03 在跑;w01 與 m02 已優雅關機(可隨時開回)

---

## 2026-10-05 20:00 — Installer depot 設定(新增)

### ✅ 已完成
- VCF Installer `vcf-m03-inst01` 10.0.1.71 登入、精靈走到 Prepare 第 1 步
- **Offline depot 已接上**:`https://10.0.0.61`,帳號 `vcfdepot`,狀態
  `DEPOT_CONNECTION_SUCCESSFUL`
- **16 個 VCF 9.1.1.0 元件開始下載**(約 64 GB):Cloud proxy 3.22G /
  Fleet lifecycle 582M / Identity broker 859M / License server 882M /
  Migration service engine 524M / Salt master 392M / Salt RaaS 654M /
  SDDC lifecycle 649M / SDDC Manager 2.40G / Software depot 879M /
  Telemetry 240M / VCF Automation 15.67G / VCF Operations 3.15G /
  VCF services runtime 16.11G / VMware NSX 8.26G / VMware vCenter 9.71G

### 🔴 新發現:offline depot 只吃 IP,不吃 FQDN(而且錯誤訊息會騙人)
同一組帳密、同一張憑證,四種 URL 實測:

| URL | 結果 |
|---|---|
| `https://vcf9depotserver.home.lab` | ❌ `VMWARE_DEPOT_OFFLINE_INVALID_URL` |
| `https://vcf9depotserver.home.lab/` | ❌ 同上 |
| `https://vcf9depotserver.home.lab/PROD` | ❌ 同上 |
| `https://vcf9depotserver.home.lab:443` | ❌ 同上 |
| **`https://10.0.0.61`** | ✅ **成功** |

錯誤訊息寫的是「The offline depot URL should be a valid URL **without query
parameters or fragments**」—— 但這些 URL 根本沒有 query 也沒有 fragment。
訊息是誤導的,實際擋點跟 hostname 有關(本機 DNS 正反解都正常,
憑證 SAN 也同時含 FQDN 與 IP)。**lab/客戶現場遇到這個錯,先改用 IP 試。**

### 🔴 CDP 打字的致命細節(修掉了)
`Input.dispatchKeyEvent` 如果拿 `ch.charCodeAt(0)` 當 `windowsVirtualKeyCode`,
`.` 的 charCode 是 **46**,而 **VK 46 = Delete** → 打 `home.lab` 會變成 `homelab`
(每個點都把前一個字刪掉)。只有 A-Z0-9 給正確 VK,其餘一律給 0。

另外 `Input.insertText` 雖然會把字放進欄位,但**不會讓 Angular 的 form control
變 dirty** → 驗證永遠 invalid、相依的 toggle 永遠 disabled。必須逐字送
keyDown/keyUp(帶 `text`)。

### 🛠️ 工具改用 Playwright(使用者建議)
`pip install playwright` + `connect_over_cdp("http://127.0.0.1:9222")`
**接上原本那顆有頭 Chrome**(不另開瀏覽器,登入狀態與截圖品質都保留)。
`page.select_option()` / `locator.check(force=True)` / `get_by_role()`
自動處理上面所有 Clarity 眉角,不用再自己量座標、自己送事件。
工具在 `E:\9.1\tools\pw.py`,流程腳本在 `E:\9.1\m03\pw_*.py`。

### ⚠️ 誠實記錄
depot 設定最後是**先用 API 試出「IP 可以、FQDN 不行」**才回 UI 做的。
UI 連試 3 次都只給那句誤導訊息,看不出真因;診斷用 API 讀回應是必要的。
現在 UI 上顯示的就是這組設定(Depot connection active / https://10.0.0.61)。

---

## 2026-10-05 21:05 — binaries 下載完 + Prepare 9 步填完 + 驗證中

### ✅ 完成
- 16 個元件、約 64 GB,**22 分鐘**下載完(20:17→20:39),全部 Success
- Prepare 9 步全部填完,精靈進到 **Validate & Deploy**(16 項驗證)
- 下載到完整的 deployment spec:`E:\9.1\m03\deployment-spec-m03.json`

### 🔑 最關鍵的發現:UI 精靈不會自動把「既有元件」標成既有
從精靈自己產生的 JSON 看:

```jsonc
"licenseServerSpec": { "hostname": "vcf-m03-lic01.home.lab" },        // 只有 hostname!
"vcfOperationsSpec": { ..., "useExistingDeployment": false, ... },
"vcenterSpec":       { ..., "useExistingDeployment": false },
"sddcManagerSpec":   { ..., "useExistingDeployment": false },
"vcfAutomationSpec": { ..., "useExistingDeployment": false }
```

- **License Server 是唯一「天生就指既有」的元件** —— 那一欄只有 FQDN,
  沒有密碼欄、沒有 useExistingDeployment,因為它本來就是外部 appliance。
  這直接回答了「我已經有 lic 怎麼辦」:**什麼都不用做,填 FQDN 就好**。
- **vCenter / VCF Operations 即使填既有的 FQDN,精靈還是給 `useExistingDeployment: false`**
  → 光是在 UI 打既有 FQDN **不等於** converge。真正的開關在 JSON。
  精靈首頁的「DEPLOY USING JSON SPEC」就是為了這個:
  下載 spec → 改 `useExistingDeployment: true` → 上傳。

### 🔴 救回一個會炸掉 lab 的 DNS 衝突
`vcf-m03-nsx01b` → **10.0.1.59**、`vcf-m03-nsx01c` → **10.0.1.60**
(別的 session 留下的殘影)——那正是本次 m03 的 **esx04** 和 **vCenter**。
NSX 三節點是必填,如果照著這兩個名字部下去,會直接打到正在跑的主機和 vCenter。
已改指 10.0.1.76 / 10.0.1.77(A+PTR 都改)。

其餘同 IP 多筆 A 記錄(vcf-ovl-esx01~04 對 10.0.1.62-65、vcf-m02-vsanhost 對
10.0.1.61)沒有動——反解 PTR 全部正確指向 m03 的名字,不影響驗證。

### 本次 m03 的網路設計
| 用途 | VLAN | 網段 | 備註 |
|---|---|---|---|
| ESX / VM Management | 0 | 10.0.0.1/23 | 沿用既有 |
| VCF Management Services IP Pool | - | 10.0.1.80-95 | 16 個 |
| VCF Automation IP Pool | - | 10.0.1.96-102 | 7 個 |
| vMotion | 0 | 192.168.35.1/24 (.11-.20) | MTU 9000,沿用既有 vmk1 |
| vSAN | 0 | 192.168.36.1/24 (.11-.20) | 新網段(原本 vSAN 走 vmk0) |
| NSX Overlay | 0 | 192.168.37.1/24 (.11-.30) | 新 |

新增 DNS:auto-vip .72 / auto-platform .73 / shared01 .74 / ops02 .75 /
nsx01b .76 / nsx01c .77

### 🔴 精靈其他要注意的
- **VCF Operations 一定要兩個節點**(primary + replica),單節點過不了必填驗證
  → 既有單節點的 ops01 要補一台 ops02,由 installer 部署後 join
- Hosts 這一步按 CONFIRM ALL FINGERPRINTS 後會跳
  「Resource Requirements Warning:資源夠用,但不到建議的 20% 餘裕」→ lab 可以 YES, PROCEED
- SDDC Manager 這一步會明講:「VCF Installer appliance 不在管理網域的主機上
  → 會另外部一台新的 SDDC Manager」。反之(installer 裝在管理網域主機上)
  它會把自己轉成 SDDC Manager
- 精靈按鈕的 class 每一步都不一樣,DOM 文字是 " Next "(大寫是 CSS text-transform),
  自動化要用 innerText 比對「可見且未 disabled」的那顆

---

## 2026-10-05 21:10 — 🔴 驗證結果:**Deployment Wizard 要的是乾淨主機**

16 項驗證,失敗的全部指向同一件事。錯誤碼原文:

| 錯誤碼 | 訊息 |
|---|---|
| `MANAGEMENT_VSWITCH_VMNIC_IN_USE` | has **0** Physical NICs connected to vSwitch0 (**Expecting 1**) |
| `VMNIC_IN_USE` | vmnic0 is in use (**Expecting to be unassigned**) |
| `MORE_THAN_ONE_VMKERNEL_CONFIGURED` | more than one ([vmk0, vmk1]) VM Kernel Adapters configured |
| `VSAN_PARTITION_FOUND_ON_HOST` | vSAN partition already exists |
| `VSAN_ZERO_SSD_DISKS_VALIDATION` | found zero SSD devices for SSD cache tier |
| `VSWITCH_EXISTS` | vSwitch 'vcf-m03-cl01-vds01' already exists |
| `IP_NOT_IN_USE` | **IP 10.0.1.60 allocated for vcf-m03-vc01.home.lab is already in use** |

最後那一條最關鍵:精靈把既有的 vCenter FQDN 當成「要新部署的目標」,
發現 IP 被佔用就報錯 —— 再次證實光填既有 FQDN **不等於** converge。

### 所以「既有 vROps + lic 要進管理網域」的真實答案

| 元件 | 做法 |
|---|---|
| **License Server** | ✅ **直接填 FQDN 就好**。精靈那一欄天生只有 hostname、沒有密碼、沒有 useExistingDeployment,因為它本來就是外部 appliance。spec 只產生 `{"hostname": "..."}` |
| **VCF Operations / vCenter** | ❌ UI 精靈不支援。要走 **DOWNLOAD JSON SPEC → 改 `useExistingDeployment: true` → DEPLOY USING JSON SPEC** |
| **已經有 vSphere 叢集(主機在既有 vCenter 裡)** | ❌ Deployment Wizard 完全不行,它要乾淨主機。這種要走 VCF Operations 的 **Import a vCenter**(= 之前 coverage lab 做的那條),結果是 **workload domain**,不是管理網域 |

### 乾淨主機的定義(精靈的驗證標準)
- vmnic0 掛在 **vSwitch0**(標準交換器),其餘 vmnic **未指派**
- 只有 **vmk0** 一張 VMkernel
- 磁碟**沒有 vSAN partition**,且至少一顆標記為 **SSD**
- 沒有同名的 VDS
- 所有要部署元件的 IP **都還沒被佔用**
