# 獨立（standalone）NSX → VCF 9.1.1 — 手動部署、Upgrade Coordinator 升級、與 `vcfEnvironmentCheck` 關卡

把一套**從未進過 VCF**的 NSX（手動部署、無 SDDC Manager）用 Upgrade Coordinator（UC）升到 9.1.1，
會撞到 `vcfEnvironmentCheck`（錯誤碼 31944）這道硬關卡。本資料夾記錄：怎麼手動把 lab 建起來、
UC 升級流程、這道關卡在檢查什麼，以及 lab 裡怎麼驗證它。

> ⚠️ **Lab only。** 偽造 VCF watermark 官方不支援，正式環境獨立 NSX 要升 9.x 的官方路徑是
> **先 import / converge 進 VCF**（KB440630），再用 VCF lifecycle 升級。

## 0. 環境（lab 值）

| 元件 | 版本 | 位址 |
|---|---|---|
| nested ESXi ×3 | 8.0U3b | 10.0.1.161-163，cluster m07-cl01，vSAN OSA |
| vCenter | 8.0U3c | vcf-m07-vc01 10.0.1.164 |
| NSX（單節點） | 4.2.1.0.0.24304122 | node 10.0.1.166 / VIP 10.0.1.165（medium） |
| 升級目標 | 9.1.1.0.0.25691509 | depot `http://<depot>:8888/PROD/COMP/NSX_T_MANAGER/` |

5.2.1 BOM 的安裝媒體（vCSA 8.0U3c ISO、NSX 4.2.1 OVA、ESXi 8.0U3b）可從 Cloud Builder 5.2.1
appliance 內 `/mnt/iso/sddc-foundation-bundle-.../{vcenter_ova,nsxt_ova,esx_iso}` 取得，CB 上也有 `ovftool`。

## 1. 手動把 lab 建起來（不經 Cloud Builder bring-up）

| 腳本 | 做什麼 |
|---|---|
| `scripts/Deploy-NestedESXi.ps1 -Set m07` | 3 台 nested ESXi 8.0U3b（`createvmfs=false`，碟留給 vSAN）；需 `$env:VIPASS`/`$env:ESXPASS` |
| （手動）esx01 esxcli bootstrap 單節點 vSAN | CLI `vcsa-deploy` 前要先有 datastore；否則 installer 選碟頁 0 顆碟 |
| `vcsa-deploy install`（在 CB 上，掛 vCSA ISO） | 部 vCenter 8.0U3c |
| `scripts/Build-M07Cluster.ps1` | 建 DC/cluster、加主機、vmk0 開 vMotion+vSAN、disk group、VDS、DRS、靜音 vSAN HCL；需 `$env:VCPASS`/`$env:ESXPASS`。🔴 PowerCLI 13.5 開 vSAN 用 `Set-Cluster -VsanEnabled`（`Set-VsanClusterConfiguration` 已無此參數） |
| `ovftool`（在 CB 上）部 NSX 4.2.1 medium | 🔴 nested 用 medium（small 16 GB 會餓死，telemetry/CEIP 起不來） |
| `scripts/Configure-M07Nsx.ps1` | compute manager → uplink profile → TEP pool → TNP → host prep；需 `$env:NSXPASS`/`$env:VCPASS` |

## 2. UC 升級流程（到 pre-check）

`scripts/Run-NsxPrecheck.ps1`（需 `$env:NSX_PASS`）走跟 UI 一樣的順序，**到 pre-check 就停**：

```
上傳 .mub（URL）→ EULA → upgrade UC（9.1.1）→ execute_pre_upgrade_checks → 存 JSON
```

- 上傳 .mub 會把 UC 升到 9.1.1（manager 重啟約 5 分鐘，期間 API 回 500）。
- nested 慢碟：`Extracting Bundle Signature` 可能 iowait 70%+ 卡很久，不是當機。
- 上傳中服務重啟後重送會回 30902「Another upgrade bundle upload is in progress」→ 用原 bundle id 續追（`-ResumeBundleId`）。

## 3. `vcfEnvironmentCheck`（31944）在檢查什麼

- 實作：UC 的 `libnsx-upgrade-plugins.jar` → `VcfEnvironmentInspectionTask`，只呼叫
  `getNsxManagerDeploymentInfo()` 讀 NSX DB 的 `NsxManagerDeploymentInfo`；讀不到 → `FAILURE NOT_VCF_ENVIRONMENT`（31944，`needs_ack=False`，不能 acknowledge）。
- 這筆資料的 API = **`/api/v1/watermark`**，由 Cloud Builder / SDDC Manager 部署時寫入；只看 NSX 自己的 DB（SDDC Manager 關機不影響）。

### 對照（同一 NSX build 4.2.1.0.0.24304122）

| | Cloud Builder 部 | 手動部 | 手動部 + 補 watermark |
|---|---|---|---|
| `GET /api/v1/watermark` | 200 | 404（error 600） | 200 |
| 9.1.1 pre-check | 0 FAILURE / 4 WARNING | **FAILURE 31944** + 4 WARNING | **0 FAILURE** / 4 WARNING |

四個共同 WARNING（可 acknowledge）：31911 FPROT context profile、36014 NSX-V 遷移、31935 MP API 棄用、31954 Malicious IP DFW rule。

原始紀錄（2026-10-22，UC 9.1.1.0 的 `/api/v1/upgrade/pre-upgrade-checks/failures` 輸出）：

| 檔案 | 內容 |
|---|---|
| [`evidence/m06/06-precheck-failures.json`](evidence/m06/06-precheck-failures.json) | Cloud Builder 部：4 WARNING，無 31944 |
| [`evidence/m07/06-precheck-failures.json`](evidence/m07/06-precheck-failures.json) | 手動部：FAILURE 31944 + 4 WARNING |
| [`evidence/m07/watermark-test.txt`](evidence/m07/watermark-test.txt) | 手動部補 watermark 全程：GET 404 → POST 201 → GET 200 → 重跑預檢 → 失敗清單 |
| [`evidence/m07/07-precheck-failures-after-watermark.json`](evidence/m07/07-precheck-failures-after-watermark.json) | 補 watermark 後：0 FAILURE，剩 4 WARNING |

## 4. lab 繞過（`scripts/watermark-curl.sh`）

```bash
export NSX=<nsx-ip> NSX_PASS=<admin-pw>
bash watermark-curl.sh get        # 404 = 非 VCF，會被擋
bash watermark-curl.sh post       # 寫一筆 VCF watermark（欄位照 CB 格式）
bash watermark-curl.sh precheck   # 重跑預檢
bash watermark-curl.sh failures   # 31944 應消失
bash watermark-curl.sh delete     # 還原
```

互動版 `scripts/watermark-curl-v1.sh`（同樣六個子命令）：直接執行會依序詢問 NSX Manager IP/FQDN、admin 密碼（`post` 另問 `managed_by`、`version`），
`post`/`delete` 送出前要按 y 確認，`get`/`post`/`delete` 會印 HTTP 狀態碼。設了環境變數 `NSX`、`NSX_PASS`（選填 `NSX_USER`、`MANAGED_BY`、`WM_VERSION`）就不問。

## 5. 補 watermark 後的實際升級

`scripts/nsx-host-chain.ps1`：等 MP SUCCESS → `plan?action=continue` 做 HOST → 停在 FINALIZE 前
（FINALIZE 要 vCenter 已升 9.1）。MP/HOST 的 plan settings 設 `pause_after_each_group=true` 當檢查點。
啟動 MP 前若 pre-check 擋「service account/trust disabled」→ compute manager 開 `create_service_account=true`
+ `set_as_oidc_provider=true`，等 trust UP 再重跑 pre-check。

官方升級順序（有 SDDC Manager）：NSX Manager(+Host) → vCenter → ESX → NSX Edge / Finalize。
