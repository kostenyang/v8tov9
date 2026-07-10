# v8tov9 — Manual VCF 5.2.1 → 9.1 Upgrade on *Unsupported* Hardware (Lab)

手動把一套 nested **VCF 5.2.1**（vSphere 8.0.3 + NSX 4.2.1）逐元件升到 **9.1**，跑在 **Broadcom 官方不支援的 Broadwell CPU** 上。脫離 SDDC Manager LCM、純手動 + CLI/API，全程實測記錄。

> ⚠️ **Lab / 研究用途，Broadcom 不支援。** 這裡用的旁路（`allowLegacyCPU`、`--skip-product-interop-check`、移除 extension 等）都會讓環境脫離受支援狀態。正式環境請走 SDDC Manager LCM 並用受支援硬體。

> 🔑 所有密碼已以 `<PLACEHOLDER>` 取代。IP 為 RFC1918 私網，保留以利閱讀。

---

## 環境

| 元件 | 版本 (升級前) | IP |
|------|--------------|-----|
| 實體 ESXi (外層) | 8.0.3 · **Xeon E5-2682 v4 (Broadwell-EP)** | 192.168.110.16 |
| 外層 vCenter | 8.0.3 | 192.168.110.32 |
| Nested vCenter (VCF mgmt) | 8.0.3.00300 | 192.168.110.142 |
| Nested NSX Manager | 4.2.1.0.0 | 192.168.110.143 |
| Nested ESXi ×4 | 8.0.3 | 192.168.110.145–148 |
| SDDC Manager | 5.2.1 | 192.168.110.141 |
| Jump host (repo/installer) | Windows + PowerCLI | 192.168.110.200 |

9.1 媒體 (放 jump host)：`VMware-VCSA-all-9.1.0.0100.25417926.iso`、`VMware-ESXi-9.1.0.0100.25433460-depot.zip`、`VMware-NSX-upgrade-bundle-9.1.0.0100.0.25470810.mub`。

---

## 官方升級順序（重要）

依 [Broadcom KB 390634 — Update Sequence for VCF 9.0](https://knowledge.broadcom.com/external/article/390634/update-sequence-for-vcf-90-and-compatibl.html)（9.1 見 [KB 440630](https://knowledge.broadcom.com/external/article/440630/upgrade-sequence-and-related-issues-for.html)）：

> **SDDC Manager → NSX → vCenter → ESXi**

- **NSX 先於 vCenter**。官方：*若 vCenter 為 8.0 U3+ 且已註冊 NSX 4.2.1+，可不先升 vCenter、直接先升 NSX*。
- 手動測試略過 SDDC Manager LCM，實際順序：**NSX → vCenter → ESXi**。

---

## 🧱 最大障礙：CPU 被 VCF 9 封鎖 —— 已用實測繞過

Xeon E5-2682 v4 = Broadwell-EP，屬 [KB 318697](https://knowledge.broadcom.com/external/article/318697/) 的 **discontinued**（安裝程式 block）。但 **ESXi 9.1 可在 Broadwell 上開機**，實測配方：

1. depot.zip 解壓成 online depot（含 `index.xml`），用 HTTP/HTTPS 掛出（`esxcli` 的 offline `-d` 只吃本機路徑，不吃 URL）。
2. staging：
   ```
   esxcli software profile update -d <depot>/index.xml \
     -p ESXi-9.1.0.0100-25433460-standard --no-hardware-warning
   ```
3. 在**新 bootbank** 的 `boot.cfg` 的 `kernelopt=` 尾端加 `allowLegacyCPU=TRUE`（兩個 bootbank 都補；見 [`patch-boot.sh`](patch-boot.sh)），再 `reboot`。

結果：`VMware ESXi 9.1.0 build-25433460` 在 Broadwell 上開起來。
**重點**：`allowLegacyCPU` 是**開機參數**，不是 runtime kernel setting（8.0.3 上 `esxcli system settings kernel set -s allowLegacyCPU` 回 `Invalid Key Name`）。KB 的 "block" 指 ISO 安裝程式；`profile update` + `kernelopt` 這條可繞。

---

## ① NSX 4.2.1 → 9.1（先做）

用 URL 匯入 bundle（5.57GB，比瀏覽器上傳快）：
```powershell
# jump host 上把 .mub 用 HTTP 掛出：  python -m http.server 8000 --directory E:\
# NSX API (admin/<NSX_PASSWORD>)：
POST https://<nsx>/api/v1/upgrade/bundles   body: {"url":"http://<jump>:8000/VMware-NSX-upgrade-bundle-...mub"}
GET  https://<nsx>/api/v1/upgrade/bundles/<bundle_id>/status   # 輪詢 SUCCESS
# 然後 Upgrade Coordinator：precheck → 升級 Edge → Host → Management
```
> Host 元件升級時 ESXi 仍是 8.0.3——官方順序允許此過渡；nested + Broadwell 到 host 步驟需留意。

---

## ② vCenter 8.0.3 → 9.1（CLI migration）

**VAMI「更新」分頁不行**：8→9 是大版本升級，非 patch。實測 VAMI「檢查 CD ROM + URL」對 9.1 repo 回「找不到適用的更新」（因 updaterepo manifest `allowedSourceVersions=[9.0.0.0,]`，只收 ≥9.0）。且 **VAMI 自訂 repo 只吃 HTTPS/FTPS，不吃 HTTP**（要自簽 HTTPS server，見 [`https_repo.py`](https_repo.py)）。

正解 = **VCSA 9.1 ISO 的 CLI migration installer**（[`vcsa91-upgrade.json`](vcsa91-upgrade.json)）：
```
F:\vcsa-cli-installer\win32\vcsa-deploy.exe upgrade \
  --accept-eula --acknowledge-ceip --no-ssl-certificate-verification \
  --upgrade-framework legacy --skip-product-interop-check \
  --precheck-only --verbose  vcsa91-upgrade.json
```
踩到的坑（依序）：
1. **RDU 卡死**：預設 `reduced_downtime_upgrade` 在 nested VCF DRS cluster 上，`DRS_cluster resource validation` 卡 ~16 分後失敗 → 改 **`--upgrade-framework legacy`**（傳統 migration，有停機）。
2. **NSX 相容性硬擋**：來源 vCenter 的 upgrade checker 回 `NSX '4.2.1.0' is not supported`（`--skip-product-interop-check` 也擋不掉，因為是來源端 checker.sh 判的）。→ 正確解是**先升 NSX**（本 repo 順序），NSX 升 9.1 後 extension 變 9.1 相容。
3. 新 9.1 appliance 是 **Linux(Photon) guest VM，不受 Broadwell CPU 封鎖**（CPU 封鎖只在 ESXi hypervisor 層）。
4. migration 需**暫時 IP**（部署新機用，遷移後切回原 IP）。

---

## ③ ESXi 8.0.3 → 9.1

見上面「CPU 繞過」配方，每台 host 逐一：staging (`--no-hardware-warning`) → `boot.cfg` 加 `allowLegacyCPU=TRUE` → reboot。升級前記得對 nested host 打 snapshot。

---

## 常見卡點速查

| 症狀 | 原因 / 解 |
|------|-----------|
| ESXi 9 裝不上 / 開機卡 Unsupported CPU | Broadwell discontinued → `--no-hardware-warning` + `boot.cfg` `allowLegacyCPU=TRUE` |
| `allowLegacyCPU` `Invalid Key Name` | 它是 boot option 不是 kernel setting，改 `boot.cfg` `kernelopt` |
| VAMI 更新頁看不到 9.1 | 8→9 非 patch；改用 VCSA ISO CLI migration |
| VAMI 自訂 repo URL 紅字 | 只吃 HTTPS/FTPS，架自簽 HTTPS server |
| `esxcli ... -d http://...` ValueError | offline bundle 只吃本機路徑；解壓成 online depot 用 URL |
| vcsa-deploy RDU `DRS_cluster resource validation` 卡死 | `--upgrade-framework legacy` |
| vcsa-deploy `NSX 4.2.1 not supported` | 先升 NSX（官方順序）；或移除 NSX extension 暫時旁路 |

---

## 檔案

| 檔案 | 用途 |
|------|------|
| [`vcsa91-upgrade.json`](vcsa91-upgrade.json) | vCenter 8.0.3→9.1 CLI migration 範本（密碼已 placeholder）|
| [`patch-boot.sh`](patch-boot.sh) | 在 ESXi 兩個 bootbank 的 `boot.cfg` 注入 `allowLegacyCPU=TRUE` |
| [`https_repo.py`](https_repo.py) | 自簽 HTTPS 檔案伺服器（VAMI 只吃 HTTPS 用）|
