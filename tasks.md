# Tasks — VCF 5.2.1 → 9.1 升級

## NSX (Part 1)
- [x] 匯入 NSX 9.1 bundle (.mub) + 接受 EULA
- [x] 升級 Upgrade Coordinator → 9.1
- [x] Pre-checks 通過（3 warnings acknowledge）
- [x] NSX Manager (MP) 升級 → SUCCESS（修 compute manager 重新註冊）
- [x] NSX Host VIB ×4 升級 → SUCCESS（4/4）
  - [x] 解 vLCM health check：靜音 vSAN HCL 測試
  - [x] 解 DRS/vCLS：修 nested VM guestId=vmkernel8 + vHW-20（MWAIT）
- [x] NSX Edge → SUCCESS（skip，無 edge）

## vCenter
- [x] 重掛 VCSA 9.1 ISO (F:)
- [x] precheck 全過（legacy framework, skip-interop）
- [x] **執行 migration 升級 → 完成 (exit 0)**
  - [x] Stage 1 部署新 appliance (.151)
  - [x] rpminstall / precheck / export / firstboot / import 全 SUCCEEDED
  - [x] IP 切換 .151 → .142，舊機關機
  - [x] 驗證新 vCenter **9.1.0.0100 build 25417926** 在 .142、SSO OK、4 host CONNECTED、inventory 完整

## ESXi ×4 (Broadwell CPU 繞過)
- [x] 驗證配方可行（esxi9-cputest 開機成功）
- [x] **發現：profile-update 路徑升 9.1 在 Broadwell 上「不需」allowLegacyCPU（esx03 實證開機成功）**
- [x] esx03 → 9.1（CONNECTED，vSAN green）
- [x] esx02 → 9.1（ESXi 9.1.0 build-25433460，exit MM OK）
- [x] esx04 → 9.1（9.1.0 build-25433460，MM Disabled，resync 0）
- [x] esx01 → 9.1（跑新 vCenter，最後升，成功）
- [x] **4 台全部 9.1.0 build-25433460，CONNECTED，MM Disabled，vSAN green**

## NSX (Part 2) — 需 vCenter 9.1 後
- [x] **NSX Finalize Upgrade → SUCCESS**（vCenter 9.1 後 gate 解除）
- [x] **NSX 版本 = 9.1.0.0100.25470810**（MP/HOST/EDGE/FINALIZE 全 SUCCESS）

## 🎉 升級完成 (2026-07-13)
- NSX 9.1.0.0100.25470810 · vCenter 9.1.0.0100 build 25417926 · ESXi ×4 9.1.0 build-25433460 · vSAN green
- [x] 推 github.com/kostenyang/v8tov9 (42abff0)

## 🔌 Lab 關機 / 開機
- [x] 乾淨關機（vSAN reboot_helper prepare → MM noAction → poweroff，4 台 off）
- [~] **開機中 (2026-07-15)**
  - [x] Xindian .32 開 4 台 nested ESXi VM（ping 通）
  - [ ] 直接連 host /sdk 啟 SSH（vCenter 關著、SSH reboot 後關）
  - [ ] `reboot_helper.py recover`（任一 host）
  - [ ] 4 台 exit MM
  - [ ] 開 vc01-9、vCLS 自動起、DRS 恢復、vSAN green

## 📸 文件補圖（使用者：升級文件圖片有缺）
- [ ] 開機後重新截圖補足升級各階段（NSX / vCenter 9.1 / ESXi 9.1 / vSAN），更新 docx

## ⏭ 下一階段（媒體下載後）
- [ ] 部署 VCF Operations / VCF Installer / License Server

## 收尾
- [ ] 外部 extension (LCM/SDDC/NSX) 於 vCenter 升級後重新註冊
- [ ] 整體 fleet 健康驗證（DRS/vCLS/vSAN/NSX/vCenter）
- [x] 交付文件更新到最終狀態（doc\*.docx，11章/5表/4圖）
- [x] 推上 github.com/kostenyang/v8tov9（密碼 placeholder，commit 42abff0）

## ⏭ 下一階段（等使用者下載媒體後進行）
使用者下載中：**VCF Operations**、**VCF Installer**、**License Server**。
- [ ] 部署 VCF Operations（原 Aria/vROps 家族，9.x 的 fleet/維運）
- [ ] 部署 VCF Installer / VCF Management Services（9.1 取代 9.0 的 Fleet Management Appliance）
- [ ] 部署 License Server（VCF 9.1 授權集中管理）
- 目前基礎已就緒：NSX 9.1 / vCenter 9.1 / ESXi×4 9.1 / vSAN green（SDDC Mgr 仍 5.2.1）

> 圖例：[x] 完成　[~] 進行中　[ ] 待辦
