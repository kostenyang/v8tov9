# VCF Operations + License Server 手動部署 SOP (VCF 9.1)

> 來源：Broadcom techdocs（Deploy VCF Operations Nodes）+ giovannidominoni / captainvops（License Server）。
> 媒體：`E:\Operations-Appliance-9.1.0.0400.25541561.ova` (3.1GB)、`E:\Vcf-License-Server-9.1.0.0400.25541557.ova` (0.6GB)

## 依賴與順序（重要）
**先 VCF Operations → 後 License Server**。License Server 部署時要填的 **registration key** 是從 VCF Operations 的「Add License Server」精靈拿的。

## 前置
- DNS：兩台各需 A + PTR record（在 ADSrv .1 / kosten.lab）。本 lab 用 `vcf-ops01→.150`、`vcf-lic01→.151`（腳本 `prep-dns-opslic.ps1`）。
- NTP：兩台都要能同步（時鐘偏移會壞憑證/授權）。**Ops OVA 沒有 NTP 屬性 → NTP 在開機後的 setup wizard 設**（不是 OVF property）。
- **一定用 vCenter 的「Deploy OVF Template」部署，不要用 ESXi host client**（後者 bypass vApp OVF property injection → 要刪掉重來）。

## ⚠️ ovftool 屬性注入的坑（2026-07-27 技術確認實測）
用 ovftool CLI 部 Operations 時，網路屬性（`DNS`/`domain`/`searchpath`/`ipv4_type`/`ipv4_address`/`ipv4_gateway`/`ipv4_netmask`/`ipv6_type`）**屬於 product instance `VMware_Aria_Operations`，裸 `--prop:DNS=...` 會被忽略**（ovftool 回 "OVF property with key: 'DNS' does not exists"）；只有 `root_password`、`timezone`（預設段）吃得到。結果 VM 用預設 DHCP 開機、拿不到 IP。
**解法（擇一）**：
- **GUI**：vSphere Client「Deploy OVF Template」精靈的「Customize template」頁直接填 → GUI 會正確對應 instance，不會有此問題。
- **CLI 補救**：ovftool 部署時**不要加 `--powerOn`**；部完後用 vCenter API 改 vApp 屬性（等同 Customize template 頁）**在關機狀態設好 IP**，再**單次開機**。本 lab 用 PowerCLI `ReconfigVM` 設 `VAppConfig.Property`（依 numeric key edit）。

## ⚠️ firstboot 絕不可打斷（2026-07-27 實測踩到）
第一次部署我加了 `--powerOn` → VM 用 DHCP 開機（拿不到 IP）→ 我中途 `Stop-VM` 改 IP 再開 → **firstboot 被打斷後卡死**（主控台停在「Firstboot is running」，但 VM CPU 只有 25MHz＝閒置，不是在忙）。
**正確做法**：部署→**關機狀態**設好 Static IP（+ 確認 DNS A/PTR 已存在）→**開機一次讓 firstboot 一氣呵成**（xsmall 2vCPU/8GB + nested vSAN 上要 20–40 分，期間 CPU 應該是高負載；若長時間 25MHz 閒置＝卡住，需重部）。前置 DNS 必須先加好（firstboot / 註冊會用到 FQDN）。

---

## ① VCF Operations Appliance（先裝）
1. vSphere Client（新 vCenter 9.1 .142）→ Deploy OVF Template → 選 `E:\Operations-Appliance-...ova`。
2. 填：
   - **Node Name**：勿含底線等特殊字元（例 `vcf-ops01`）
   - **Deployment Size**：選 size（不影響 disk 大小；lab 選最小 / Extra Small 即可）
   - **Disk Format**：Thin
   - **Destination Network**：SDDC-DPortGroup-VM-Mgmt
   - **Networking**：Domain Name、Domain Search Path、DNS Servers、IP（static IPv4）、Gateway、**NTP**
   - **Time Zone**：所有節點一致
   - FIPS：不勾（除非需要）
3. 開機 → 等 bootstrap → 瀏覽器開 `https://<ops-ip-or-fqdn>/` 初始 wizard：
   - **New Installation**
   - admin 密碼（**≥15 字元**，含大小寫+數字+特殊字元）
   - 憑證（預設或自訂）
   - primary node name
   - NTP
   - Availability Mode（lab 單節點不用）
   - **Start VCF Operations**
4. 起來後：連 vCenter / NSX（Ops 內加 adapter/cloud account），註冊 Broadcom Business Services Console 拿 entitlement。

## ② VCF License Server（後裝）
1. 在 **VCF Operations**：Manage → Licensing → Licenses & Registration → License Servers → **Add License Server** → 複製 **registration key**（step 3 的長字串，綁定本環境、不可重用）。
2. vSphere Client → Deploy OVF Template → 選 `E:\Vcf-License-Server-...ova`（4GB disk / 2 vCPU / 4GB RAM）。
3. 填 OVF properties：
   - **Hostname**：例 `vcf-license01`
   - **VM Domain Name**：⚠️ **只填 domain（`kosten.lab`）不要填 FQDN**（填 FQDN 會變 hostname.domain.domain → 之後授權靜默失敗）
   - Domain Search Path、IP、DNS、Gateway
   - **Registration Key**：貼上步驟 1 的 key
4. 開機 → 等 5–10 分鐘。
5. VCF Operations → **Review License Servers** 確認出現 → 產生 activation code → 指派授權（VCF / vSAN…）→ 下載 license file → Licenses & Registration 套用到 vCenter。

## 常見坑
- License Server VM Domain Name 填成 FQDN → hostname.domain.domain → 授權靜默失敗。
- 用 ESXi host client 部署 → OVF property 沒注入 → 刪掉用 vCenter 重部。
- 時鐘偏移 → 憑證/註冊失敗。
