# Context — VCF 5.2.1 → 9.1 升級

## 目前狀態 (2026-07-15)：升級完成，lab 開機中
**升級全部完成 (2026-07-13)**：NSX 9.1.0.0100.25470810（MP/HOST/EDGE/FINALIZE 全 SUCCESS）· vCenter 9.1.0.0100 b25417926（.142）· ESXi ×4 9.1.0 build-25433460 · vSAN green · 已推 github.com/kostenyang/v8tov9 (42abff0)。SDDC Manager 仍 5.2.1（刻意脫離 LCM）。

**現在進行中**：lab 之前乾淨關機（vSAN reboot_helper prepare），現正開機中。
- 4 台 nested ESXi VM 已從 Xindian .32 開機、ping 通，但 **SSH refused（reboot 後預設關）**。
- vCenter (vc01-9) 還關著（在 vSAN 上，vSAN 尚在 shutdown mode 需 recover）。
- **雞生蛋**：recover 需 SSH → 平常靠 vCenter 啟 SSH → vCenter 需 vSAN recover。**解法：直接連 host 自己的 /sdk API（root）啟 SSH，不透過 vCenter。**

**開機待辦順序**：① host /sdk 直接啟 SSH → ② `reboot_helper.py recover`（任一 host）→ ③ 4 台 exit MM → ④ 開 vc01-9 → ⑤ vCLS 自動起、DRS 恢復 → ⑥ 補升級截圖（文件圖片有缺）→ ⑦ 部署 VCF Operations / Installer / License Server。

## 環境 / 存取
| 角色 | IP | 認證 |
|------|-----|------|
| 外層 Xindian vCenter | 192.168.110.32 | administrator@vsphere.local / <PHYSICAL_VC_PASSWORD> |
| 實體 ESXi (外層) | 192.168.110.16 | ESXi 8.0.3 · Xeon E5-2682 v4 (Broadwell) |
| Nested vCenter (VCF) | 192.168.110.142 | administrator@vsphere.local / <VC_ESXI_PASSWORD> |
| 新 vCenter appliance (暫時) | 192.168.110.151 | root / <VC_ESXI_PASSWORD> |
| Nested NSX Manager | 192.168.110.143 | admin / <NSX_PASSWORD>（API basic）|
| Nested ESXi ×4 | 192.168.110.145–148 | root / <VC_ESXI_PASSWORD>（SSH 需先 API 啟用）|
| SDDC Manager | 192.168.110.141 | — |
| ADSrv / DNS (kosten.lab) | 192.168.110.1 | — |
| Nested cluster | MoID `domain-c9` (vcf-m01-cl01) | hosts host-12/26/28/30 = esx01/02/03/04 |
| Nested ESXi VM (在 Xindian) | vm-29025..29028 = esx01..04 | — |

## 關鍵決策 + 理由
- **guestId 改 vmkernel8Guest + vHW-20**（4 台 nested ESXi VM，在 Xindian .32）：原 guest type=Other(64bit) 不開 MWAIT → CRX vCLS 開不了機 → DRS 失效。這是解 NSX Host 升級卡關的根因。存於 vmx，持久（停電後 vCLS 自動恢復）。
- **靜音 vSAN HCL 健康測試**（controllerdiskmode 等）：nested 虛擬控制器未認證呈黃，vLCM 以 overall_health_not_green 擋 host 進 MM。
- **vcsa-deploy 用 `--upgrade-framework legacy`**：預設 RDU 在 nested DRS 叢集資源驗證卡死。
- **`--skip-product-interop-check`**：來源 vCenter 曾擋 NSX 4.2.1；先升 NSX 後解除。
- **NSX 升級用 session+XSRF API 驅動**：NSX UC 的 Angular iframe 常凍結 CDP（screenshot timeout）。
- **不打 snapshot**：使用者要求（太慢）。
- **allowLegacyCPU=TRUE (boot.cfg kernelopt) + --no-hardware-warning**：Broadwell 被 VCF9 列 discontinued，此法可在該 CPU 開機 ESXi 9.1。

## 關鍵檔案路徑 (專案根 C:\Users\mjalan\Documents\vspher8to9\)
- `vcsa91-upgrade.json` — vCenter migration 範本（temp IP .151→.142, migrateSet core）
- `doc\build_doc.py` + `doc\VCF-5.2.1-to-9.1-Manual-Upgrade.docx` — 交付文件（11 章/4 圖）
- `shots\*.png` — 各階段截圖（grab.ps1 用 PrintWindow 抓 Chrome 視窗）
- NSX：`nsx-continue.ps1`（action/component 續跑）、`nsx-monitor.ps1`、`nsx-upg-status.ps1`
- vLCM/vSAN/vCLS 修復：`vclcm-recheck.ps1`、`vsan-silence.ps1`、`vcls-retreat.ps1`、`vcls-monitor.ps1`
- MWAIT 修復：`xindian-setguestos.ps1`、`upgrade-hw-guest.ps1`、`enable-ssh.ps1`
- ESXi 9 CPU 繞過：`patch-boot.sh`、`https_repo.py`（在 v8tov9 git）
- memory：`~\.claude\...\memory\vcf521-nested-lab.md`（完整踩坑記錄）

## 常用 API / 指令
- NSX 續跑：`POST https://<nsx>/api/v1/upgrade/plan?action=continue&component_type=HOST`（先 POST /api/session/create 拿 x-xsrf-token）
- NSX 狀態：`GET /api/v1/upgrade/status-summary?component_type=HOST`（basic auth）
- vLCM precheck：`POST /api/esx/settings/clusters/domain-c9/software?action=check` body `{}`
- vSAN 靜音：SOAP `VsanHealthSetVsanClusterSilentChecks`（https://vc/vsanHealth, SOAPAction urn:vsan/8.0.2.0）
- 新機 deployment 狀態：`GET https://151:5480/rest/vcenter/deployment`（root basic）
- vCenter SOAP：/sdk 需 SOAPAction `urn:vim25/8.0.2.0`（否則綁到舊 vim2.5）
