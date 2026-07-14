# v8tov9 — Manual VCF 5.2.1 → 9.1 Upgrade on *Unsupported* Hardware (Lab)

手動把一套 nested **VCF 5.2.1**（vSphere 8.0.3 + NSX 4.2.1）逐元件升到 **9.1**，跑在 **Broadcom 官方已列為 discontinued 的 Broadwell CPU**（Xeon E5-2682 v4）上。脫離 SDDC Manager LCM，純手動 CLI / API / UI，全程實測記錄。

## ✅ 結果：升級全部完成

| 元件 | 前 → 後 | 狀態 |
|------|---------|------|
| **NSX** | 4.2.1 → **9.1.0.0100.25470810** | MP / HOST / EDGE / **FINALIZE** 全 SUCCESS |
| **vCenter** | 8.0.3.00300 → **9.1.0.0100** (b25417926) | migration 完成，切回原 IP |
| **ESXi ×4** | 8.0.3 → **9.1.0** (build-25433460) | 全 CONNECTED、MM Disabled |
| **vSAN** | — | OVERALL **green**（物件全 healthy、resync 0）|

> ⚠️ **Lab / 研究用途，Broadcom 不支援。** 這裡用的旁路（改 guestId、靜音 vSAN HCL 健康檢查、`--skip-product-interop-check` 等）都會讓環境脫離受支援狀態。正式環境請走 SDDC Manager LCM 並用受支援硬體。

> 🔑 所有密碼已以 `<PLACEHOLDER>` 取代。IP 為 RFC1918 私網，保留以利閱讀。

---

## 🏆 兩個最有價值的實測發現

### 1. nested vCLS 開不了機 → DRS 失效 → NSX Host 升級卡死

**症狀**：NSX Host 升級（VLCM 叢集 → vLCM remediation）失敗，`Health Check for cluster failed`，4 台 host 全部 not processed。追進 vLCM precheck 發現 `Is host ready to enter maintenance` = ERROR：

```
DRS is non-functional due to absence of vCLS quorum. Active vCLS VMs:0; Required:1.
```

vCLS VM 全部 POWERED_OFF、反覆重建（手動開機被拒 403，service-managed）。vCLS 是 **CRX 微型 VM**（`/var/run/crx/infra/…`，datastore 為空），vmkernel.log 顯示其 vmm world 每 ~0.3 秒重啟一次。關鍵證據在 CRX 的 `vmware.log`：

```
Power on failure messages: Feature 'cpuid.mwait' was 0, but must be 0x1.
Module 'FeatureCompatLate' power on failed.
```

**根因**：vSphere 8 的 embedded vCLS (CRX) 需要 **MONITOR/MWAIT** 指令，而該指令**預設只對兩種 guest OS type 開啟：VMware ESXi 與 macOS**。本環境的 nested ESXi VM 被建成 **`Other (64-bit)` / OTHER_64** → 不開放 MWAIT → CRX vCLS 無法開機。

**解法**（在**實體/外層** vCenter 上，對每台 nested ESXi VM）：

1. 升級虛擬硬體版本 **vmx-14 → vmx-20**
   （原 HW14 = ESXi 6.7 等級，會讓 `vmkernel8Guest` 被判 `UnsupportedGuest / No host is compatible`，即使實體 host 是 8.0.3）
2. guest OS type 改為 **VMware ESXi 8.x**（`guestId = vmkernel8Guest`）
3. **完整關機再開機**（滾動逐台；vSAN FTT=1 可容忍單台離線）

→ 見 [`scripts/upgrade-hw-guest.ps1`](scripts/upgrade-hw-guest.ps1)、[`scripts/xindian-setguestos.ps1`](scripts/xindian-setguestos.ps1)

完成 2 台後 vCLS 就開機、DRS 恢復、vLCM precheck 全過。**此修復存於 VM 的 vmx，是持久設定** — 期間遇過一次實體停電，環境恢復後 vCLS 自動開機、vSAN 資料完整。

> 參考：[William Lam — Incorrect guestOS type for Nested ESXi causes vCLS issues](https://williamlam.com/2024/07/incorrect-guestos-type-for-nested-esxi-causes-vcls-issues-with-vmware-cloud-foundation-vcf-holodeck-toolkit.html)

### 2. ★ ESXi 9.1 在 Broadwell 上「不需要」allowLegacyCPU

Xeon E5-2682 v4 屬 [KB 318697](https://knowledge.broadcom.com/external/article/318697/) 的 **discontinued**。原本預期要在 `boot.cfg` 的 `kernelopt` 加 `allowLegacyCPU=TRUE`。

**實測結果**：第一台（esx03）因 sed 跳脫問題，該參數其實**根本沒寫進去**（`boot.cfg` 仍是 `kernelopt=autoPartition=FALSE`），但 host **照樣成功開機為 ESXi 9.1.0 build-25433460**。後面 3 台直接略過該步驟，4 台全部順利升級。

**結論**：KB 318697 的 CPU 封鎖是在 **ISO 安裝程式**層的檢查；走 `esxcli software profile update ... --no-hardware-warning` 的**升級路徑不會在開機時硬擋 Broadwell**。（`allowLegacyCPU` 仍可留作保險，但本案實證非必要。）

---

## 官方升級順序（VCF 9.1）

依 [KB 440630](https://knowledge.broadcom.com/external/article/440630/upgrade-sequence-and-related-issues-for.html) 與官方 techdocs：

> **SDDC Manager → NSX Manager (Part 1) → vCenter → ESXi → NSX Edge + Finalize (Part 2)**

- 官方明確點出 **NSX 9.1 升級「拆成兩部分」**：Part 1 = NSX Manager（vCenter 之前）；Part 2 = Edge + **Finalize**，在 **vCenter、ESXi 之後**才做。
- **NSX Finalize 硬性要求 vCenter 已是 9.1**（實測 gate）：
  ```
  error 36013: Found compute manager at version 8.0.3.
  Please upgrade the compute manager to version 9.1 to complete the NSX upgrade.
  ```
- 本案（傳統 NSX Upgrade Coordinator，脫離 LCM）實際節奏：**NSX Manager + Host → vCenter → ESXi → NSX Finalize**。

---

## ① NSX 4.2.1 → 9.1

用 URL 匯入 bundle（5.57GB，比瀏覽器上傳快）；然後 UC：precheck → Manager → Host → Edge → Finalize。

**踩到的坑**

- **UC UI 整片空白**：Chrome 語系 zh-TW 時 `assets/i18n/zh-TW.json` 回 HTTP 500 → **把 Chrome 語言改英文**即可渲染。
- **UC UI 常凍結**（Angular iframe 把 CDP 卡死）→ 改用 **session + XSRF API** 驅動：
  ```powershell
  # 先 POST /api/session/create (form j_username/j_password) 拿 x-xsrf-token
  POST /api/v1/upgrade/plan?action=continue&component_type=HOST
  POST /api/v1/upgrade/plan?action=upgrade&component_type=EDGE          # 無 edge 時標記 SUCCESS
  POST /api/v1/upgrade/plan?action=upgrade&component_type=FINALIZE_UPGRADE
  GET  /api/v1/upgrade/status-summary?component_type=HOST                # 監控
  ```
  → [`scripts/nsx-continue.ps1`](scripts/nsx-continue.ps1)、[`scripts/nsx-monitor.ps1`](scripts/nsx-monitor.ps1)
- **MP 升級 98% 失敗**（`mp_notify_completion`, error 26 compute managers unhealthy）：根因是 compute manager (vCenter) `connection=DOWN` → `PUT /api/v1/fabric/compute-managers/{id}` 帶帳密 + thumbprint 重新註冊 → retry 成功。
- **Host 升級（VLCM 叢集）被 vLCM precheck 擋兩關**：
  1. `Host in vSAN maintenance mode possible` = ERROR → 因 nested 的 `controllerdiskmode`（控制器未認證）呈黃，vLCM 以 `overall_health_not_green` 擋 MM。**解**：靜音 vSAN HCL 健康測試 → [`scripts/vsan-silence.ps1`](scripts/vsan-silence.ps1)（注意用**短 id**：`controllerdiskmode` / `controlleronhcl` / `hcldbuptodate`…，長的 `com.vmware.vsan.health.test.*` 會被拒）
  2. `Is host ready to enter maintenance` = ERROR → vCLS/DRS（見上面「發現 1」）

---

## ② vCenter 8.0.3 → 9.1（CLI migration）

**VAMI「更新」分頁不行**（8→9 是大版本升級非 patch；且 VAMI 自訂 repo 只吃 HTTPS）。正解是 **VCSA 9.1 ISO 的 CLI migration installer**：

```
F:\vcsa-cli-installer\win32\vcsa-deploy.exe upgrade \
  --accept-eula --acknowledge-ceip --no-ssl-certificate-verification \
  --upgrade-framework legacy --skip-product-interop-check \
  --verbose  vcsa91-upgrade.json          # 加 --precheck-only 可只做檢查
```

- **RDU 卡死** → 改 `--upgrade-framework legacy`
- **`NSX 4.2.1 not supported`** → **先升 NSX**（升到 9.1 後此擋自動消失）
- 新 9.1 appliance 是 **Photon guest VM，不受 Broadwell 封鎖**（CPU 封鎖只在 ESXi hypervisor 層）
- migration 用**暫時 IP** 部署新機，完成後自動切回原 IP、關掉舊機（約 52 分鐘）
- **坑**：中途 installer 可能拋一次 `SecureConnectorException: a bytes-like object is required, not 'NoneType'`（訊息暗示 clock skew，但實測時鐘正常）→ **一次性 glitch，會自行重試恢復，非致命**。權威進度看新機自己：
  ```
  GET https://<新機IP>:5480/rest/vcenter/deployment      # root basic auth
  ```

---

## ③ ESXi 8.0.3 → 9.1（逐台）

每台：**進 MM → profile update → reboot → 退 MM → 等 vSAN resync 歸零**

```bash
# jump host 掛 depot： python -m http.server 8000   (E:\esxi91-depot 內含 index.xml)
esxcli software profile update \
  -d http://<jump>:8000/esxi91-depot/index.xml \
  -p ESXi-9.1.0.0100-25433460-standard \
  --no-hardware-warning
reboot
```

→ 全自動腳本：[`scripts/esxi-upgrade-host.ps1`](scripts/esxi-upgrade-host.ps1)（進 MM 用 vSAN `ensureObjectAccessibility`，DRS 自動搬走管理 VM）

- **不需要** `allowLegacyCPU`（見上面「發現 2」）
- **升級順序**：先升沒有 running 管理 VM 的 host；**跑 vCenter 的 host 最後升**
- 下一台之前確認：`esxcli vsan debug resync summary get` → `Total Number Of Resyncing Objects: 0`

---

## 常見卡點速查

| 症狀 | 原因 / 解 |
|------|-----------|
| nested vCLS 開不了機 / DRS 失效 / `cpuid.mwait was 0` | nested ESXi VM guest type = Other(64-bit) 不開 MWAIT → 改 `guestId=vmkernel8Guest` + 升 vHW-20（外層 vCenter，需關機）|
| NSX Host 升級 `Health Check for cluster failed` | ① vSAN `controllerdiskmode` 黃 → 靜音 HCL 測試；② vCLS/DRS quorum → 修 vCLS |
| NSX Finalize `error 36013 compute manager 8.0.3` | 先把 vCenter 升到 9.1 |
| NSX UC UI 整片空白 | Chrome 語系 zh-TW 的 i18n JSON 回 500 → 改英文 |
| NSX UC UI 凍結（CDP timeout） | 改用 session + XSRF API 驅動 |
| ESXi 9 ISO 裝不上 / Unsupported CPU | Broadwell discontinued → 改走 `esxcli profile update --no-hardware-warning`；**此路徑不需 allowLegacyCPU** |
| vcsa-deploy RDU `DRS_cluster resource validation` 卡死 | `--upgrade-framework legacy` |
| vcsa-deploy `NSX 4.2.1 not supported` | 先升 NSX |
| vcsa-deploy `SecureConnectorException` (NoneType) | 一次性 glitch，會自行恢復；看新機 `:5480/rest/vcenter/deployment` |
| VAMI 更新頁看不到 9.1 / repo URL 紅字 | 8→9 非 patch，改 ISO CLI migration；VAMI 自訂 repo 只吃 HTTPS |
| `esxcli ... -d http://...` ValueError | offline bundle 只吃本機路徑；解壓成 online depot 用 URL |

---

## 檔案

| 檔案 | 用途 |
|------|------|
| [`doc/VCF-5.2.1-to-9.1-Manual-Upgrade.docx`](doc/) | **完整交付文件**（11 章、5 表、4 圖，含截圖）|
| [`plan.md`](plan.md) / [`context.md`](context.md) / [`tasks.md`](tasks.md) | 目標範圍 / 決策與環境 / checkbox 進度 |
| [`scripts/esxi-upgrade-host.ps1`](scripts/esxi-upgrade-host.ps1) | ESXi 逐台升級（MM → profile update → reboot → 退 MM）|
| [`scripts/upgrade-hw-guest.ps1`](scripts/upgrade-hw-guest.ps1) | ★ vCLS 修復：升 vHW + 改 `vmkernel8Guest` + 電源循環 |
| [`scripts/vsan-silence.ps1`](scripts/vsan-silence.ps1) | 靜音 vSAN HCL 健康測試（解 vLCM MM 阻擋）|
| [`scripts/vclcm-recheck.ps1`](scripts/vclcm-recheck.ps1) | 跑 vLCM remediation precheck 並印出所有 ERROR |
| [`scripts/nsx-continue.ps1`](scripts/nsx-continue.ps1) | NSX 升級 API 驅動（session + XSRF）|
| [`scripts/nsx-monitor.ps1`](scripts/nsx-monitor.ps1) / [`nsx-upg-status.ps1`](scripts/nsx-upg-status.ps1) | NSX 升級進度監控 |
| [`scripts/vcls-retreat.ps1`](scripts/vcls-retreat.ps1) / [`vcls-monitor.ps1`](scripts/vcls-monitor.ps1) | vCLS retreat mode 切換 / 監控 |
| [`scripts/mm-exit.ps1`](scripts/mm-exit.ps1) / [`enable-ssh.ps1`](scripts/enable-ssh.ps1) | 退出 maintenance mode / 啟用 host SSH |
| [`vcsa91-upgrade.json`](vcsa91-upgrade.json) | vCenter migration 範本（密碼已 placeholder）|
| [`https_repo.py`](https_repo.py) | 自簽 HTTPS 檔案伺服器（VAMI 只吃 HTTPS 時用）|
| [`patch-boot.sh`](patch-boot.sh) | 注入 `allowLegacyCPU`（**實證非必要**，保留備用）|
