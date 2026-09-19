# Converge 到 VCF 9.1.1 —— 不給 Host TEP (VTEP) 網段

> ✅ **2026-09-19 實測成功(多 cluster)**:vCenter 9.1.1 下兩個 cluster(ESXi 9.1.1 ×4 + ESXi 8.0U3b ×4,後者是從 VCF 5.2.1 搬過來帶資料的 vSAN cluster),
> 新部 NSX 9.1.1、overlay 走 vmk0、不給 TEP,`COMPLETED_WITH_SUCCESS` 181/181。實際用的 spec 見 [範本 3](#範本-3新部-nsxoverlay-over-management多-cluster2026-09-19-實測成功)。

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

---

# 範本 2:沿用既有 NSX + 多 cluster(2026-09-19 實測成功)

檔案:[`converge-m02-existing-nsx-multicluster.json`](converge-m02-existing-nsx-multicluster.json)

情境:vCenter 9.1.1 底下有兩個 cluster —— `m01-cl01`(ESXi 9.1.1,已是 NSX 9.1.1 transport node)與 `vcf-m01-cl01`(ESXi 8.0U3b,從 VCF 5.2.1 環境照 KB 326849 帶資料搬過來、無 NSX)。
用 VCF Installer 9.1.1「DEPLOY USING JSON SPEC」把整個 vCenter converge 成 management domain,結果 `COMPLETED_WITH_SUCCESS`,SDDC Manager 兩個 cluster 都納管。

| 區塊 | 與範本 1 的差異 |
|---|---|
| `nsxtSpec` | `useExistingDeployment: true` + VIP 的 `sslThumbprint`;不給 TEP、不給 overlay 選項。既有 transport node 保留,**沒 prepare 的 cluster 不會被 prepare** |
| `clusterSpec` | 指定既有 `datacenterName` / `clusterName`(管理元件落點) |
| `datastoreSpec` | **不能放**。`existingDatastoreName` 會套到 vCenter 內每一個 cluster,第二個 cluster 找不到就 `Existing Components` FAILED |
| `fleetLcmSpec` / `sddcLcmSpec` | 明給 hostname(與 vspClusterSpec 的 fleetFqdn / instanceFqdn 一致) |

實測驗證會逐 cluster 檢查的項目(每個 cluster 都要過):
- vLCM image 模式(baseline 會擋)
- vLCM 修復原則 `evacuate_offline_vms` 必須 = true(預設 false)→ `PUT /api/esx/settings/clusters/{id}/policies/apply {"evacuate_offline_vms":true}`
- datastore 存在、VDS ≥ 8.0、vmk 靜態 IP
- **不檢查** cluster 之間 ESXi 版本是否一致(9.1.1 + 8.0U3b 混用通過)

其他:
- 做過 bring-up 的 installer 資料庫記著舊 domain,converge 要用乾淨的 installer
- vCenter 上若殘留同名 SDDC Manager VM 要先刪(`Validate Virtual Machine Names Do Not Exist`)
- 各階段耗時(nested):SDDC Manager 27m / Convert 6m / VSP 2h40m / Ops 1h24m / VCFMS 1h17m


---

# 範本 3:新部 NSX、overlay over management、多 cluster(2026-09-19 實測成功)

檔案:[`converge-m02-newnsx-overlay-mgmt-multicluster.json`](converge-m02-newnsx-overlay-mgmt-multicluster.json)

= 範本 1 的做法(`useExistingDeployment:false` + `skipNsxOverlayOverManagementNetwork:false`、無 TEP)套到範本 2 的多 cluster 環境,**實際跑完**。

## 實測結果

| 問題 | 答案 |
|---|---|
| 多 cluster + 新部 NSX,installer prep 哪些 cluster? | **全部**。每個 cluster 各建 TNP(`<vc>-<cluster>`)+ Transport Node Collection、各自的 VLAN TZ(每 vDS 一個),共用一個 overlay TZ;8 台 transport node 全 success |
| NSX 9.1.1 能不能 prep ESXi 8.0U3b? | 能。8.0U3b 主機裝 `nsx-* 9.1.1.0-8.0.25691512`(8.0 flavor),vLCM 映像加 `com.vmware.nsxt` solution;9.1.1 主機 NSX VIB 在 base image 內建,映像不加 solution |
| overlay over management 要 TEP IP 嗎? | 不要。TNP `ip_assignment_spec.resource_type = NoIpv4`,主機不新增 TEP vmk(只有 vmk0/1/2 + vmk50 hyperbus) |
| 任務數 | 183(沿用既有 NSX 是 134),多「Deploy and configure NSX」階段 45 分鐘(nested) |
| 各階段耗時(nested) | Convert 5m / NSX 45m / VSP 2h21m / Ops 1h17m / VCFMS 1h12m |

## 驗證差異(相對範本 2)
- `Existing Components` 多一個 **WARNING**「cluster 是 vLCM image based,請確認 compliance」(每個 cluster 各列一條),cluster 已 COMPLIANT 時 acknowledge 即可。
- NSX 的 INSTALL bundle 沒下載完會直接 **FAILED**(`NSX install image ... was not found`)。

## 前置(客戶端)
- mgmt VLAN **端到端 MTU ≥ 1600**(實體交換器、vDS、vmk0)。installer 驗證抓不到 MTU 不足:1500 也會 converge 成功,但之後 overlay(VPC / Supervisor / VCFA 租戶網路)>1450 bytes 封包會丟。
- 所有 cluster 都會被 prep → NSX 授權、MTU 要涵蓋所有 cluster;不想 prep 的 cluster 事先不要放在這個 vCenter。
- import 進來的舊版 cluster,converge 會把 vLCM desired image 設成 BOM 版本(9.1.1)→ 之後 compliance NON_COMPLIANT,預期用 LCM 升級。
