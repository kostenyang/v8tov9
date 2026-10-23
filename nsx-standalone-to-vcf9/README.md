# 獨立 NSX 手動部署 → 升級 9.1.1 → 轉入 VCF 9.1.1：完整實作手冊

> Lab 實作：2026-10-22。環境 `m07`，nested on VCF lab。
> 截圖目錄 `E:\9.1\doc-shots\m07-r3\`，CLI 輸出與 JSON 證據同目錄。

**目錄**

1. 這份文件在解什麼問題
2. 環境與媒體來源
3. Part A — 手動建置 5.2.1 BOM（不用 Cloud Builder bring-up）
4. Part B — Upgrade Coordinator 升級流程（UI step-by-step）
5. Part C — `vcfEnvironmentCheck`（31944）關卡
6. Part D — `watermark-curl-v1.sh` 使用說明
7. Part E — 升級 NSX 到 9.1.1
8. Part F — 轉入 VCF 9.1.1（converge）
9. 附錄 — 踩過的坑

---

## 1. 這份文件在解什麼問題

一套**從未進過 VCF** 的獨立（standalone）NSX，想用 Upgrade Coordinator（UC）升到 9.1.1，
預檢會出現一個**無法 acknowledge** 的 Error：

```
[FAILURE] 31944  needs_ack=False
Upgrade of standalone NSX deployment to VCF 9.X is not supported.
Please import your NSX deployment into VCF before proceeding with the upgrade.
Minimum version for importing into VCF is NSX 4.1.0.2+.
```

本文記錄：這個檢查**實際在檢查什麼**（拆 UC jar 實證）、Cloud Builder 部署與手動部署的差異、
lab 環境如何驗證與繞過、以及後續升級與轉入 VCF 的完整流程。

> ℹ️ **現階段定位。** 用 watermark 繞過 `vcfEnvironmentCheck`，目前是**手動 / lab 驗證**做法，
> 尚未是官方自動化路徑；**RD 正評估把它標準化成受支援流程**。
> 今日既有官方路徑：獨立 NSX 先 import / converge 進 VCF（KB440630），再走 VCF lifecycle 升級。

---

## 2. 環境與媒體來源

### 2.1 環境（lab 值）

| 元件 | 版本 | 位址 |
|---|---|---|
| nested ESXi ×3 | 8.0U3b (24280767) | 10.0.1.161-163，cluster `m07-cl01` |
| vCenter | 8.0U3c (24305161) | `vcf-m07-vc01` 10.0.1.164 |
| NSX（單節點，medium） | 4.2.1.0.0.24304122 | node 10.0.1.166 / VIP 10.0.1.165 |
| 升級目標 | 9.1.1.0.0.25691509 | depot `http://<depot>:8888/PROD/COMP/NSX_T_MANAGER/` |

### 2.2 🔑 媒體來源：Cloud Builder appliance 內建

VCF 5.2.1 BOM 的三個安裝媒體都在 Cloud Builder appliance 裡，不必另外下載：

```
/mnt/iso/sddc-foundation-bundle-5.2.1.0-24307856/
├── vcenter_ova/VMware-VCSA-all-8.0.3-24305161.iso     12.4 GB
├── nsxt_ova/nsx-unified-appliance-4.2.1.0.0.24302016.ova  12.1 GB
└── esx_iso/VMware-VMvisor-Installer-8.0U3b-24280767.x86_64.iso
```

Cloud Builder 本身也有 `/usr/bin/ovftool`，所以**整個部署可以在 CB 上執行**，媒體不必落地到本機。

### 2.3 🔴 nested 環境的儲存設定（關鍵）

第一輪用 **FTT1**（預設鏡像）時，NSX Manager 升級跑到 Data Migration 會因為
nested vSAN 的寫入放大而 **I/O hung**（console 出現 `df` / `systemd-udevd` blocked 240–360 秒），
升級卡死。

改用 **FTT0**（單份、不鏡像）後，同樣的步驟全部正常，且速度約快一倍：

| 步驟 | FTT1 | FTT0 |
|---|---|---|
| NSX OVA 部署 | 40 分 | 20 分 |
| `.pub` 下載 + UC 升級 | 15 分 | 8 分 |
| vSAN 可用容量（3×1500 GB） | 3.0 TB | 4.5 TB |

設定方式：在第一台 ESXi bootstrap vSAN 時就把預設 policy 設成 FTT0，
之後建立的 vCenter / NSX 都會繼承。

```bash
esxcli vsan policy setdefault -c vdisk -p "((\"hostFailuresToTolerate\" i0) (\"forceProvisioning\" i1))"
```

---

## 3. Part A — 手動建置 5.2.1 BOM

不使用 Cloud Builder bring-up，全部手動建立，這樣得到的 NSX 才是「獨立部署」狀態（沒有 watermark）。

### 3.1 nested ESXi ×3

`Deploy-NestedESXi.ps1`（William Lam 的 Nested ESXi OVA）。本輪規格：

```
20 vCPU / 128 GB RAM / cache 120 GB / capacity 1500 GB（thin）
三台都放在同一顆較快的實體碟
```

🔴 兩個關鍵：
- `guestinfo.createvmfs = false` — 碟要留給 vSAN，不能先建 VMFS
- device 順序固定 `[0]` 開機碟、`[1]` cache、`[2]` capacity，**不要用容量排序挑碟**

### 3.2 bootstrap 單節點 vSAN（FTT0）

CLI 版的 `vcsa-deploy` 需要先有 datastore，所以在第一台 ESXi 上手動把 vSAN 拉起來：

```bash
CAP=<capacity-disk-naa>; CACHE=<cache-disk-naa>
P="((\"hostFailuresToTolerate\" i0) (\"forceProvisioning\" i1))"

esxcli vsan storage tag add -d $CAP -t capacityFlash
esxcli vsan cluster new
esxcli vsan storage add -s $CACHE -d $CAP
for c in cluster vdisk vmnamespace vmswap vmem; do
  esxcli vsan policy setdefault -c $c -p "$P"
done
```

> 🔴 **預設 policy 設 FTT0 是本輪最重要的改變**，理由見 2.3。
> 之後建立的 vCenter 與 NSX 都會繼承這個 policy。

> 💡 若改用 vCSA GUI 安裝程式的「Install on a new vSAN cluster」，Claim disks 頁會出現
> **0 顆碟**（installer log：`TypeError: Cannot read properties of null (reading 'find')`），
> 即使 `vdq -q` 顯示三顆都 Eligible。先 bootstrap 再選 existing datastore 可繞過。

### 3.3 vCenter 8.0U3c（在 Cloud Builder 上用 CLI 安裝）

```bash
# 在 Cloud Builder 上掛載 ISO
mount -o loop,ro /mnt/iso/sddc-foundation-bundle-.../vcenter_ova/VMware-VCSA-all-8.0.3-24305161.iso /mnt/vcsa

# 背景執行安裝
setsid nohup /mnt/vcsa/vcsa-cli-installer/lin64/vcsa-deploy install \
  --accept-eula --acknowledge-ceip --no-ssl-certificate-verification \
  --log-dir /root/m07/vcsa-log /root/m07/vcsa-m07.json \
  > /root/m07/vcsa-deploy.out 2>&1 < /dev/null &
```

JSON 範本取自 `/mnt/vcsa/vcsa-cli-installer/templates/install/embedded_vCSA_on_ESXi.json`，
`datastore` 填 `vsanDatastore`，`deployment_option` 用 `tiny`。本輪耗時約 32 分鐘。

### 3.4 建立叢集

`Build-M07Cluster.ps1`：建 Datacenter / Cluster、開 vSAN、加入三台主機、
vmk0 啟用 vMotion + vSAN、建 disk group、建 VDS（8.0.0 / MTU 9000 / vmnic1 當 uplink）、
DRS 全自動、HA 關閉、靜音 vSAN HCL 類健康檢查。

> 🔴 PowerCLI 13.5 的 `Set-VsanClusterConfiguration` **已經沒有 `-VsanEnabled` 參數**，
> 要改用 `Set-Cluster -VsanEnabled $true`。
> 另外 `Set-VsanClusterConfiguration -StoragePolicy` 是設效能服務的 stats 物件，
> 不是設叢集預設 policy，效能服務沒開時還會報錯——FTT0 要在 3.2 的 esxcli 階段就設好。

### 3.5 NSX 4.2.1（medium）

在 Cloud Builder 上用 `ovftool` 部署：

```bash
ovftool --acceptAllEulas --noSSLVerify --allowExtraConfig --X:injectOvfEnv --powerOn \
  --diskMode=thin --deploymentOption=medium --name=<nsx-vm-name> \
  --datastore=vsanDatastore '--network=<portgroup>' \
  '--prop:nsx_role=NSX Manager' '--prop:nsx_hostname=...' '--prop:nsx_ip_0=...' \
  （其餘 nsx_* 屬性省略） \
  /mnt/iso/.../nsxt_ova/nsx-unified-appliance-4.2.1.0.0.24302016.ova \
  'vi://<user>:<pass>@<vcenter>/<dc>/host/<cluster>/'
```

> 🔴 **nested 環境一定要用 `medium`（6 vCPU / 24 GB）。**
> `small`（4 vCPU / 16 GB）會因記憶體不足導致 telemetry / phonehome 服務起不來，
> 後續任何需要這些服務的動作都會失敗。

### 3.6 Compute Manager 與 host prep

`Configure-M07Nsx.ps1`：註冊 Compute Manager → 建 uplink profile →
建 TEP IP pool → 建 Transport Node Profile → 套用到叢集做 host prep。

> 🔴 註冊 Compute Manager 時要同時開啟 **`create_service_account: true`** 與
> `set_as_oidc_provider: true`。否則 MP 升級啟動時會被擋：
> `Pre-upgrade checks failed for MP: Either service account is disabled or trust is disabled for compute managers`（30955）。
> 事後補救方式是 PUT 更新 Compute Manager，等 registration 回到 REGISTERED / UP 後重跑預檢。

驗證：每台主機應有 `vmk10`（TEP）取得 IP、24 個 nsx VIB，
主機之間 `vmkping ++netstack=vxlan -d -s 1572` 應該全通。

## 4. Part B — Upgrade Coordinator 升級流程（UI step-by-step）

NSX UI →「System」→「Lifecycle Management」→「Upgrade」。

### 4.1 起始畫面

Upgrade 頁顯示目前版本與五個階段（Check Upgrade Readiness / Prepare for Upgrade /
Upgrade Edges / Upgrade Hosts / Upgrade NSX Manager），下方有 **CHECK UPGRADE READINESS**
與 **UPGRADE** 兩個按鈕。〔圖 `03-upgrade-start.png`〕

### 4.2 Step 1 — 預檢套件（`.pub`）

按 **UPGRADE** 進入「Check Upgrade Readiness」。這一步要的是 **`.pub`（pre-check bundle，約 1 GB）**，
不是 `.mub`。選 **Download with Remote URL**，填 depot 上的 `.pub` 網址後按 **DOWNLOAD**。
〔圖 `04-upgrade-wizard.png`、`05-pub-url-filled.png`、`06-pub-downloading.png`〕

> 🔑 `.pub` 上傳完成後，**Upgrade Coordinator 會自動升級到目標版本**（本例 9.1.1.0.25691516），
> 期間 manager 服務重啟、API 回 500 數分鐘。這一步不可逆，要退回只能用 appliance 內部的
> `call_uc_rollback` 腳本。〔圖 `07-uc-upgraded.png`〕

### 4.3 Step 2 — 執行預檢

按 **RUN PRE-CHECKS**，從下拉選單選 **All Pre-Checks**（也可只跑 NSX Manager / Hosts /
Edges / Finalize 單項）。〔圖 `08b-precheck-menu.png`〕

四個群組依序跑完。獨立部署的 NSX 會得到：

```
NSX Manager   1 Error  4 Warning
Hosts         Success
Edges and VNAs Success
Finalize Upgrade Success
```

上方出現紅色橫幅「Resolve/Acknowledge all pre-check issues to proceed with the upgrade.」
〔圖 `10-prechecks-done.png`〕

點 **1 Error** 看明細：`Component Level Issues (1)`、`Successful Checks (32)`，
Severity 欄是 **Error**，**Action 欄是空的**（代表無法 acknowledge）。〔圖 `11-error-31944-detail.png`〕

這就是第 5 節要處理的 `vcfEnvironmentCheck`。

### 4.4 Step 3 — 升級套件（`.mub`）

預檢沒有 Error 之後 **NEXT** 才會啟用。進入「Prepare for Upgrade (.mub file)」，
同樣用 Remote URL 填 `.mub`（約 9 GB）網址後 **DOWNLOAD**。
〔圖 `15-mub-url-filled.png`、`16-mub-downloading.png`〕

> ⚠️ `.pub` 與 `.mub` 的版本必須相同，UI 上也有提示。
> `.mub` 下載後會再次重啟 UC；`.mub` 實體檔案落在 **`/image/upgrade-coordinator/`**（不是 `/repository`），
> 盯錯目錄會以為卡住。完成後 UI 文字可能沒更新，**重整頁面**即可看到正確狀態。

### 4.5 Step 4 — Upgrade Summary

重整後進入「Upgrade Summary」，每個元件都解析出目標版本：

| 元件 | 目標版本（本例） |
|---|---|
| MP | 9.1.1.0.25691516 |
| HOST | 9.1.1.0.25691512 |
| EDGE | 9.1.1.0.25691514 |
| FINALIZE_UPGRADE | 9.1.1.0.25691509 |

按 **BEGIN UPGRADE** → 跳出 **Foundation Agreement（EULA）**。
〔圖 `17-upgrade-summary.png`、`19-eula.png`〕

> 🔴 EULA 的 **AGREE AND CONTINUE 不是靠捲到底啟用**，而是要勾選
> 「I understand and accept the terms of the license agreement」。

### 4.6 Step 5 — Acknowledge 警告

接受 EULA 後會解析各元件目標版本，再按 **NEXT** 進入「NSX Managers」分頁。
此時 **START UPGRADE 仍是灰的**，因為預檢的 Warning 尚未 acknowledge。

回「Check Upgrade Readiness」→ 點 **4 Warning** → 每筆按 **ACKNOWLEDGE** →
回「NSX Managers」，**START UPGRADE** 就會啟用。〔圖 `24-warning-ack-dialog.png`、`25-warnings-acked.png`〕

### 4.7 Step 6 — 升級 NSX Manager

**START UPGRADE** → 確認對話框「Start Upgrade」列出注意事項（節點會依序重開、
建議先做遠端備份、升級期間不要 SSH 進 `/config`），**勾選 "Confirm to start the upgrade now."**
後 **START** 才會啟用。〔圖 `26b-confirm-start.png`〕

MP 升級分五個步驟：

```
1 Pre-Upgrade Check
2 Prepare Nodes
3 Node OS Upgrade
4 Data Migration        ← nested 慢碟環境容易卡在這
5 Notify Manager completion
```

〔圖 `27-mp-upgrade-progress.png`〕

## 5. Part C — `vcfEnvironmentCheck`（31944）關卡

### 5.1 這個檢查實際在檢查什麼

拆開 Upgrade Coordinator 9.1.1 的實作：

```
/opt/vmware/upgrade-coordinator-tomcat/webapps/upgrade-coordinator/WEB-INF/lib/
  libnsx-upgrade-plugins.jar
    → com.vmware.nsx.management.upgrade.plugin.mp.task.VcfEnvironmentInspectionTask
```

`execute()` 只做一件事：呼叫 `UpgradePersistenceService.getNsxManagerDeploymentInfo()`
讀 NSX 資料庫裡的 `NsxManagerDeploymentInfo`。讀不到就：

```
logger.warn("Upgrade to 9.x is blocked for non vCF environments")
→ FAILURE  NsxUpgradePluginsErrorCode.NOT_VCF_ENVIRONMENT  (31944)
```

**沒有讀任何其他欄位**，也沒有去問 vCenter 或 SDDC Manager。

### 5.2 這筆資料的 API

`NsxManagerDeploymentInfo` 對應的 NSX API 是 **`/api/v1/watermark`**。
API 文件對這個 schema 的描述是「Deployment Details of NSX Manager deployed via VCF」，
必填欄位 `instance_id`、`managed_by`、`log_token`、`deployed_by`，支援 GET / POST / PUT / DELETE。

由 **Cloud Builder / SDDC Manager 在部署 NSX 時寫入**。因為只讀 NSX 自己的 DB，
所以 **SDDC Manager 事後關機、甚至整台不存在，都不影響這個檢查的結果**。

### 5.3 三組環境對照（同一個 NSX build 4.2.1.0.0.24304122）

| | A：Cloud Builder 部署 | B：手動部署 | C：手動部署 + 補 watermark |
|---|---|---|---|
| `GET /api/v1/watermark` | 200 | **404**（error 600） | 200 |
| 9.1.1 預檢結果 | 0 Error / 4 Warning | **1 Error（31944）** / 4 Warning | 0 Error / 4 Warning |
| Successful Checks | 33 | 32 | 33 |
| UI 可否繼續升級 | 可 | **NEXT 永遠灰的** | 可 |

A 組的 watermark 內容（Cloud Builder 5.2.1 寫的）：

```json
{
  "deployed_by": "VMware Cloud Foundation - VSRN",
  "version": "5.2.1.0-24307856",
  "managed_by": "<SDDC Manager FQDN>",
  "instance_id": "<uuid>",
  "log_token": "VCF",
  "resource_type": "NSXManagerDeploymentInfo"
}
```

三組共同的 4 個 Warning（都可 acknowledge）：

| 錯誤碼 | 內容 |
|---|---|
| 31911 | Context Profile `/infra/context-profiles/FPROT` 含不支援的 APP ID（KB410572） |
| 36014 | VCF 9.0 起不再支援 NSX-V → NSX 遷移 |
| 31935 | MP API（`/api` 開頭）已棄用 |
| 31954 | 升級會停用預設 DFW 規則 "Malicious IP at Destination Rule" |

### 5.4 🔑 補 watermark 的副作用

補上 watermark 之後，NSX UI 最上方的橫幅會變成：

> This NSX Manager is managed by SDDC Manager. Making modifications directly in NSX may impact some SDDC Manager workflows.

〔圖 `17b-managed-by-sddcm-banner.png`〕

也就是說，**這筆紀錄的影響不只是升級預檢**，NSX 整體會把自己視為受 VCF 管理的元件 ——
這其實與 VCF 的管理模型一致（converge 後 VCF 也會寫入同語意的 metadata）。
現階段手動寫入屬 lab 驗證；要知道它的完整影響範圍，也正是 RD 評估標準化時要界定清楚的地方。

---

## 6. Part D — `watermark-curl-v1.sh` 使用說明

> ℹ️ **現階段定位（非最終）。** 以下子命令會對 NSX 寫入一筆 VCF watermark，用來繞過
> `vcfEnvironmentCheck (31944)`，讓**獨立部署的 NSX** 能跑 9.x 升級。目前這是**手動 / lab 驗證**做法，
> 還不是官方自動化流程；**RD 正評估把它標準化**，故本段以中性記錄「它怎麼運作、有何影響」，而非禁用。
>
> **converge 實證（2026-10-23, m07）**：把這台（已寫入 watermark 的）NSX converge 進 VCF 9.1.1 後，
> 里程碑「Convert existing vCenter+NSX → VCF instance」完成，**VCF 會寫入自己真正的管理 metadata**，
> 蓋掉這裡手動寫的那筆 —— 代表 VCF 本就會管理這筆 watermark，與手動寫入語意一致（這也是為何有標準化空間）。
> 今日既有官方路徑：NSX 停在 VCF BOM 支援版本、或先 import/converge 進 VCF 再走 VCF lifecycle 升級。


### 6.1 可以在哪裡執行（四種環境實測）

| 環境 | bash | curl | python | uuidgen | `NSX=` 要填 | 結果 |
|---|---|---|---|---|---|---|
| Windows Git Bash | ✅ | ✅ | ✅ | ❌（走 python fallback） | NSX 的 IP/FQDN | ✅ |
| Ubuntu 20.04 | 5.0.17 | ✅ | **只有 python3** | ✅ | NSX 的 IP/FQDN | ✅ |
| Photon OS（Cloud Builder） | 5.0.0 | ✅ | ✅ | ✅ | NSX 的 IP/FQDN | ✅ |
| **NSX appliance 本機** | 5.1.16 | ✅ | ✅ | ✅ | **`localhost`** | ✅ |

腳本沒有相依 `jq`，python 偵測寫成 `command -v python3 || command -v python`
（Ubuntu 20.04 沒有 `python`），UUID 有三層 fallback（`uuidgen` → `/proc/sys/kernel/random/uuid` → python），
所以上述環境都不必額外安裝東西。

在 NSX 上執行時，用 `admin` 帳號 SSH 進去會落在 NSX CLI 而不是 bash，
要先打 `st en`（start enable）才有 shell；用 `root` 則直接是 bash。

### 6.2 六個子命令

| 命令 | 作用 | 會不會改動 |
|---|---|---|
| `get` | 查 watermark | 否 |
| `post` | 寫入 watermark | **會**，需按 y |
| `precheck` | 重新執行預檢 | 否 |
| `status` | 各元件預檢狀態 | 否 |
| `failures` | 列出所有 Error / Warning | 否 |
| `delete` | 移除 watermark（還原） | **會**，需按 y |

### 6.3 `get`

```bash
# 互動：會問 NSX 位址與密碼
bash watermark-curl-v1.sh get

# 或用環境變數跳過詢問
NSX=10.0.1.165 NSX_PASS='<password>' bash watermark-curl-v1.sh get
```

兩種結果：

```
HTTP 200  → 有 watermark，UC 認定為 VCF 環境，31944 不會出現
HTTP 404  → 沒有（error_code 600），預檢會被 31944 擋住
HTTP 000  → curl 沒收到任何回應，見 9.3
```

### 6.4 `post`

```bash
bash watermark-curl-v1.sh post
```

會依序詢問，直接按 Enter 可用預設值：

```
managed_by, SDDC Manager FQDN to record [sddcm.example.local]:
version, Cloud Builder / SDDC Manager build [5.2.1.0-24307856]:
POST watermark (...) to 10.0.1.165? lab only, unsupported [y/N]: y
```

成功回 `HTTP 201`。環境變數 `MANAGED_BY`、`WM_VERSION` 可跳過前兩問，
**但 y/N 確認一定會跳**（刻意保留）。要完全無人值守請用原版 `watermark-curl.sh`。

欄位說明：

| 欄位 | 值 | 可否變更 |
|---|---|---|
| `deployed_by` | `VMware Cloud Foundation - VSRN` | 腳本固定（照 Cloud Builder 實際寫入的字串） |
| `version` | `5.2.1.0-24307856` | `WM_VERSION` |
| `managed_by` | SDDC Manager FQDN | `MANAGED_BY`。**這台不需要真的存在** |
| `instance_id` | 每次自動產生 UUID | 自動 |
| `log_token` | `VCF` | 腳本固定 |

> 重複執行 `post` 會新增另一筆（`id` 與 `instance_id` 不同），不會報錯也不會覆蓋。
> 要乾淨重做請先 `delete`。寫入後**必須重跑預檢**才會生效。

### 6.5 完整循環（lab 實測）

```bash
export NSX=10.0.1.165 NSX_PASS='<password>'

bash watermark-curl-v1.sh get        # HTTP 404
bash watermark-curl-v1.sh post       # y → HTTP 201
bash watermark-curl-v1.sh get        # HTTP 200
bash watermark-curl-v1.sh delete     # y → HTTP 204
bash watermark-curl-v1.sh get        # HTTP 404（確認還原成功）
bash watermark-curl-v1.sh post       # 再補回來
bash watermark-curl-v1.sh precheck   # 重跑預檢
bash watermark-curl-v1.sh status     # 等到四個元件都 COMPLETED
bash watermark-curl-v1.sh failures   # count 4，31944 已消失
```

實測輸出存於 `m07-r3-watermark-cycle.txt`。

## 7. Part E — 升級 NSX 到 9.1.1 與 vCenter 到 9.1.1

### 7.1 NSX（UC 流程走完）

補好 watermark、Pre-Check 通過後，依序：

1. **NSX Manager（MP）**：Upgrade Summary → BEGIN UPGRADE → acknowledge 4 個 Warning → NSX Managers 分頁 START UPGRADE。
   五步：Pre-Upgrade Check → Prepare Nodes → Node OS Upgrade → Data Migration → Notify Manager completion。
   本例 FTT0 nested，MP 約 45 分；升級完成後 `/api/v1/node/version` 的 software 已是 9.1.1，但 **Product Version 要到 Finalize 才翻**。
2. **Hosts**：Hosts 分頁 START UPGRADE（Maintenance 模式、Serial）。3 台各約 30 分。
3. **Edges and VNAs**：🔴 **即使沒有 Edge，也要按一次 START UPGRADE**。否則 EDGE 停在 NOT_STARTED，Finalize 會被擋：
   `Cannot upgrade component FINALIZE_UPGRADE, until EDGE component has been upgraded successfully.`
   沒有 Edge 時這一步會瞬間 SUCCESS。
4. **Finalize Upgrade**：Finalize 分頁 START FINALIZE UPGRADE。五步（local backup / Notify Completion /
   Product Version Update / Unpin API / Unpin UI），約 2 分。完成後 **Product Version = 9.1.1.0.25691509**，
   Upgrade 頁六個階段全綠。

> 🔴 NSX MP 升級完成後，**所有既有 UI session 會失效**，要重新登入才能繼續 Hosts / Edges / Finalize。
> 升級精靈在 iframe 內；導覽視窗（Welcome to NSX）會反覆跳出，勾「Don't show this again」才根治。

### 7.2 vCenter 8.0U3c → 9.1.1（vcsa-deploy upgrade）

migration-based upgrade：部新 9.1.1 appliance（臨時 IP）→ 搬資料 → 切換成原 IP/FQDN，舊 VM 關機。

```bash
# 先 precheck（不改動來源 vCenter）
vcsa-deploy upgrade --accept-eula --acknowledge-ceip --no-ssl-certificate-verification \
  --precheck-only --log-dir <log> vcsa-upgrade-911.json
# 通過後正式升級
vcsa-deploy upgrade --accept-eula --acknowledge-ceip --no-ssl-certificate-verification \
  --log-dir <log> vcsa-upgrade-911.json
```

spec（`vcsa-upgrade-911.json`）重點：`new_vcsa.esxi` 指向**來源 vCenter 目前所在的 ESXi**
（Host 升級 Maintenance 模式會讓 DRS 搬動 vCenter VM，部署前要照現況填）；`temporary_network.ip` 用空閒 IP；
`source_vc.vc_vcsa` 填來源 vCenter FQDN + SSO 管理員 + root。本例約 1h25m，升到 9.1.1.0.25712839。

> 升級完成後 NSX 的 compute manager 會自動重連（REGISTERED / UP / version 9.1.1），不需手動重設。

## 8. Part F — 轉入 VCF 9.1.1（converge）

把 Part E 升好的「獨立 vCenter 9.1.1 + 獨立 NSX 9.1.1」正式 **import / converge 進 VCF 9.1.1**：
由 VCF Installer 9.1.1 部署 SDDC Manager、接管既有 vCenter + NSX、再部齊 VCF 管理元件
（VCF Operations、VSP/VCF Automation、Fleet、License server 等）。本段為 m07 實作（2026-10-23）。

### 8.1 前置

| 項目 | m07 值 |
|---|---|
| VCF Installer 9.1.1 | `vcf-m07-inst01` 10.0.1.167（admin@local）|
| 既有 vCenter（已升 9.1.1） | `vcf-m07-vc01.home.lab` 10.0.1.164 |
| 既有 NSX（已升 9.1.1） | VIP `vcf-m07-nsx01.home.lab` .165 / node `vcf-m07-nsx01a` .166 |
| cluster | `m07-cl01`（domain-c9）, datacenter `m07-dc` |
| 管理元件 IP pool | 10.0.1.176–189（≥12，見 8.4）|

**送出前硬性條件**（實測）：
- `/v1/sddcs` 必須為空（沒有既存 SDDC）。
- 既有 vCenter / NSX 連得到、cluster `STABLE`、thumbprint 正確。
- **既有 vCenter VM 必須接在 DVS 的 portgroup 上**（不是 standard switch）→ 見 8.3。
- **cluster 必須是 vLCM single-image 管理**（不是 baseline/VUM）→ 見 8.5。

### 8.2 兩種送出方式與選擇

Installer 可用 (a) step-by-step UI wizard，或 (b) deployment spec **JSON** 檔。
本手冊走 **(b) JSON spec**：所有密碼放在 spec 檔案本體，不需在 UI 欄位逐一輸入；
spec 範本見 `converge-m07-spec.json`，關鍵欄位：

```jsonc
{
  "sddcId": "vcf-m07", "workflowType": "VCF", "version": "9.1.1.0",
  "vcenterSpec":  { "useExistingDeployment": true, "vcenterHostname": "...", "sslThumbprint": "<SHA-256>" },
  "nsxtSpec":     { "useExistingDeployment": true, "vipFqdn": "...", "nsxtManagers": [ {"hostname":"..."} ], "sslThumbprint": "<SHA-256>" },
  "clusterSpec":  { "datacenterName": "m07-dc", "clusterName": "m07-cl01" },
  "vspClusterSpec": { "size": "small", "ipv4Pool": { "ipRange": {"startIpAddress":"10.0.1.176","endIpAddress":"10.0.1.189"} } },
  "vcfOperationsSpec": { ... }, "sddcManagerSpec": { ... }, "fleetLcmSpec": { ... }, ...
}
```

> `sslThumbprint` 是 **SHA-256**（64 hex），不是 UI 常見的 SHA-1。取法：對 443 憑證 `ComputeHash(SHA256, RawData)`。

### 8.3 API 認證（沿用瀏覽器登入，不另打密碼）

Installer REST 在 `https://<installer>/v1/...`。本手冊沿用使用者在 UI 的登入 session：
瀏覽器 `sessionStorage.sessionDetails.accessToken` 取出 bearer，再從本機 curl 帶上：

```bash
TOK=<從 sessionStorage.sessionDetails.accessToken 取>
curl -sk -H "Authorization: Bearer $TOK" https://10.0.1.167/v1/sddcs            # 必須回 {"elements":[]}
curl -sk -H "Authorization: Bearer $TOK" https://10.0.1.167/v1/sddcs/validations/latest
```

> 在頁面內直接 `fetch()` 會 `Failed to fetch`（CSP/攔截器），所以改由本機 curl 帶 bearer。

### 8.4 validation（四輪，逐一修正）

`POST /v1/sddcs/validations`（body = spec）→ `GET /v1/sddcs/validations/{id}` 輪詢。
10 項檢查：Deployment Spec / Security / DNS / Versions & Bundles / Existing SDDC Manager /
Password Policies / Network / Existing Components / Capacity(×3)。m07 實際踩到並修好的：

| 輪 | 失敗項 | 錯誤碼 | 修正 |
|---|---|---|---|
| v1 | vCenter 不在 DVS | `VSP_UNABLE_TO_DETERMINE_DEPLOYMENT_NETWORK` | 把 vCenter VM 網卡搬到 VDS portgroup（見附錄 9.5）|
| v2 | VSP pool 太小 | `VSP_IPV4_POOL_TOO_SMALL` | small 管理服務需 **≥12** IP → pool 從 7 擴到 14（176–189）|
| v2 | 管理 portgroup 無效 | `VALIDATE_VCF_MANAGEMENT_COMPONENTS_PORTGROUP` | `xRegionNetwork.networkName` 改成實際 VDS PG（`m07-vds01-pg-mgmt`）|
| v3 | cluster 非 vLCM image | `BROWNFIELD_VSPHERE_CHECK` | cluster 轉 single-image（見 8.5）|
| v4 | — | — | **COMPLETED / WARNING（0 error）** ✅ |

殘留 **warning**（可過）：upgrade policy 與 SDDC Manager 預設不同（無害）；
vSAN 儲存帳面不足（4177 < 4364 GB）—— thin provisioning 下實耗遠低於帳面，installer 標 WARNING 放行。

### 8.5 🔑 cluster 轉 vLCM single-image（UI，必做）

VCF 9.x 要求匯入的 cluster 以 **單一映像（vLCM image）** 管理，不能是 baseline/VUM。
9.1.1 的 REST enablement 操作查不到（metamodel 空、各 path 404），故走 **vCenter UI**：

1. Cluster `m07-cl01` → **Updates → Image Setup**，按 **Check cluster's eligibility**；
   偵測到 hosts 現跑的映像（m07 = **ESXi 8.0U3b 24280767**），「All hosts are running this image」。〔圖 `12-image-eligibility.png`〕
2. **PROCEED WITH THIS IMAGE** → UI 萃取該映像建 draft（「Reading and extracting the selected image」）。〔圖 `14-image-review.png`〕
3. **Step 1 Define Image**：ESXi 8.0U3b、無 Vendor/Firmware addon、無額外 component → **SAVE**。〔圖 `15-image-editor.png`〕
4. **Step 2 Check Image Compliance** 跑完 → **FINISH IMAGE SETUP** → 確認框 **YES, FINISH IMAGE SETUP**
   （不可逆：取代所有 baseline，之後無法回 baseline）。〔圖 `18-finish-clicked.png`〕
5. 驗證：`GET /api/esx/settings/clusters/<cluster>/enablement/software` → `{"enabled":true}`。

> 選「用偵測到的映像（host 現行版）」最省事 —— hosts 本來就相容，免 remediation。

### 8.6 送出部署

validation 過（WARNING 無 error）後：

```bash
curl -sk -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json"      --data-binary @converge-m07-spec.json  https://10.0.1.167/v1/sddcs
# 回 { "id": "...", "status": "IN_PROGRESS", ... }
```

### 8.7 監看（5 milestone / 134 subtask）

`GET /v1/sddcs/{id}`，subtask 成功狀態字串 = **`POSTVALIDATION_COMPLETED_WITH_SUCCESS`**（不是 `SUCCESSFUL`）。
Installer UI 的 **VIEW PROGRESS** 也看得到：〔圖 `21-deploy-progress.png`〕

| # | Milestone | subtask |
|---|---|---|
| 1 | Deploy SDDC Manager | 17 |
| 2 | **Convert the existing vCenter with existing NSX to a new VCF instance** | 44 |
| 3 | Deploy and configure VCF Management Platform（VSP/VCFA）| 40 |
| 4 | Deploy and configure the operations appliance（VCF Ops + Cloud Proxy）| 15 |
| 5 | Deploy and configure VCF Management Services | 18 |

里程碑 2 就是 import 核心。M3/M4（VSP、VCF Ops via Fleet Lifecycle）最慢。m07 全程約數小時。

### 8.8 結果

`status = COMPLETED_WITH_SUCCESS`，**134/134，0 failed**。〔圖 `22-deploy-complete.png`〕

| 新元件 | IP | 驗證 |
|---|---|---|
| SDDC Manager | 10.0.1.168 | https 301→UI ✅ |
| VCF Operations | 10.0.1.169 | https 200 ✅ |
| Fleet / VSP | 10.0.1.171 / .173 | API 端點 |

既有 vCenter(.164) + NSX(.165/.166) 已成為 VCF 9.1.1 management domain 的元件。

### 8.9 post-converge 注意

- **NSX 從此歸 VCF 管**：密碼輪替、憑證、備份、升級都走 SDDC Manager，**不要再手動改 NSX 密碼/憑證**。
- converge 後 VCF 會寫入自己的管理 metadata（watermark）—— 蓋掉 Part D 手動寫的那筆，兩者語意一致。
- **單節點 NSX** 為 lab 做法；正式環境期望 3 節點 NSX cluster。
- m07 完成後可整套關機 parked（converge 成果保留在 vSAN），日後可開回。

## 9. 附錄

### 9.1 VCF 5.2.x BOM 對照（Broadcom KB 314608）

| VCF | 發布 | vCenter | ESXi | NSX |
|---|---|---|---|---|
| 5.2 | 2024-07 | 8.0U3a | 8.0U3 | 4.2.0.0（24105817） |
| 5.2.1 / .1 / .2 | 2024-07~2025-04 | 8.0U3c | 8.0U3b | **4.2.1.0（24304122）** |
| 5.2.2 | 2025-09 | 8.0U3g | 8.0U3g | 4.2.3（24866349） |
| 5.2.3 | 2026-02 | 8.0U3i | 8.0U3i | 4.2.3.3（25171318） |
| 5.2.4 | 2026-05 | 8.0U3j | 8.0U3j | 4.2.4（25410638） |

🔑 **NSX 4.2.2.x 不在任何 VCF BOM 內**（5.2.1 用 4.2.1.0，直接跳到 5.2.2 的 4.2.3）。
現場若見 NSX 4.2.2.1，代表另外套了 async patch 或是獨立部署。本手冊用的 4.2.1.0 即 VCF 5.2.1 BOM。

### 9.2 UI 自動化坑（Clarity / NSX / Installer）

- NSX 升級精靈在 **iframe**（`/upgrade-coordinator/`）；控制項要在該 frame 內找。
- Clarity 的 radio / checkbox 被 `<label for=...>` 蓋住 → 點 **label**，不是點 input。
- 按鈕文字常有前後空白（" NEXT "），`exact` 比對會失敗 → 用 `automation-id` 屬性最穩。
- 確認對話框的主按鈕多半 disabled，要先勾「Confirm…」或「I understand…」才啟用。
- Welcome to NSX 導覽會反覆蓋住畫面 → 勾「Don't show this again」+ SKIP。
- NSX MP 升級後既有 session 失效，要重新登入。

### 9.3 `HTTP 000` 判讀

curl `-w '%{http_code}'` 回 000 = **沒收到任何 HTTP 回應**（不是伺服器狀態碼）。
常見於 NSX 升級期間 manager 重啟（連線被拒）、位址打錯、443 不通、少了 `-k`。
拿掉 `-s` 看 curl 的訊息即可分辨。NSX 升級過程中短暫 000 是正常的；持續 20 分以上才需從 vCenter console 查。

### 9.4 其他

- FTT1 vs FTT0 的差異見第 2.3 節——nested 慢碟環境 NSX MP 升級能否過，這一項是關鍵。
- offline depot 設定只接受裸 IP，FQDN 會回 `VMWARE_DEPOT_OFFLINE_INVALID_URL`（訊息誤導）。
- converge 前置：VDS 版本要 8.0.3 才收 8.0U3 主機；installer 的 `/v1/sddcs` 必須為空；
  vCenter 不可有 `com.vmware.sddcManager` / `com.vmware.vcf.client` extension。

### 9.5 vCenter VM 必須在 DVS（converge 前置網路修正）

converge 的 `VSP_UNABLE_TO_DETERMINE_DEPLOYMENT_NETWORK` 來自「既有 vCenter VM 的網卡接在 standard switch」。
VCF 要從 vCenter VM 的 portgroup 推斷 deployment network，故 **vCenter（與 NSX）VM 必須接在 VDS 的 dvportgroup**。

修正：透過 **vCenter** 把該 VM 網卡改到 VDS portgroup（`Set-NetworkAdapter -Portgroup <vds-pg>`）。
若該 dvportgroup 是 static（earlyBinding），**只能由 vCenter 指派 port**，從 host 直接改會回
`Invalid configuration for device 0`。

m07 另有一個 host 層坑（reboot 後遇到）：vmk0+vmnic0 曾被搬到 VDS，使 standard switch 失去 uplink，
VM 被孤立（`Team Uplink: void`）。救法：`esxcfg-vswitch -Q <vmnic> -V <dvport> <dvs>` 退回 uplink 給 vSwitch0
恢復連線，再由 vCenter 把 VM 搬到 VDS PG。若 host vmk0 也要在 VDS，`Add-VDSwitchPhysicalNetworkAdapter`
一次原子地搬 pnic+vmk 以保留 rollback 保護。
