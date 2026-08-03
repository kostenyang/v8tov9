# 全新重建追蹤 — VCF 5.2.1 → 9.1 + Ops + License（含逐步截圖 → docx）
開始：2026-07-28。媒體：E:\Nested_ESXi8.0u3g_Appliance_Template_v1.ova (0.85GB)、E:\VMware-Cloud-Builder-5.2.1.0-24307856_OVF10.ova (29GB)。

## 目標
毀現有 9.1+Ops → 從 5.2.1 從頭 bringup → 升 9.1（NSX→vCenter→ESXi→Finalize）→ 部 Ops + License → 每步乾淨截圖 → 組 docx。
截圖法：headless Chrome `--ignore-certificate-errors --screenshot`（單頁）、CDP（登入後多步 UI）、VM CreateScreenshot（firstboot/console）。

## 環境
- 實體/外層 Xindian vCenter 192.168.110.32 (administrator@vsphere.local / <PHYSICAL_VC_PASSWORD>)；DC="Xindian Datacenter" Cluster="XinDian Cluster"(DRS off) DS="Datastore2"；PG=VCF-Nested(vSwitch0 VLAN4095 promisc)
- nested 網段 192.168.110.140-148；DNS ADSrv .1 (kosten.lab)；GW .254
- 要毀的 VM：vcf-m01-esx01..04 (vm-29025..29028) + vcf-m01-cb01 (vm-29029)

## Phases
- [x] P1 毀現有 nested lab（5 VM 全刪，2026-07-28）
- [x] P2 部 4 台 nested ESXi + Cloud Builder（30 分，vcf-config.json 產生，評估模式）
- [x] P3 DNS 確認（9/9 A 正解全對；4 host + CB 全 ping UP、ESXi/CB API 200）
- [x] P4 bringup 5.2.1 **COMPLETED_WITH_SUCCESS**（2026-07-29 00:15，約 2h40m）
  - [x] Cloud Builder 登入頁 shots/p4-cloudbuilder-login.png
  - [x] validation SUCCEEDED → deployment COMPLETED_WITH_SUCCESS
  - [x] 5.2.1 基準截圖：p4-sddcm-521 / p4-vcenter-521 / p4-nsx-521.png
  - bringup id c290c11d-d1f9-415c-8a43-40bd6266b672
- [~] P5 升級 9.1：NSX(MP/Host) → vCenter(migration) → ESXi×4 → NSX Finalize + **每步乾淨截圖（務必進 docx）**
  - 媒體：NSX .mub 9.1.0.0200(25524170) / VCSA ISO 9.1.0.0300(25629530) / ESXi depot 9.1.0.0100(25433460)
  - before 基準：NSX 4.2.1.0.0.24302016、vCenter 8.0.3、ESXi 8.0.3；截圖 p5-nsx-before-421.png
  - [~] NSX：EULA→bundle SUCCESS→UC 升級（uc_version 9.1.0.0200.25524172）→ **plan?action=start 200，MP 升級中**
    - 坑：EULA 要「重接受」才 stick；bundle status = `/upload-status`；啟動 = `POST /api/v1/upgrade/plan?action=start`（含 XSRF，session/create 取 token）
    - target: MP 9.1.0.0200.25524172 / HOST ...171 / EDGE ...173 / FINALIZE ...170
    - [x] **MP 升級 SUCCESS**（node_version 9.1.0.0200.25524172）→ overall PAUSED；截圖 p5-nsx-mp-91.png
    - [x] Host 前置修復：nested VM otherGuest64/vmx-14 → **esx03(vm-30006)/esx04(vm-30007) 改 vmkernel8Guest+vmx-20**（upgrade-hw-guest.ps1）→ vCLS 在 esx03 起來（quorum）→ DRS 功能；vSAN HCL 靜音（vsan-silence.ps1）；resync=0
    - [x] **HOST 升級 SUCCESS 4/4**（9.1.0.0200.25524171，vSAN resync=0，全 Connected）；截圖 p5-nsx-host-91.png
    - overall PAUSED（EDGE 無節點、FINALIZE 待 vCenter 9.1）
  - [x] **vCenter migration 8.0.3→9.1 SUCCESS**（~50 分，vcf-m01-vc01-9 @ .142，9.1.0 build 25629530，4 host Connected，resync=0）；截圖 p5-vcenter-91.png
    - precheck exit 0；正式 upgrade --upgrade-framework legacy --skip-product-interop-check；VCSA ISO 掛 G:
  - [~] ESXi ×4 → 9.1（profile-update，Broadwell 免 allowLegacyCPU）
    - 順序：esx03(host-28,空)→esx01(host-12,nsx)→esx04(host-30,sddc)→esx02(host-26,vCenter)最後
    - 前置：4 台 SSH 開（vCenter PowerCLI）、清 plink 舊 host key 重新接受、depot HTTP :8080 (E:\esxi91-depot)、profile ESXi-9.1.0.0100-25433460-standard
    - 坑：host 連本機 .200:8080 被 Windows 防火牆擋（無 admin 加不了規則；NSX bundle 之前僥倖過）→ **改把 692MB depot 複製到 vSAN datastore，用本機路徑 `-d /vmfs/volumes/vcf-m01-cl01-ds-vsan01/esxi91-depot/index.xml`**
    - 坑：esx03 reboot 後 SSH 關 → 每台升級前用 vCenter PowerCLI 重開 SSH；plink host key 主機重建後要清舊快取（HKCU PuTTY SshHostKeys）重新接受
    - **關鍵坑（0200 bundle 特有）**：NSX host VIB 是 9.1.0.0200-**8.0** flavor（要求 esx<<8.1）→ `profile update` 到 ESXi9.1 被 DependencyError 擋；`vib remove` live 失敗（nsx-datapath 使用中）。**解法：`esxcli software profile install -d <vSAN depot> -p ESXi-9.1.0.0100-25433460-standard --no-hardware-warning --ok-to-remove --no-live-install --maintenance-mode`** → 一次換掉：移 ESXi8.0+NSX-8.0 VIB、裝 ESXi9.1+NSX-9.1 VIB（depot 內含 nsx-*_9.1.0.0100-9.1）。vSAN disk 仍 In CMMDS（mock VIB 不需重加）。已改進 esxi-upgrade-host.ps1。
    - 每台前置：vCenter PowerCLI 開 SSH（reboot 後會關）；SOAP 8.0.2.0 對 vC9.1 相容
    - [x] **ESXi ×4 全 9.1.0 build 25433460**（Connected、無 MM、vSAN resync=0）
    - 腳本 bug 修：`$out -notmatch` 對陣列判斷錯 → 改 `-not ($out -match ...)`；reboot 偵測有 race（vCenter 快取），完成後另用輪詢驗證版本到 9.1.0
  - [x] **NSX FINALIZE SUCCESS 100%**（product_version 9.1.0.0200.25524170）；`POST plan?action=upgrade&component_type=FINALIZE_UPGRADE`（continue 不推進 FINALIZE）；截圖 p5-nsx-final-91.png
  - [x] **🎉 P5 全部完成**：NSX 9.1.0.0200 · vCenter 9.1.0 (25629530) · ESXi×4 9.1.0 (25433460) · vSAN resync=0
  - NSX：bundle 匯入 / pre-check / MP SUCCESS / Host 4/4 SUCCESS / Finalize SUCCESS / 版本頁
  - vCenter：precheck / 部署進度 / 9.1 完成（build 頁）
  - ESXi×4：每台 9.1 build 畫面 / vSAN green
  - **升級圖是 docx 重點 —— 使用者特別要求**
- [x] **P6 完成：Ops + License 都部署好**
  - [x] Ops (.150)：Import-VApp → 關機設 IP/root_pw/domain → 單次開機 → CaSA **INITIALIZED**；admin OK；p6-ops-login/p6-ops-dashboard
  - [x] License (.151)：**OVA 簽章 PowerCLI 不信 → 解 OVA 移 .cert/.mf 變 unsigned OVF 再 Import-VApp**；設 hostname/ip/otk(placeholder)/dns/domain → 開機（console "Started License Server Operator"）；p6-lic-console
  - **otk 確認 BSC-gated**（兩環境 /casa/license/registration-key 都 500）→ air-gapped 無法真正註冊；使用者定調「有圖就好」otk 用 placeholder
- [~] P7 組 docx（含所有乾淨截圖，升級圖為重點）
- [ ] P8 sanitize（密碼→placeholder，sanitize-and-stage.ps1）→ push github.com/kostenyang/v8tov9（腳本+docx+截圖+rebuild.md）

## 已確立的技術點（沿用上次）
- ESXi 9.1 on Broadwell：profile-update 路徑不需 allowLegacyCPU；depot HTTP serve E:\esxi91-depot
- MWAIT/vCLS：nested VM 需 guestId=vmkernel8Guest + vHW-20（在 Xindian 設）
- vLCM host 升級：靜音 vSAN HCL 健康測試 + 修 vCLS quorum
- vCenter 升級：vcsa-deploy --upgrade-framework legacy --skip-product-interop-check，temp IP .151
- Ops 部署：PowerCLI Import-VApp；firstboot 不可打斷；CaSA init（curl.exe）到 INITIALIZED
- appliance HTTPS 一律用 curl.exe（PS5.1 .NET TLS 太舊）
