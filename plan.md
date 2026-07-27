# Plan — VCF 5.2.1 → 9.1 手動逐元件升級 (Nested Lab)

## 目標
把既有的 nested **VCF 5.2.1**（vSphere 8.0.3 + NSX 4.2.1）以**傳統手動方式**（脫離 SDDC Manager LCM，用 NSX Upgrade Coordinator + vcsa-deploy + esxcli）逐元件升級到 **9.1**，全程實測、踩坑、解坑，並產出交付文件（含截圖）。

## 範圍 (In scope)
- NSX 4.2.1 → 9.1（Manager / Host VIB / Edge / Finalize）
- vCenter 8.0.3 → 9.1（CLI migration，vcsa-deploy）
- ESXi ×4 8.0.3 → 9.1（在**非支援的 Broadwell CPU** 上，用 allowLegacyCPU 繞過）
- 交付文件：`doc\VCF-5.2.1-to-9.1-Manual-Upgrade.docx`（含各階段截圖）
- 上傳到 github.com/kostenyang/v8tov9（密碼以 placeholder 取代）

## 不做什麼 (Out of scope)
- **不走 SDDC Manager / VCF LCM 自動化**（本案刻意手動，SDDC Manager 5.2.1 留原版）
- **不打 nested host snapshot**（使用者明確要求，太慢）
- 不升級外層 Xindian vCenter (.32) / 實體 host (.16)（只當升級目標平台）
- 不追求 Broadcom 受支援狀態（本 lab 的旁路都會脫離支援）
- 不部署 VCF 9.1 新的 Fleet/Management Services（那是 LCM 路線）

## 完成標準 (Definition of Done)
1. NSX：Manager + Host + Edge + **Finalize** 全部 SUCCESS，NSX 版本標記為 9.1。
2. vCenter：新 9.1 appliance 切回原 IP .142，vpxd 健康、inventory 完整。
3. ESXi：4 台 nested host 皆 `VMware ESXi 9.1.0` 開機、CONNECTED、vSAN green。
4. 交付文件更新到最終狀態並推上 git。
5. 環境整體健康（DRS/vCLS 正常、vSAN green、無 inaccessible object）。

## 官方順序 (KB 440630)
SDDC Manager → NSX Manager (Part 1) → **vCenter** → **ESXi** → NSX Edge + Finalize (Part 2)
> NSX 拆兩部分；Finalize 硬性要求 vCenter 先到 9.1。本案 NSX Host 提前於 vCenter（傳統 NSX UC 允許，已成功）。
