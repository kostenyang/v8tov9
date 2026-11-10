# ESXi 9.1.1 Installation Step-by-Step

## 1. About This Document and Planning Values

This document describes how to install **VMware ESXi 9.1.1 (build 25714478)** on a physical server from the original ISO — from booting the installer, through the installation wizard and DCUI management network configuration, to the initial configuration in the ESXi Host Client and post-installation verification. All screenshots were captured during an actual installation.

- Installer and DCUI screens: operated on the server's local console or the BMC remote console (iDRAC / iLO / XCC)
- Host Client screens: operated in a web browser at `https://<host FQDN>/ui/`

The example values used in this document are listed below. **Replace them with the customer's planned values** for an actual installation; all other steps stay the same.

| Item | Example value | Notes |
|---|---|---|
| Installation media | `VMware-VMvisor-Installer-9.1.1.0.25714478.x86_64.iso` | Original ISO downloaded from the Broadcom Support Portal (699.5 MB) |
| Host FQDN | `esx911-demo.home.lab` | Lowercase, including the domain; create both forward and reverse DNS records in advance |
| Management IP / mask | `10.0.0.88` / `255.255.254.0` (/23) | Static IP for vmk0 |
| Default gateway | `10.0.0.1` | |
| DNS server | `10.0.0.200` | |
| DNS suffix | `home.lab` | |
| NTP server | `10.0.1.254` | Same time source as vCenter / other VCF components |
| VLAN | None (access port) | A VLAN ID is only needed in the DCUI for a trunk port |
| Datastore name | `esx911-demo-ds01` | Created on a local disk or SAN LUN other than the boot device |
| root password | Provided separately | Not listed in this document |

## 2. Preparation

### Hardware and compatibility

- The server, CPU, NICs, and HBA / RAID controllers must be listed as supported for ESXi 9.1.1 in the Broadcom Compatibility Guide.
- Boot device: 32 GB minimum; **a persistent device of 128 GB or larger is recommended** (M.2 / BOSS card / local SSD). Using an SD card or USB flash drive as the only boot device is not recommended.
- Memory: refer to the 9.1 documentation for the official minimum; hosts for a VCF management domain need far more than the minimum in practice.
- For OEM servers, use the vendor's custom ISO (Dell / HPE / Lenovo), which includes the vendor's drivers and management tools.

### BIOS / UEFI settings

- Boot mode: **UEFI**
- Intel VT-x / AMD-V and VT-d / AMD-Vi (IOMMU): enabled
- Power management: OS Controlled is recommended (lets ESXi manage power)
- Secure Boot and TPM 2.0: according to the customer's security requirements; Secure Boot requires a signed ISO

### Network and name resolution

- Confirm with the network team whether the management switch port is an **access** or **trunk** port; for a trunk port, obtain the management VLAN ID.
- **Create the A and PTR records in DNS first**, and check both `nslookup <FQDN>` and `nslookup <IP>` — the results must match each other.
- The NTP source must be the same as for vCenter / other VCF components.

### Mounting the installation media

- Remote: mount the ISO with the Virtual Media feature of iDRAC / iLO / XCC and boot from Virtual CD
- Local: write the ISO to a bootable USB drive with a tool such as Rufus
- Mass deployment: PXE + kickstart (not covered in this document)

> When using the HTML5 remote console of a BMC, **F11 is often captured by the browser as "full screen"**. Send F11 using the virtual keyboard or key macros on the remote console toolbar instead.

## 3. Booting from the ISO

1. After mounting the ISO, reboot the server and open the one-time boot menu during POST (common keys: Dell **F11** Boot Manager, HPE **F11** One-Time Boot, Lenovo **F12**; you can also set "next boot from Virtual CD" in the BMC web interface). Select Virtual CD / USB.

2. When the ESXi boot loader appears, there is a 5-second countdown. Press **Enter** or let it boot automatically.

   ![Boot loader countdown](img/01-開機載入.png)

   > Press **Shift+O** on this screen to edit the boot options — for example, to specify a kickstart file, or to use `systemMediaSize=min|small|default|max` to control how large the system partition (OSDATA) will be. This is useful when the boot device is large and you want to keep the remaining space for a datastore.

3. The installer loads its modules. Wait for the progress bar to finish; no action is needed.

   ![Loading the ESXi installer](img/02-載入安裝程式.png)

## 4. Installation Wizard

### 4.1 Welcome

1. When the Welcome screen appears, press **Enter** to continue.

   ![Welcome screen](img/03-Welcome.png)

### 4.2 End User License Agreement (EULA)

1. Read the license agreement and press **F11 (Accept and Continue)**.

   ![EULA](img/04-EULA.png)

2. The installer scans for available storage devices. Wait a few seconds.

   ![Scanning for devices](img/05-Scanning.png)

### 4.3 Select the installation disk

1. Use the arrow keys to select the disk to install ESXi on (the BOSS / M.2 / RAID 1 virtual disk used for booting). The list shows each device's name, model, and capacity, grouped by Local / Remote.

   ![Select a disk](img/06-選擇安裝磁碟.png)

   > A disk marked `*` already contains a VMFS partition, and a disk marked `#` is claimed by vSAN. **Selecting either type overwrites its data** — double-check before continuing. On hosts connected to a SAN, consider suspending the FC / iSCSI zoning or unplugging the HBA cables before installing, so that ESXi is not accidentally installed on a remote LUN.

2. If you are not sure which disk is which, highlight it and press **F1** to view its details (model, capacity, path, whether ESXi is already installed, and which datastores it holds). Press **Enter** to close the details.

   ![Disk details (F1)](img/07-磁碟詳細資訊.png)

3. Back in the list, press **Enter** to select the disk.

### 4.4 Keyboard layout

1. Select the keyboard layout (usually the default **US Default**) and press **Enter**.

   ![Keyboard layout](img/08-鍵盤配置.png)

### 4.5 Set the root password

1. Enter the root password, press the ↓ key to move to Confirm password, and enter it again.

   ![Enter a root password](img/09-設定root密碼.png)

2. When both entries match, "Passwords match." appears below. Press **Enter** to continue.

   ![Passwords match](img/10-root密碼已輸入.png)

   > The default password policy requires sufficient length and a mix of uppercase, lowercase, digits, and symbols. If the host will be used for VCF, set a password that already meets the VCF password requirements to avoid changing it later.

### 4.6 System scan warnings (only on hardware that is not on the compatibility list)

After the password is entered, the installer checks whether the hardware meets the requirements. If all hardware is on the compatibility list, **the screens in this section do not appear** and the installer goes straight to 4.7 "Confirm Install".

If the CPU is not supported by ESXi 9.1.1 (for example, on an older server generation), the following two screens appear:

1. `CPU_SUPPORT OVERRIDEWARNING`: the CPU is not supported by ESXi 9.1.1. You can force the installation, but it is not officially supported (see KB 82794). **In a production environment, press Esc to stop the installation and replace the hardware with supported hardware**; press **Enter** to continue only in a test environment.

   ![CPU support warning](img/11-系統掃描警告-CPU.png)

2. Confirm again whether to force the installation (Force Installation).

   ![Force installation confirmation](img/12-強制安裝確認-CPU.png)

> If a different warning appears (for example, VT or NX/XD is not enabled), it is usually a BIOS setting issue: press Esc to cancel, fix the setting in the BIOS, and run the installation again.

### 4.7 Confirm the installation

1. The final confirmation screen shows the target disk and warns that the disk will be repartitioned. If everything is correct, press **F11 (Install)**.

   ![Confirm Install](img/13-確認安裝.png)

2. The installation starts and is complete when the progress reaches 100%. It normally takes only a few minutes (when the ISO is mounted remotely through BMC Virtual Media, the speed depends on the network bandwidth).

   ![Installation progress](img/14-安裝進度.png)

### 4.8 Installation complete and reboot

1. When "Installation Complete" appears, **unmount the installation media first** (unmount the ISO from BMC Virtual Media, or remove the USB drive), then press **Enter** to reboot.

   ![Installation Complete](img/15-安裝完成.png)

   > The screen also notes that without a license, ESXi runs in **90-day evaluation mode**.

2. After the reboot, the screen title reads "Loading VMware ESXi" (not "Loading ESXi installer"), which means the host is booting from its disk.

   ![Booting ESXi from disk](img/16-重新開機中.png)

## 5. Configuring the Management Network in the DCUI

### 5.1 DCUI main screen

1. When the boot finishes, the DCUI (Direct Console User Interface) appears. The management network uses DHCP by default; if the network has no DHCP server, "Waiting for DHCP" and a `DHCP lookup failed` warning are shown. This is expected — the next steps configure a static IP.

   ![DCUI main screen (DHCP)](img/17-DCUI主畫面-DHCP.png)

### 5.2 Log in

1. Press **F2 (Customize System/View Logs)**. Login Name defaults to `root`; press ↓ to move to Password, enter the password set during installation, and press **Enter**.

   ![DCUI login](img/18-DCUI登入.png)

2. After logging in, the System Customization menu appears.

   ![System Customization](img/19-System-Customization.png)

### 5.3 Configure Management Network

1. Use the arrow keys to select **Configure Management Network**. The right pane shows the current hostname and IP (still `localhost` and 169.254.x.x at this point). Press **Enter**.

   ![Select Configure Management Network](img/20-選Configure-Management-Network.png)

   > "Configure Lockdown Mode" is grayed out and skipped by the arrow keys — pressing ↓ twice from Configure Password lands on Restart Management Network, so watch the highlight.

2. The management network submenu opens.

   ![Configure Management Network menu](img/21-Management-Network選單.png)

### 5.4 Network Adapters

1. Select **Network Adapters** and press Enter to confirm which physical NICs the management network uses (`[X]` means selected). If two or more NICs are connected to the management network, select them with **Space** for redundancy, then press **Enter**.

   ![Network Adapters](img/22-Network-Adapters.png)

   > On a physical server, press **D (View Details)** and compare the MAC address with the switch cabling to make sure the selected NIC is the one connected to the management network.

### 5.5 VLAN (optional)

1. Select **VLAN (optional)** and press Enter. If the switch port is a **trunk** port, enter the management VLAN ID here; for an **access** port, leave it empty and press Esc. The example environment uses an access port, so no VLAN is set.

   ![VLAN (optional)](img/23-VLAN.png)

### 5.6 IPv4 Configuration

1. Select **IPv4 Configuration** and press Enter. The default is "Use dynamic IPv4 address" (DHCP).

   ![IPv4 Configuration (default DHCP)](img/24-IPv4-預設DHCP.png)

2. Use the arrow keys to move to **Set static IPv4 address and network configuration**, press **Space** to select it, then fill in IPv4 Address, Subnet Mask, and Default Gateway (delete the existing values in each field with Backspace first). Press **Enter**.

   ![Static IPv4 configuration](img/25-IPv4-靜態IP.png)

### 5.7 DNS Configuration

1. Select **DNS Configuration** and press Enter. The default is to obtain the settings automatically.

   ![DNS Configuration (default)](img/26-DNS-預設.png)

2. Move to **Use the following DNS server addresses and hostname**, press **Space** to select it, enter the Primary DNS Server, enter the **FQDN** as the Hostname (for example `esx911-demo.home.lab`), and press **Enter**.

   ![Static DNS and hostname](img/27-DNS-靜態與Hostname.png)

### 5.8 Custom DNS Suffixes

1. Select **Custom DNS Suffixes** and press Enter. Enter the search domain(s) (separate multiple entries with spaces or commas) and press **Enter**.

   ![Custom DNS Suffixes](img/28-Custom-DNS-Suffixes.png)

### 5.9 Apply the changes

1. Press **Esc** to leave the management network submenu. When asked whether to apply the changes and restart the management network, press **Y**.

   ![Apply changes and restart management network](img/29-套用變更確認.png)

   > Changing only IPv4 / DNS does not require a reboot; enabling or disabling IPv6 does require a host reboot.

2. Back in System Customization, the right pane shows the new hostname and IPv4 address.

   ![Management network after configuration](img/30-管理網路設定結果.png)

### 5.10 Test Management Network

1. Select **Test Management Network** and press Enter. By default it pings the gateway and DNS servers and resolves the host's own FQDN. Press **Enter** to run the test.

   ![Test Management Network](img/31-Test-Management-Network.png)

2. All three items must show **OK**. If any item fails, fix it before continuing.

   ![Test results](img/32-Test結果.png)

   > If even the gateway cannot be pinged, the most common cause is that **the switch port VLAN configuration does not match the DCUI** (the switch port is a trunk but no VLAN ID is set in the DCUI, or the port is an access port but a VLAN ID is set), followed by a selected NIC that is not cabled or is connected to the wrong switch. Have the network team check the port configuration, and compare MAC addresses using View Details in section 5.4.

### 5.11 Enable SSH (optional)

1. Select **Troubleshooting Options** and press Enter.

   ![Troubleshooting Options](img/33-Troubleshooting-Options.png)

2. Select **Enable SSH** and press Enter. When the right pane shows "SSH is Enabled" and the option changes to "Disable SSH", it is done. Hosts that will be added to VCF (commission / bring-up) need SSH enabled; in other environments, disabling it after use is recommended.

   ![SSH enabled](img/34-Enable-SSH.png)

### 5.12 Log out

1. Press **Esc** twice to log out and return to the DCUI main screen. Confirm that the management URLs now show the FQDN and the IP marked `(STATIC)`.

   ![DCUI main screen (static IP)](img/35-DCUI主畫面-靜態IP.png)

## 6. Initial Configuration in the Host Client

### 6.1 Log in to the Host Client

1. Open `https://<host FQDN>/ui/` in a browser (the first connection shows a self-signed certificate warning; continue after confirming it is your host).

   ![Host Client login page](img/36-HostClient登入頁.png)

2. Enter `root` and the password, then click **LOG IN**.

   ![Entering the credentials](img/37-HostClient輸入帳密.png)

3. On the first login, you are asked whether to join the CEIP (Customer Experience Improvement Program). Decide according to the customer's policy and click **OK**. The example does not join.

   ![CEIP](img/38-CEIP.png)

4. The host Summary page opens. The ESXi 9.1 Host Client uses a new interface: the left pane shows Host / Virtual Machines / Storage / Networking, and the host tabs are Summary / Monitor / Configure / Permissions. At this point, Issues and Alarms shows that SSH is enabled, no datastore exists yet, and the license expires in 90 days.

   ![Host Summary](img/39-Host-Summary.png)

### 6.2 Configure NTP

1. Click **Configure → System → Time Configuration**. By default, Time Synchronization is **Manual** and the NTP Client is Disabled. Click **EDIT...** next to Network Time Protocol.

   ![Time Configuration (default)](img/40-Time-Configuration-預設.png)

2. The Edit Network Time Protocol dialog opens.

   ![Edit Network Time Protocol](img/41-Edit-NTP-預設.png)

3. Select **Enable**, enter the NTP server(s) in NTP Servers (separate multiple servers with commas), and click **OK**.

   ![NTP server entered](img/42-Edit-NTP-已填.png)

4. Confirm that Time Synchronization is now **Network Time Protocol**, with NTP Client = Enabled and NTP Service Status = Running.

   ![Time Configuration (NTP)](img/43-Time-Configuration-NTP.png)

### 6.3 Set the startup policy of the NTP service

> **Common pitfall**: after enabling NTP in the previous step, the NTP Daemon is running but its startup policy is still "Start and stop manually" — **NTP does not start automatically after the host reboots**. Always do this step as well.

1. Click **Configure → System → Services**. SSH is Running, and the NTP Daemon is Running but its startup policy is Start and stop manually.

   ![Services list](img/44-Services.png)

2. Select **NTP Daemon**, click **EDIT STARTUP POLICY...**, select **Start and stop with host**, and click **OK**.

   ![Edit Startup Policy: Start and stop with host](img/46-NTP啟動原則-隨主機.png)

3. Confirm that the Startup Policy of the NTP Daemon is now **Start and stop with host**.

   ![NTP Daemon startup policy updated](img/47-Services-NTP已設定.png)

### 6.4 Verify DNS and networking

1. Click **Configure → System → TCP/IP Configuration** and confirm that the IPv4 gateway and preferred DNS server of the Default stack are correct.

   ![TCP/IP Configuration](img/48-TCPIP-DNS.png)

2. Click **Networking → Port Groups** in the left pane. By default, vSwitch0 has two port groups: **Management Network** and **VM Network**.

   ![Port Groups](img/49-Networking.png)

3. Switch to the **VMKernel Adapters** tab and confirm the IP and TCP/IP stack of vmk0.

   ![VMkernel Adapters](img/50-VMkernel-Adapters.png)

### 6.5 Create a VMFS datastore

> The boot device is first used by the system partitions: BOOTBANK1 / BOOTBANK2 (about 4 GB each) plus OSDATA. On a small boot device (for example, a small-capacity BOSS / M.2 boot device), the entire device is consumed and the installer **does not create datastore1 automatically**, so the Summary page shows "No datastores have been configured". The installer creates datastore1 only when space remains after the system partitions. A datastore for virtual machines should be created on a local disk or SAN LUN other than the boot device, as follows.

1. Click **Storage → Storage Devices → RESCAN STORAGE** and click **OK** in the dialog to rescan (newly inserted disks and SAN LUNs that were just zoned / mapped need a rescan first).

   ![Rescan Storage](img/51-Rescan-Storage.png)

2. Confirm that the disk for the datastore appears in the list (the 100 GB disk in the example).

   ![Storage Devices](img/52-Storage-Devices.png)

3. Switch to the **Datastores** tab, click **NEW DATASTORE...**, select **VMFS** as the type, and click **NEXT**.

   ![New Datastore: type](img/53-New-Datastore-類型.png)

4. Enter the datastore name, select the target disk (make sure not to select the boot device), and click **NEXT**.

   ![New Datastore: name and device](img/54-New-Datastore-名稱與磁碟.png)

5. Select **VMFS 6** as the VMFS version and click **NEXT**.

   ![New Datastore: VMFS version](img/55-New-Datastore-VMFS版本.png)

6. For Partition Configuration, select **Use all available partitions**, keep the other defaults (block size 1 MB, Space Reclamation Priority Low), and click **NEXT**.

   ![New Datastore: partition configuration](img/56-New-Datastore-分割區.png)

7. Review the settings and click **FINISH**.

   ![New Datastore: ready to complete](img/57-New-Datastore-確認.png)

8. The new VMFS 6 datastore appears in the Datastores list.

   ![Datastores list](img/58-Datastores結果.png)

9. Back on the host Summary page, the "No datastores" message is gone and the storage capacity is shown.

   ![Host Summary after configuration](img/59-Host-Summary-完成.png)

### 6.6 Regenerate the host certificate (required before adding the host to VCF / vCenter)

The ESXi self-signed certificate is generated **at installation time**, when the hostname is still `localhost`, so its CN / SAN is `localhost.localdomain`. Changing the FQDN in the DCUI afterwards does **not** update the certificate. VCF Installer / SDDC Manager checks that the host certificate matches the FQDN and fails validation if it does not.

1. Click **Configure → System → Certificate**. The CN in the Subject is still `localhost.localdomain`.

   ![Certificate before regeneration](img/60-Certificate-改前.png)

2. Log in to the host over SSH, regenerate the certificate, and restart the related services (on ESXi 9 the rhttpproxy that serves port 443 is Envoy — **it must be restarted**, otherwise the old certificate is still presented):

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

   > If only hostd / vpxa are restarted, `rui.crt` is already updated but port 443 still presents the old certificate; it changes only after rhttpproxy is restarted. Rebooting the host also works.

3. Log in to the Host Client again (restarting hostd invalidates the existing session). The CN on the Certificate page is now the host FQDN.

   ![Certificate after regeneration](img/61-Certificate-改後.png)

## 7. Post-Installation Verification

Log in to the host over SSH and run the following commands to check each item (the output below is from the example host).

### Version

```
[root@esx911-demo:~] esxcli system version get
   Product: VMware ESXi
   Version: 9.1.1
   Build: Releasebuild-25714478
   Update: 1
   Maintenance: 1
   Patch: 0
```

> When adding the host to an existing VCF environment, the ESXi build must match the BOM of that VCF version (9.1.1 = 25714478).

### Management network, hostname, DNS

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

### NTP synchronization

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

Only `Time Synchronized: true` means the clock is actually synchronized.

### Storage

```
[root@esx911-demo:~] esxcli storage filesystem list
Volume Name                                  Type    Size          Free
-------------------------------------------  ------  ------------  ------------
esx911-demo-ds01                             VMFS-6  107105746944  105590554624
OSDATA-6ae06a2d-3d0de9f4-1679-005056bf44bf   VMFSOS   59861106688   57913901056
BOOTBANK1                                    vfat     4293591040    3939893248
BOOTBANK2                                    vfat     4293591040    4293525504
```

(The Mount Point / UUID columns are omitted.)

### Acceptance checklist

| # | Check | Expected result | Result |
|---|---|---|---|
| 1 | ESXi version / build | 9.1.1 / 25714478 | ✅ |
| 2 | vmk0 address type | STATIC; IP / mask / gateway correct | ✅ |
| 3 | FQDN | Matches the DNS A record; all lowercase | ✅ |
| 4 | Forward / reverse DNS | `nslookup FQDN` and `nslookup IP` match each other | ✅ |
| 5 | Test Management Network | Gateway / DNS / hostname all OK | ✅ |
| 6 | NTP | Time Synchronized = true | ✅ |
| 7 | NTP Daemon startup policy | Start and stop with host | ✅ |
| 8 | Host certificate CN / SAN | = host FQDN | ✅ |
| 9 | SSH | As required (needed for VCF commissioning) | ✅ |
| 10 | Datastore | Created as required (VMFS 6) | ✅ |

## 8. Troubleshooting and Notes

| Symptom | Cause | Resolution |
|---|---|---|
| `CPU_SUPPORT OVERRIDEWARNING` during installation | The CPU is not supported by ESXi 9.1.1 | Replace with supported hardware in production; force the installation only in a test environment (KB 82794) |
| F11 does nothing in the BMC remote console | The browser treats F11 as full screen | Send F11 with the console's virtual keyboard / key macros |
| The DCUI shows `DHCP lookup failed` | No DHCP on the management network | Expected; configure a static IP as in chapter 5 |
| Ping fails / Test Management Network fails after setting the IP | Wrong switch port VLAN, wrong NIC selected, or wrong gateway | Check access / trunk and the VLAN ID first, then compare MAC addresses with View Details in Network Adapters |
| No datastore1 after installation | The boot device is fully used by the system partitions | Create a datastore (section 6.5), or reduce OSDATA with the `systemMediaSize` boot option during installation |
| The time drifts again after a reboot | The NTP Daemon startup policy is manual | Change it to Start and stop with host (section 6.3) |
| VCF host validation reports a certificate / hostname mismatch | The certificate is still the installation-time `localhost.localdomain` | Regenerate the certificate and restart rhttpproxy (section 6.6) |
| VMs cannot be powered on after 90 days | The evaluation license has expired | In a VCF 9 environment, the license is applied by vCenter / VCF Operations after the host is added to vCenter |

### Next steps

- Add to vCenter: use **Add Host** in the vSphere Client, with the FQDN as the host name.
- Add to VCF: before commissioning the host in VCF Operations / SDDC Manager, make sure items 1–9 in the checklist above all pass.
