# 階段 4:把 w01 匯入成 VI workload domain,並共用管理網域的 NSX

## 官方路徑(VCF 9.1)
VCF Operations → **Operate** → **Inventory** → **Detailed View** → 展開 **VCF Instances**
→ 選 `vcf-m02-converge` → **Add workload domain** ▾ → **Import a vCenter**

## 本 lab 的輸入
| 欄位 | 值 |
|------|-----|
| Workload domain 名稱 | `vcf-w01` |
| vCenter | `vcf-w01-vc01.home.lab` (10.0.1.49),administrator@vsphere.local |
| vCenter 版本 | 9.1.1(階段 3 剛升完) |
| 主機 | `vcf-w01-esx01~03.home.lab`,ESXi **8.0 U3b** 24280767 |
| 儲存 | vSAN OSA,1500 GB |
| NSX | **join 既有** `vcf-m02-nsx01.home.lab`(NSX 9.1.1,管理網域在用) |

## 為什麼 vCenter 一定要先升到 9.1
官方前置條件寫明:**NSX 9.1 不支援 vCenter 8.0 Update 3a 以後的版本**;
要讓匯入的網域接 NSX 9.1,vCenter 必須先升到 9.1。主機可以留在 8.0U3b
(import 的最低需求是 ESX 8.0 U3)。

## 前置檢查
- [x] 所有 ESX 主機在 inventory 內是 FQDN(不是短名)
- [x] 既有 vCenter 開 SSH(`ssh_enable: true`)
- [ ] vCenter 已升到 9.1.1 並可登入
- [ ] 舊的 8.0.3 appliance VM 已關機、改名

## 走過的冤枉路(留在文件裡當對照)
VCF Installer 的 `workflowType = VCF_EXTEND` **不是** workload domain import,
它是「把既有 VVF 補成 VCF」。詳見 `cli/vcf-extend-not-import.txt`。
