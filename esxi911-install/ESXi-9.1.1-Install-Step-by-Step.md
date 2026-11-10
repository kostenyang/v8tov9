# ESXi 9.1.1 安裝 Step-by-Step

## 1. 文件說明與規劃值

本文件說明如何在實體伺服器上以 **VMware ESXi 9.1.1（build 25714478）** 原廠 ISO 安裝 ESXi，從開機、安裝精靈、DCUI 管理網路設定，一路做到 ESXi Host Client 的初始設定與安裝後驗證。文中畫面都是實際安裝時擷取的。

- 安裝程式與 DCUI 畫面：在伺服器本機螢幕或 BMC 遠端主控台（iDRAC / iLO / XCC）上操作
- Host Client 畫面：用瀏覽器登入 `https://<主機 FQDN>/ui/` 操作

文件中使用的範例值如下。**實際安裝時請換成客戶的規劃值**，其餘步驟不變。

| 項目 | 範例值 | 說明 |
|---|---|---|
| 安裝媒體 | `VMware-VMvisor-Installer-9.1.1.0.25714478.x86_64.iso` | Broadcom Support Portal 下載的原廠 ISO（699.5 MB） |
| 主機 FQDN | `esx911-demo.home.lab` | 小寫、含網域；DNS 正解與反解都要先建好 |
| 管理 IP / 遮罩 | `10.0.0.88` / `255.255.254.0`（/23） | vmk0 靜態 IP |
| Default Gateway | `10.0.0.1` | |
| DNS Server | `10.0.0.200` | |
| DNS Suffix | `home.lab` | |
| NTP Server | `10.0.1.254` | 與 vCenter / VCF 其他元件使用同一個時間源 |
| VLAN | 無（access port） | trunk port 才需要在 DCUI 填 VLAN ID |
| Datastore 名稱 | `esx911-demo-ds01` | 建在開機碟以外的本機磁碟或 SAN LUN |
| root 密碼 | 另行提供 | 文件中不列出 |

## 2. 安裝前準備

### 硬體與相容性

- 伺服器、CPU、網卡、HBA / RAID 卡都要在 Broadcom Compatibility Guide 上列為支援 ESXi 9.1.1。
- 開機裝置：最小 32 GB，**建議 128 GB 以上的持久性裝置**（M.2 / BOSS 卡 / 本機 SSD）。不建議用 SD 卡或 USB 隨身碟當唯一開機裝置。
- 記憶體：官方最低需求以 9.1 文件為準；要加入 VCF 管理網域的主機實務上遠高於最低需求。
- OEM 伺服器建議使用原廠客製 ISO（Dell / HPE / Lenovo），內含該廠牌的驅動與管理套件。

### BIOS / UEFI 設定

- 開機模式：**UEFI**
- Intel VT-x / AMD-V、VT-d / AMD-Vi（IOMMU）：啟用
- 電源管理：建議設為 OS Controlled（交給 ESXi 管理）
- Secure Boot、TPM 2.0：依客戶安全需求決定；要用 Secure Boot 就要用有簽章的 ISO

### 網路與名稱解析

- 先跟網管確認管理網路的交換器 port 是 **access** 還是 **trunk**；trunk 要知道管理 VLAN ID。
- 在 DNS 上**先建好 A 記錄與 PTR 記錄**，用 `nslookup <FQDN>` 和 `nslookup <IP>` 各驗一次，兩邊要對得起來。
- NTP 來源要與 vCenter / VCF 其他元件一致。

### 安裝媒體掛載方式

- 遠端：iDRAC / iLO / XCC 的 Virtual Media 掛 ISO，從 Virtual CD 開機
- 本地：用 Rufus 等工具把 ISO 寫入 USB 開機碟
- 大量部署：PXE + kickstart（本文未涵蓋）

> 透過 BMC 的 HTML5 遠端主控台操作時，**F11 常被瀏覽器攔截成「全螢幕」**。請改用遠端主控台工具列上的虛擬鍵盤或按鍵巨集送出 F11。

## 3. 從 ISO 開機

1. 掛好 ISO 後重開伺服器，在 POST 畫面進入一次性開機選單（常見按鍵：Dell **F11** Boot Manager、HPE **F11** One-Time Boot、Lenovo **F12**；也可以在 BMC 網頁上直接設定「下次從 Virtual CD 開機」），選擇 Virtual CD / USB 開機。

2. ESXi 開機載入程式出現後有 5 秒倒數，直接按 **Enter** 或等它自動開機。

   ![](img/01-開機載入.png)

   > 這個畫面按 **Shift+O** 可以編輯開機參數，例如指定 kickstart 檔，或用 `systemMediaSize=min|small|default|max` 控制系統分割區（OSDATA）要占多大。開機碟很大、又想把剩餘空間留給 datastore 時會用到。

3. 安裝程式開始載入各個模組，等進度列跑完即可，不需要操作。

   ![](img/02-載入安裝程式.png)

## 4. 安裝精靈

### 4.1 Welcome

1. 出現 Welcome 畫面後按 **Enter** 繼續。

   ![](img/03-Welcome.png)

### 4.2 授權合約（EULA）

1. 閱讀授權合約後按 **F11（Accept and Continue）**。

   ![](img/04-EULA.png)

2. 安裝程式開始掃描可用的儲存裝置，等幾秒即可。

   ![](img/05-Scanning.png)

### 4.3 選擇安裝磁碟

1. 用方向鍵選要安裝 ESXi 的磁碟（開機用的 BOSS / M.2 / RAID 1 虛擬磁碟）。清單會依 Local / Remote 列出裝置名稱、型號與容量。

   ![](img/06-選擇安裝磁碟.png)

   > 清單上有 `*` 的磁碟代表已經有 VMFS 分割區，`#` 代表已被 vSAN 使用。**選到這兩種磁碟會覆蓋上面的資料**，請再三確認。有接 SAN 的主機，建議安裝前先暫停 FC / iSCSI 的 zoning 或拔掉 HBA 線，避免誤裝到 Remote 的 LUN 上。

2. 不確定是哪一顆時，先選起來按 **F1** 看詳細資訊（型號、容量、路徑、是否已有 ESXi、上面有哪些 datastore），確認後按 **Enter** 關掉。

   ![](img/07-磁碟詳細資訊.png)

3. 回到清單後按 **Enter** 選定磁碟。

### 4.4 鍵盤配置

1. 選擇鍵盤配置，台灣一般使用預設的 **US Default**，按 **Enter**。

   ![](img/08-鍵盤配置.png)

### 4.5 設定 root 密碼

1. 輸入 root 密碼，按方向鍵 ↓ 移到 Confirm password 再輸入一次。

   ![](img/09-設定root密碼.png)

2. 兩次一致時下方會顯示「Passwords match.」，按 **Enter** 繼續。

   ![](img/10-root密碼已輸入.png)

   > 預設的密碼原則要求足夠長度並混合大小寫、數字、符號。這台主機之後要給 VCF 用的話，直接設成符合 VCF 密碼規範的密碼，省得之後再改。

### 4.6 系統掃描警告（硬體不在支援清單時才會出現）

輸入密碼後安裝程式會檢查硬體是否符合需求。硬體都在相容性清單內時**不會出現這一節的畫面**，直接進入 4.7「Confirm Install」。

若 CPU 不在 ESXi 9.1.1 的支援清單內（例如較舊世代的伺服器），會出現以下兩個畫面：

1. `CPU_SUPPORT OVERRIDEWARNING`：表示 CPU 不受 ESXi 9.1.1 支援，可以強制安裝但官方不支援（參考 KB 82794）。**正式環境看到這個警告應按 Esc 停止安裝、更換支援的硬體**；只有測試環境才按 **Enter** 繼續。

   ![](img/11-系統掃描警告-CPU.png)

2. 再次確認是否強制安裝（Force Installation）。

   ![](img/12-強制安裝確認-CPU.png)

> 若出現的是其他警告（例如 VT 沒開、NX/XD 沒開），通常是 BIOS 設定問題：按 Esc 取消、進 BIOS 修正後再重新安裝。

### 4.7 確認安裝

1. 最後確認畫面會列出要安裝的目標磁碟，並警告這顆磁碟會被重新分割。確認無誤後按 **F11（Install）**。

   ![](img/13-確認安裝.png)

2. 開始安裝，進度跑到 100% 即完成，一般只需要幾分鐘（透過 BMC Virtual Media 從遠端掛 ISO 時，速度取決於網路頻寬）。

   ![](img/14-安裝進度.png)

### 4.8 安裝完成並重新開機

1. 看到「Installation Complete」後，**先卸載安裝媒體**（BMC 的 Virtual Media 卸載 ISO，或拔掉 USB），再按 **Enter** 重新開機。

   ![](img/15-安裝完成.png)

   > 畫面也提醒：沒有套用授權時，ESXi 會以 **90 天評估模式**運作。

2. 重新開機後畫面標題是「Loading VMware ESXi」（不是「Loading ESXi installer」），代表已經從硬碟開機。

   ![](img/16-重新開機中.png)

## 5. DCUI 設定管理網路

### 5.1 DCUI 主畫面

1. 開機完成後進入 DCUI（Direct Console User Interface）。管理網路預設用 DHCP；網段沒有 DHCP 時會顯示「Waiting for DHCP」與 `DHCP lookup failed` 警告，這是正常的，接下來改成靜態 IP。

   ![](img/17-DCUI主畫面-DHCP.png)

### 5.2 登入

1. 按 **F2（Customize System/View Logs）**，Login Name 預設 `root`，按 ↓ 移到 Password 輸入安裝時設定的密碼，按 **Enter**。

   ![](img/18-DCUI登入.png)

2. 登入後進入 System Customization 選單。

   ![](img/19-System-Customization.png)

### 5.3 Configure Management Network

1. 用方向鍵選 **Configure Management Network**，右側會顯示目前的 hostname 與 IP（此時還是 `localhost` 與 169.254.x.x）。按 **Enter**。

   ![](img/20-選Configure-Management-Network.png)

   > 「Configure Lockdown Mode」是灰色的，方向鍵會跳過它；從 Configure Password 往下按兩次會跑到 Restart Management Network，要留意。

2. 進入管理網路子選單。

   ![](img/21-Management-Network選單.png)

### 5.4 Network Adapters

1. 選 **Network Adapters** 按 Enter，確認管理網路要用哪幾張實體網卡（`[X]` 為已選）。有兩張以上連到管理網段的網卡時，用 **Space** 勾選多張做容錯，按 **Enter** 確定。

   ![](img/22-Network-Adapters.png)

   > 實體機建議按 **D（View Details）** 對照 MAC 與交換器上的接線，確認選到的是接管理網段的那張。

### 5.5 VLAN（選用）

1. 選 **VLAN (optional)** 按 Enter。交換器 port 是 **trunk** 時在這裡填管理 VLAN ID；是 **access** port 就留空，按 Esc 離開。範例環境為 access port，不設定。

   ![](img/23-VLAN.png)

### 5.6 IPv4 Configuration

1. 選 **IPv4 Configuration** 按 Enter，預設是「Use dynamic IPv4 address」（DHCP）。

   ![](img/24-IPv4-預設DHCP.png)

2. 用方向鍵移到 **Set static IPv4 address and network configuration**，按 **Space** 選取，再往下填入 IPv4 Address、Subnet Mask、Default Gateway（欄位內原有的值要先用 Backspace 刪掉），按 **Enter**。

   ![](img/25-IPv4-靜態IP.png)

### 5.7 DNS Configuration

1. 選 **DNS Configuration** 按 Enter，預設是自動取得。

   ![](img/26-DNS-預設.png)

2. 移到 **Use the following DNS server addresses and hostname**，按 **Space** 選取，填入 Primary DNS Server，Hostname 填 **FQDN**（例如 `esx911-demo.home.lab`），按 **Enter**。

   ![](img/27-DNS-靜態與Hostname.png)

### 5.8 Custom DNS Suffixes

1. 選 **Custom DNS Suffixes** 按 Enter，填入搜尋網域（多個用空白或逗號分隔），按 **Enter**。

   ![](img/28-Custom-DNS-Suffixes.png)

### 5.9 套用變更

1. 按 **Esc** 離開管理網路子選單，會詢問是否套用變更並重啟管理網路，按 **Y**。

   ![](img/29-套用變更確認.png)

   > 只改 IPv4 / DNS 不會重開機；如果有啟用或停用 IPv6，則會要求重開主機。

2. 回到 System Customization，右側已顯示新的 hostname 與 IPv4 位址。

   ![](img/30-管理網路設定結果.png)

### 5.10 Test Management Network

1. 選 **Test Management Network** 按 Enter，預設會 ping Gateway、DNS，並解析自己的 FQDN。按 **Enter** 開始測試。

   ![](img/31-Test-Management-Network.png)

2. 三項都要是 **OK**。任何一項失敗都先排除再往下做。

   ![](img/32-Test結果.png)

   > Gateway 就 ping 不通時，最常見的原因是**交換器 port 的 VLAN 設定與 DCUI 不一致**（交換器是 trunk 但 DCUI 沒填 VLAN ID，或交換器是 access 卻填了 VLAN ID），其次是 Network Adapters 選到沒接線 / 接錯交換器的網卡。請網管確認 port 設定，並用 5.4 節的 View Details 對照 MAC。

### 5.11 啟用 SSH（選用）

1. 選 **Troubleshooting Options** 按 Enter。

   ![](img/33-Troubleshooting-Options.png)

2. 選 **Enable SSH** 按 Enter，右側變成「SSH is Enabled」、選項變成「Disable SSH」即完成。要加入 VCF（commission / bring-up）的主機需要開 SSH；一般環境用完建議關閉。

   ![](img/34-Enable-SSH.png)

### 5.12 登出

1. 按 **Esc** 兩次登出，回到 DCUI 主畫面，確認管理網址已顯示 FQDN 與 `(STATIC)` 的 IP。

   ![](img/35-DCUI主畫面-靜態IP.png)

## 6. Host Client 初始設定

### 6.1 登入 Host Client

1. 用瀏覽器開 `https://<主機 FQDN>/ui/`（第一次連線會有自簽憑證警告，確認是自己的主機後繼續）。

   ![](img/36-HostClient登入頁.png)

2. 輸入 `root` 與密碼，按 **LOG IN**。

   ![](img/37-HostClient輸入帳密.png)

3. 第一次登入會詢問是否加入 CEIP（Customer Experience Improvement Program），依客戶政策決定是否勾選，按 **OK**。範例中不加入。

   ![](img/38-CEIP.png)

4. 進入主機 Summary 頁。ESXi 9.1 的 Host Client 已改用新版介面，左側是 Host / Virtual Machines / Storage / Networking，主機頁籤為 Summary / Monitor / Configure / Permissions。此時 Issues and Alarms 會顯示 SSH 已啟用、尚無 datastore、授權 90 天到期等提示。

   ![](img/39-Host-Summary.png)

### 6.2 設定 NTP

1. 點 **Configure → System → Time Configuration**，預設 Time Synchronization 是 **Manual**、NTP Client 是 Disabled。點 Network Time Protocol 右側的 **EDIT...**。

   ![](img/40-Time-Configuration-預設.png)

2. 開啟 Edit Network Time Protocol 對話框。

   ![](img/41-Edit-NTP-預設.png)

3. 勾選 **Enable**，在 NTP Servers 填入 NTP 伺服器（多台用逗號分隔），按 **OK**。

   ![](img/42-Edit-NTP-已填.png)

4. 確認 Time Synchronization 變成 **Network Time Protocol**，NTP Client = Enabled、NTP Service Status = Running。

   ![](img/43-Time-Configuration-NTP.png)

### 6.3 設定 NTP 服務的啟動原則

> **常見坑**：用上一步啟用 NTP 後，NTP Daemon 雖然在跑，但啟動原則仍是「Start and stop manually」——**主機重開機後 NTP 不會自己起來**。一定要接著做這一步。

1. 點 **Configure → System → Services**，可以看到 SSH 為 Running、NTP Daemon 為 Running 但啟動原則是 Start and stop manually。

   ![](img/44-Services.png)

2. 選 **NTP Daemon**，點 **EDIT STARTUP POLICY...**，選 **Start and stop with host**，按 **OK**。

   ![](img/46-NTP啟動原則-隨主機.png)

3. 確認 NTP Daemon 的 Startup Policy 已變成 **Start and stop with host**。

   ![](img/47-Services-NTP已設定.png)

### 6.4 確認 DNS 與網路

1. 點 **Configure → System → TCP/IP Configuration**，確認 Default 堆疊的 IPv4 Gateway 與 Preferred DNS server 正確。

   ![](img/48-TCPIP-DNS.png)

2. 點左側 **Networking → Port Groups**，預設有 vSwitch0 上的 **Management Network** 與 **VM Network** 兩個 port group。

   ![](img/49-Networking.png)

3. 切到 **VMKernel Adapters** 頁籤，確認 vmk0 的 IP 與 TCP/IP 堆疊。

   ![](img/50-VMkernel-Adapters.png)

### 6.5 建立 VMFS Datastore

> 開機碟會先被系統分割區占用：BOOTBANK1 / BOOTBANK2（各約 4 GB）加上 OSDATA。開機碟不大時（例如 BOSS / M.2 的小容量開機碟）整顆都會被用掉，安裝程式**不會自動建立 datastore1**，Summary 頁就會顯示「No datastores have been configured」。開機碟扣掉系統分割區還有剩餘空間時，安裝程式才會自動建立 datastore1。放 VM 的 datastore 建議建在開機碟以外的本機磁碟或 SAN LUN 上，步驟如下。

1. 點 **Storage → Storage Devices → RESCAN STORAGE**，在對話框按 **OK** 重新掃描（新插的磁碟、剛完成 zoning / mapping 的 SAN LUN 都需要先掃描）。

   ![](img/51-Rescan-Storage.png)

2. 確認清單中出現要用來建 datastore 的磁碟（範例中為 100 GB 的那一顆）。

   ![](img/52-Storage-Devices.png)

3. 切到 **Datastores** 頁籤，點 **NEW DATASTORE...**，類型選 **VMFS**，按 **NEXT**。

   ![](img/53-New-Datastore-類型.png)

4. 輸入 datastore 名稱，選擇目標磁碟（注意不要選到開機碟），按 **NEXT**。

   ![](img/54-New-Datastore-名稱與磁碟.png)

5. VMFS 版本選 **VMFS 6**，按 **NEXT**。

   ![](img/55-New-Datastore-VMFS版本.png)

6. Partition Configuration 選 **Use all available partitions**，其他維持預設（Block size 1 MB、Space Reclamation Priority Low），按 **NEXT**。

   ![](img/56-New-Datastore-分割區.png)

7. 確認設定後按 **FINISH**。

   ![](img/57-New-Datastore-確認.png)

8. Datastores 清單出現新的 VMFS 6 datastore。

   ![](img/58-Datastores結果.png)

9. 回到主機 Summary，「No datastores」的提示已消失，Storage 容量也已顯示。

   ![](img/59-Host-Summary-完成.png)

### 6.6 重新產生主機憑證（要加入 VCF / vCenter 前必做）

ESXi 的自簽憑證是在**安裝當下**產生的，那時 hostname 還是 `localhost`，所以憑證的 CN / SAN 是 `localhost.localdomain`。之後在 DCUI 改了 FQDN，憑證**不會**自動更新。VCF Installer / SDDC Manager 會驗主機憑證與 FQDN 是否一致，不一致會擋在驗證階段。

1. 點 **Configure → System → Certificate**，可以看到 Subject 的 CN 仍是 `localhost.localdomain`。

   ![](img/60-Certificate-改前.png)

2. 用 SSH 登入主機，重新產生憑證並重啟相關服務（ESXi 9 對外 443 的 rhttpproxy 是 Envoy，**一定要重啟它**，否則對外送出的還是舊憑證）：

   ```
   [root@esx911-demo:~] /sbin/generate-certificates
   [root@esx911-demo:~] /etc/init.d/hostd restart
   hostd stopped.
   hostd started.
   [root@esx911-demo:~] /etc/init.d/vpxa restart
   vpxa stopped.
   vpxa started.
   [root@esx911-demo:~] /etc/init.d/rhttpproxy restart
   Envoy proxy Discovery Service stopped.
   Envoy proxy Discovery Service started
   [root@esx911-demo:~] openssl x509 -in /etc/vmware/ssl/rui.crt -noout -subject -ext subjectAltName
   subject=... CN=esx911-demo.home.lab ...
   X509v3 Subject Alternative Name:
       DNS:esx911-demo.home.lab
   ```

   > 只重啟 hostd / vpxa 時，`rui.crt` 檔案已經更新，但從 443 抓到的仍是舊憑證；重啟 rhttpproxy 後才換成新的。也可以直接重開機。

3. 重新登入 Host Client（hostd 重啟會讓原本的 session 失效），Certificate 頁的 CN 已是主機 FQDN。

   ![](img/61-Certificate-改後.png)

## 7. 安裝後驗證

用 SSH 登入主機執行以下指令，逐項確認（以下為範例主機的實際輸出）。

### 版本

```
[root@esx911-demo:~] esxcli system version get
   Product: VMware ESXi
   Version: 9.1.1
   Build: Releasebuild-25714478
   Update: 1
   Maintenance: 1
   Patch: 0
```

> 要加入既有 VCF 環境時，ESXi build 必須與該 VCF 版本的 BOM 一致（9.1.1 = 25714478）。

### 管理網路、Hostname、DNS

```
[root@esx911-demo:~] esxcli network ip interface ipv4 get
Name  IPv4 Address  IPv4 Netmask   IPv4 Broadcast  Address Type  Gateway   DHCP DNS
----  ------------  -------------  --------------  ------------  --------  --------
vmk0  10.0.0.88     255.255.254.0  10.0.1.255      STATIC        10.0.0.1     false

[root@esx911-demo:~] esxcli system hostname get
   Domain Name: home.lab
   Fully Qualified Domain Name: esx911-demo.home.lab
   Host Name: esx911-demo

[root@esx911-demo:~] esxcli network ip dns server list
   DNSServers: 10.0.0.200
```

### NTP 同步狀態

```
[root@esx911-demo:~] esxcli system ntp get
   Enabled: true
   Loglevel: warning
   PID: 264176
   Runtime Seconds: 638
   Servers: 10.0.1.254
   Service Providing Kernel Time: Network Time Protocol
   Time Service Enabled: true
   Time Synchronized: true
```

`Time Synchronized: true` 才代表已經真的對到時。

### 儲存

```
[root@esx911-demo:~] esxcli storage filesystem list
Volume Name                                  Type    Size          Free
-------------------------------------------  ------  ------------  ------------
esx911-demo-ds01                             VMFS-6  107105746944  105590554624
OSDATA-6ae06a2d-3d0de9f4-1679-005056bf44bf   VMFSOS   59861106688   57913901056
BOOTBANK1                                    vfat     4293591040    3939893248
BOOTBANK2                                    vfat     4293591040    4293525504
```

（輸出已省略 Mount Point / UUID 欄位）

### 驗收檢查表

| # | 檢查項目 | 預期結果 | 結果 |
|---|---|---|---|
| 1 | ESXi 版本 / build | 9.1.1 / 25714478 | ✅ |
| 2 | vmk0 IP 類型 | STATIC，IP / 遮罩 / Gateway 正確 | ✅ |
| 3 | FQDN | 與 DNS A 記錄一致、全小寫 | ✅ |
| 4 | DNS 正反解 | `nslookup FQDN` 與 `nslookup IP` 互相對應 | ✅ |
| 5 | Test Management Network | Gateway / DNS / Hostname 三項 OK | ✅ |
| 6 | NTP | Time Synchronized = true | ✅ |
| 7 | NTP Daemon 啟動原則 | Start and stop with host | ✅ |
| 8 | 主機憑證 CN / SAN | = 主機 FQDN | ✅ |
| 9 | SSH | 依需求（VCF 納管需開啟） | ✅ |
| 10 | Datastore | 依需求建立（VMFS 6） | ✅ |

## 8. 常見問題與注意事項

| 現象 | 原因 | 處理方式 |
|---|---|---|
| 安裝時出現 `CPU_SUPPORT OVERRIDEWARNING` | CPU 不在 ESXi 9.1.1 支援清單內 | 正式環境更換支援的硬體；只有測試環境才強制安裝（KB 82794） |
| BMC 遠端主控台按 F11 沒反應 | 瀏覽器把 F11 當成全螢幕 | 用主控台工具列的虛擬鍵盤 / 按鍵巨集送 F11 |
| DCUI 顯示 `DHCP lookup failed` | 管理網段沒有 DHCP | 正常現象，依第 5 章設定靜態 IP |
| 設好 IP 後 ping 不通、Test Management Network 失敗 | 交換器 port VLAN 不對、網卡選錯、Gateway 打錯 | 先確認 access / trunk 與 VLAN ID，再用 Network Adapters 的 View Details 對 MAC |
| 安裝後沒有 datastore1 | 開機碟空間全被系統分割區用掉 | 另建 datastore（6.5 節），或安裝時用 `systemMediaSize` 開機參數縮小 OSDATA |
| 重開機後時間又不準 | NTP Daemon 啟動原則是 manual | 改成 Start and stop with host（6.3 節） |
| VCF 驗證主機時報憑證 / 主機名稱不符 | 憑證仍是安裝時的 `localhost.localdomain` | 重新產生憑證並重啟 rhttpproxy（6.6 節） |
| 90 天後無法開機 VM | 評估授權到期 | VCF 9 環境的授權在主機加入 vCenter 後，由 vCenter / VCF Operations 套用 |

### 後續步驟

- 加入 vCenter：在 vSphere Client 用 **Add Host** 加入，主機名稱請用 FQDN。
- 加入 VCF：在 VCF Operations / SDDC Manager 進行主機納管（commission）前，確認上表 1–9 項全部通過。
