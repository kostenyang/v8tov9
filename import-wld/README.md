# 把既有 vSphere 匯入成 VI workload domain,並與管理網域共用同一套 NSX

> ✅ **2026-10-02 ~ 10-03 實測成功**
> 既有 vSphere(vCenter 8.0.3 + ESXi 8.0 U3b ×3 + vSAN)→ 只把 vCenter 升到 9.1.1 →
> 以 VI workload domain 匯入既有的 VCF 9.1.1 執行個體 → **與管理網域共用同一套 NSX**。
> 匯入 57/57 子任務成功,約 15 分鐘;主機全程維持 ESXi 8.0.3-24280767。

成品文件:[`VCF911-CoverageLab-ImportWLD.docx`](VCF911-CoverageLab-ImportWLD.docx)(29 頁 / 27 張逐步截圖)

## 結論

| 問題 | 結論 | 依據 |
|------|------|------|
| 另一套既有 vSphere 能匯入成 VI workload domain 嗎? | ✅ 能 | 匯入任務 57/57 成功,domain 狀態 ACTIVE |
| 能和管理網域共用同一套 NSX 嗎? | ✅ 能 | 兩個 domain 的 `nsxtCluster.id` 相同;`/v1/nsxt-clusters` 同一筆下列著兩個 domain |
| 主機可以留在 ESXi 8.0 U3b 嗎? | ✅ 可以 | 匯入後 `/v1/hosts` 仍是 `8.0.3-24280767` |
| vCenter 可以不升嗎? | ❌ 要共用 NSX 9.1 就得升到 9.1 | 官方:*NSX 9.1 does not support vCenter 8.0 Update 3a or later* |
| 匯入會自動把主機 prep 成 NSX transport node 嗎? | ❌ 不會 | 匯入後 host transport node 仍只有管理網域那幾台 |

## 入口在哪

**不是** VCF Installer。VCF Installer 的 `workflowType = VCF_EXTEND` 是「把既有 VVF 補成 VCF」,
不是匯入工作負載網域(繞路紀錄見 [`cli/vcf-extend-not-import.txt`](cli/vcf-extend-not-import.txt))。

正確路徑(VCF Operations):

```
Operate → Inventory → Detailed View → 展開 VCF Instances → 選目標 VCF Instance
→ ADD WORKLOAD DOMAIN ▾ → Import a vCenter
```

精靈 5 頁:General Information → Specify a vCenter → Certificate Thumbprint → Prechecks → Review。

## 前置條件(官方)

- vCenter 最低 **8.0 Update 3a**;ESX 最低 **8.0 Update 3**
- inventory 內所有 ESX 主機要用 FQDN,不可用短名
- 既有 vCenter 要開 SSH
- 共用 NSX:**Shared NSX instances are supported across multiple vCenter instances**
- 🔴 要接 **NSX 9.1**,vCenter 必須先升到 **9.1**(NSX 9.1 不支援 vCenter 8.0 U3a 以後的版本)

來源:[Import an Existing vCenter to Create a Workload Domain](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/building-your-private-cloud-infrastructure/working-with-workload-domains/import-an-existing-vcenter-to-create-a-workload-domain.html)

## 第一輪 precheck 的 3 個 Error 與修法

| Error | 訊息 | 修法 |
|-------|------|------|
| **Import NSX-vCenter compute manager** | `Could not find compute manager for vCenter <wld-vc> in NSX <shared-nsx>` | 先在那套 NSX 把要匯入的 vCenter 註冊成 Compute Manager(`POST /api/v1/fabric/compute-managers`)。這是**前置條件**,不是禁止共用 |
| **Cluster Distributed Resource Scheduler (DRS)** | `Cluster does not have DRS fully automated` | 本 lab 叢集本來就是 fullyAutomated,vCenter 剛升完被驗到不穩狀態,重跑即過 |
| **Cluster is vLCM image based** | `Cluster is not vSphere Lifecycle Manager (vLCM) image based` | Cluster → Updates → Image Setup →「沿用現行映像」(PROCEED WITH THIS IMAGE)。主機版本完全不動,離線 depot 沒有該版 depot zip 也不受影響。⚠ 完成後叢集無法退回 baseline |

同一輪的 `Check NSX Manager host scale support` 與 `Compatibility validation for vCenter and NSX` 都是 **Success** ——
共用 NSX 本身 VCF 沒有意見。

第二輪:**71 Passed / 0 Errors / 1 Warning**(唯一的 Warning 是 ESXi upgrade policy 與 SDDC Manager 預設值不同,不擋匯入)。

## 目錄

| 路徑 | 內容 |
|------|------|
| `VCF911-CoverageLab-ImportWLD.docx` | 成品文件 |
| `PHASE4-import-runbook.md` | 匯入 runbook |
| `shots/` | 逐步截圖 |
| `cli/` | API / CLI 佐證(密碼已清) |
| `scripts/` | 建來源端與驗收用的腳本 |

## 關鍵佐證

```
GET /v1/nsxt-clusters
  vcf-m02-nsx01.home.lab | version 9.1.1.0.25691509
      domain: vcf-m02   083d4bfe-...   (MANAGEMENT)
      domain: vcf-w01   61bc9cc1-...   (VI, imported)

GET /v1/hosts
  vcf-m02-esx01~04.home.lab   ASSIGNED   esxi=9.1.1.0.25714478
  vcf-w01-esx01~03.home.lab   ASSIGNED   esxi=8.0.3-24280767
```

完整輸出見 [`cli/import-result.txt`](cli/import-result.txt) 與 [`cli/shared-nsx-proof.txt`](cli/shared-nsx-proof.txt)。
