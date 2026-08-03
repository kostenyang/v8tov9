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
- [x] **開機完成 (2026-07-15)**
  - [x] Xindian .32 開 4 台 nested ESXi VM
  - [x] host /sdk 直接啟 SSH（ha-sessionmgr + serviceSystem MoRef）
  - [x] 4 台 exit MM → `reboot_helper.py recover`（成功）
  - [x] 開 vc01-9（vim-cmd vmsvc/power.on 1 on esx04）→ vCenter API UP、4 host CONNECTED
  - [~] 開 nsx01a/sddcm01 + vCLS retreat=true（進行中，等服務起來）

## 📸 現有截圖品質差（確認結果）
- 16/17（hosts-success、finalize）= 全壞，抓到 claude.ai 空白頁
- 10（mgr-success）= 其實是 MP「失敗」畫面 + 有 Claude debug 橫幅 + 一排雜亂分頁
- vCenter / ESXi / vSAN 完全沒圖
- 根因：grab.ps1 PrintWindow 抓前景視窗，常抓錯 tab、沒關 debug 橫幅

## 🎯 使用者定案計畫（2026-07-15）：整個重裝重升 + 好好截圖 → docx
媒體：E:\Operations-Appliance-9.1.0.0400.25541561.ova (3.1GB)、E:\Vcf-License-Server-9.1.0.0400.25541557.ova (0.6GB)
- [x] **① 確認 License Server + VCF Operations 手動裝法（官方）→ 寫成 deploy-ops-license.md**
  - 順序：Ops 先 → License 後（License 要填 Ops 給的 registration key）
  - 都用 vCenter OVF 部署（非 ESXi host client）；前置 DNS A+PTR + NTP
  - License Server VM Domain Name 只填 domain 不填 FQDN（否則授權靜默失敗）
- [x] **①b 技術確認：VCF Operations 實際部起來 + 設定好（2026-07-28 完成）**
  - [x] ovftool 探 Ops/License OVA：size、OVF 屬性、依賴（License 需 Ops 的 otk）
  - [x] 資源確認：叢集 free 145GB/65GHz、vSAN free 2234GB → 夠
  - [x] 部署法定案：**PowerCLI Import-VApp**（ovftool 裸 `--prop` 對 instance `VMware_Aria_Operations` 網路屬性無效；vi:// 路徑也不穩）
  - [x] 坑：firstboot 不可打斷（中途 power-cycle → 卡死 25MHz）→ 關機設好 IP → 單次開機
  - [x] CaSA 初始化：thumbprint → POST /casa/cluster(init) 202 → 輪詢 **INITIALIZED**（TLS 用 curl.exe）
  - [x] 驗證：admin 登入 OK、版本 9.1.0.0 build 25541561、截乾淨圖（登入頁 + 登入後 setup wizard）
  - [x] DNS：使用者在 ADSrv 加好 vcf-ops01→.150 / vcf-lic01→.151
  - [ ] License Server：otk 產生疑似需 Broadcom BSC（`/casa/license/registration-key` 回 500）→ air-gapped 受限，待確認/決定
- [ ] ② 整個重裝：毀現有 9.1 → Cloud Builder 重新 bringup 5.2.1
- [ ] ③ 重升 5.2.1 → 9.1（NSX→vCenter→ESXi），每步乾淨截圖（單一分頁、關 debug 橫幅、對的畫面）
- [ ] ④ 部署 VCF Operations + License Server（截圖）
- [ ] ⑤ 全部組成完整 docx

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
