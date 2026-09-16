# Converge 到 VCF 9.1.1 —— 不給 Host TEP (VTEP) 網段

> 問題：客戶只給管理網段，沒有 NSX Host Overlay (TEP) 網段，9.1.1 用 converge 建 management domain 行不行？
> **答：可以。** 9.1.x converge 流程支援把 host overlay 直接跑在管理 VMkernel (vmk0) 上，不需要另外的 TEP VLAN / subnet / IP pool。
> Edge 不在本文範圍（本 lab 不部 Edge）。

## 依據

| 來源 | 內容 |
|------|------|
| techdocs 9.1 [Supported and Not Supported Configurations to Converge to VCF](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/deployment/converging-your-existing-vsphere-infrastructure-to-a-vcf-or-vvf-platform-/supported-and-not-supported-configurations.html)（2026-09-14 版，涵蓋 9.1.1） | "You can choose to configure overlay traffic on a **management VMkernel** or on a VLAN-backed segment." |
| VCF Installer OpenAPI `SddcNsxtSpec` | `skipNsxOverlayOverManagementNetwork` (boolean)："Flag that indicates if the Overlay over Management Network configuration will be skipped. **Applicable only when vCenter is existing and being converted.**"<br>`required` 只有 `nsxtManagers`、`vipFqdn`；`transportVlanId`、`ipAddressPoolSpec` 皆選填。 |
| techdocs 9.1 [Use a JSON Specification File](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/deployment/deploying-a-new-vmware-cloud-foundation-or-vmware-vsphere-foundation-private-cloud-/use-a-json-specification-to-deploy-vmware-cloud-foundation-or-vmware-vsphere-foundation.html) | 官方 converge 範例 `domainSpec-sfo-m01-example03.json`（本檔即以它為骨架改寫）；並列出 converge 各 spec 的 `useExistingDeployment` 對照表。 |
| [VCF 9.1.1.0 Release Notes](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-9-0-and-later/9-1/release-notes/vmware-cloud-foundation-9-1-1-0-release-notes.html) | 可直接 converge 到 9.1.1；此選項無變更。 |

## 關鍵欄位

```json
"nsxtSpec": {
  "useExistingDeployment": false,              // 部新 NSX
  "nsxtManagers": [ { "hostname": "..." } ],
  "vipFqdn": "...",
  "skipNsxOverlayOverManagementNetwork": false // ★ false = overlay 走 vmk0，不需要 TEP
  // 不要給 transportVlanId / ipAddressPoolSpec
}
```

UI 精靈對應：NSX 頁的 **「Overlay over Management Network」** 選項。

對照官方範例 `example03`：它是 `skipNsxOverlayOverManagementNetwork: true` **加** `transportVlanId` + `ipAddressPoolSpec`（要 TEP 網段）。本範本反過來。

## 範本：[`converge-m01-no-tep.json`](converge-m01-no-tep.json)

以本 repo 的 lab（`kosten.lab` / 192.168.110.0/24 / 既有 `vcf-m01-vc01`）填值，密碼全部 `<PLACEHOLDER>`。

| 區塊 | 設定 | 說明 |
|------|------|------|
| `workflowType` | `VCF` | converge 到新 fleet |
| `vcenterSpec` | `useExistingDeployment: true` + `sslThumbprint` | 既有 vCenter，thumbprint 用 SHA256 |
| `nsxtSpec` | 新部、單節點 medium、**無 TEP** | 3 節點 HA 就多填兩個 hostname |
| `vcfManagementComponentsInfrastructureSpec.xRegionNetwork` | 管理元件要落的既有 portgroup | converge 沒有 `networkSpecs`/`dvsSpecs`，靠這個指定放哪 |
| `vspClusterSpec` | 12 個 IP | VCF Management Services；`198.18.0.0/15` 若已在用改 `240.0.0.0/15` |
| `vcfOperationsSpec` / `vidbSpec` / `licenseServerSpec` | 新部 | 若 Ops 已手動裝好（見 [`../deploy-ops-license.md`](../deploy-ops-license.md)）改 `useExistingDeployment: true` + node `sslThumbprint` |
| `vcfAutomationSpec` | **省略** | 本 lab 不部 VCFA |
| `hostSpecs` / `networkSpecs` / `dnsSpec` / `ntpServers` | **省略** | 既有 vCenter 直接讀，官方 converge 範例同樣沒有這些 |

### 匯入既有 NSX 的變體

本 lab 目前 NSX 9.1 已存在（`vcf-m01-nsx01a`，前面手動升的），若選匯入而非新部：

```json
"nsxtSpec": {
  "useExistingDeployment": true,
  "nsxtManagers": [ { "hostname": "vcf-m01-nsx01a.kosten.lab" } ],
  "vipFqdn": "vcf-m01-nsx01.kosten.lab",
  "nsxtAdminPassword": "<NSX_ADMIN_PASSWORD>",
  "sslThumbprint": "<NSX_SHA256_THUMBPRINT>"
}
```

匯入時 host 維持原狀（未 prepare 的 cluster 不會被 prepare），連 overlay-over-mgmt 都不會碰，TEP 問題不存在。

## 送出

```bash
# 1) 驗證（回 202，用 /v1/sddcs/validations/latest 追）
curl -sk -u admin@local:<PW> -H 'Content-Type: application/json' \
  -X POST https://<installer>/v1/sddcs/validations -d @converge-m01-no-tep.json

# 2) 部署（回 202 + sddc id，用 /v1/sddcs/{id} 追 milestones / sddcSubTasks）
curl -sk -u admin@local:<PW> -H 'Content-Type: application/json' \
  -X POST https://<installer>/v1/sddcs -d @converge-m01-no-tep.json
```

或 installer UI「Convert or import existing vSphere environments」→ 上傳 JSON。

## 坑 / 條件

1. **管理 VLAN 端到端 MTU ≥ 1600。** Geneve 走 vmk0，實體交換器管理 VLAN 要開 jumbo。installer 的 `NSX Host Overlay Network Connectivity` validation **抓不到 MTU 不足**——1500 照樣過驗，部完 overlay 直接壞。
2. **只適用 converge。** greenfield 沒有這個選項，一定要給 TEP（沒網段的替代法：TEP pool 與 mgmt 同 VLAN 同 subnet、另切 IP）。
3. overlay 與管理流量同一 broadcast domain、無隔離；lab / 小型可接受，正式環境建議另給網段。
4. `version` 填 installer 實際版本（9.1.1 installer 填 `9.1.1.0`）。
5. 本 repo 手上的 OpenAPI 副本是 9.1.0.0 installer；9.1.1 的 techdocs 文字與 RN 皆無變更，但送前建議 `GET https://<installer>/v1/sddcs/latest` 或 UI 精靈確認選項仍在。
