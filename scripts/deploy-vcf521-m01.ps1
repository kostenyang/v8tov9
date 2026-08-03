# ============================================================================
#  deploy-vcf521-m01.ps1
#  VCF 5.2.1 Management Domain — Nested Lab 自動部署 (Phase 1)
#
#  改編自 kostenyang/vcf9-lab-automation 的 autodeployvcfm02.ps1
#  (William Lam vcf-automated-lab-deployment) → 對應本 Lab 的 flat 192.168.110.0/24 環境
#
#  流程：連到 Xindian vCenter → 部署 4 台 Nested ESXi 8.0u3b + Cloud Builder 5.2.1
#        → 建 vApp → 產生 vcf-config.json (License-Later / 60 天評估模式)
#
#  執行：  pwsh -File .\deploy-vcf521-m01.ps1
#  接著：  .\run-bringup.ps1   (Phase 2：提交 JSON 給 Cloud Builder 做 bringup)
#  前置：  先跑 .\prep-dns.ps1 在 ADSrv 建好正/反解 DNS
# ============================================================================

#region ===== 部署目標 vCenter (Xindian vCenter) =====
$VIServer   = "192.168.110.32"
$VIUsername = "administrator@vsphere.local"
$VIPassword = "<PHYSICAL_VC_PASSWORD>"
#endregion

#region ===== OVA 路徑 (你下載後請改成實際路徑) =====
$NestedESXiApplianceOVA = "E:\Nested_ESXi8.0u3g_Appliance_Template_v1.ova"
$CloudBuilderOVA        = "E:\VMware-Cloud-Builder-5.2.1.0-24307856_OVF10.ova"
#endregion

#region ===== 部署目標資源 (請用 README 的探索指令查出實際名稱後填入) =====
$VMDatacenter = "Xindian Datacenter"    # Get-Datacenter
$VMCluster    = "XinDian Cluster"       # Get-Cluster (DRS=off → 不建 vApp)
$VMDatastore  = "Datastore2"            # 4889GB free VMFS
$VMNetwork    = "VCF-Nested"            # 已建：vSwitch0, VLAN4095, Promiscuous/Forged/MACChanges=Accept
$VMFolder     = "VCF"
#endregion

#region ===== 管理網段 (flat 192.168.110.0/24) =====
$VMNetmask = "255.255.255.0"
$VMGateway = "192.168.110.254"          # pfSense (dcxd)
$VMDNS     = "192.168.110.1"            # ADSrv
$VMNTP     = "192.168.110.1"            # ADSrv (需確認有提供 NTP，否則改 192.168.110.254)
$VMDomain  = "kosten.lab"               # 必須與 ADSrv 的 DNS 正解區域 (prep-dns.ps1 $Zone) 一致
$VMSyslog  = "192.168.110.1"
$VMPassword = "<VC_ESXI_PASSWORD>"             # Nested ESXi root 密碼
#endregion

#region ===== Cloud Builder (bringup 控制器；部署後可於 bringup 完成後關機) =====
$CloudbuilderVMName       = "vcf-m01-cb01"
$CloudbuilderHostname     = "vcf-m01-cb01.$VMDomain"
$CloudbuilderIP           = "192.168.110.140"
$CloudbuilderAdminUsername = "admin"
$CloudbuilderAdminPassword = "<CLOUDBUILDER_PASSWORD>"
$CloudbuilderRootPassword  = "<CLOUDBUILDER_PASSWORD>"
#endregion

#region ===== SDDC Manager =====
$SddcManagerName          = "vcf-m01-sddcm01"
$SddcManagerIP            = "192.168.110.141"
$SddcManagerVcfPassword   = "<NSX_SDDC_OPS_PASSWORD>"
$SddcManagerRootPassword  = "<NSX_SDDC_OPS_PASSWORD>"
$SddcManagerRestPassword  = "<NSX_SDDC_OPS_PASSWORD>"
$SddcManagerLocalPassword = "<NSX_SDDC_OPS_PASSWORD>"
#endregion

#region ===== vCenter (VCF 管理域) =====
$VCSAName         = "vcf-m01-vc01"
$VCSAIP           = "192.168.110.142"
$VCSARootPassword = "<VC_ESXI_PASSWORD>"
$VCSASSOPassword  = "<VC_ESXI_PASSWORD>"
$VCSASize         = "tiny"             # tiny=10GB RAM，受限主機建議 tiny
#endregion

#region ===== NSX (Lab 用單一 Manager) =====
$NSXManagerVIPName   = "vcf-m01-nsx01"
$NSXManagerVIPIP     = "192.168.110.143"
$NSXManagerNode1Name = "vcf-m01-nsx01a"
$NSXManagerNode1IP   = "192.168.110.144"
$NSXManagerSize      = "medium"        # medium=24GB。small(16GB) 會讓 phonehome-coordinator OOM → CEIP 失敗 (KB 382996)
$NSXRootPassword     = "<NSX_SDDC_OPS_PASSWORD>"
$NSXAdminPassword    = "<NSX_SDDC_OPS_PASSWORD>"
$NSXAuditPassword    = "<NSX_SDDC_OPS_PASSWORD>"
#endregion

#region ===== Nested ESXi 主機 (管理域最少 4 台) =====
$NestedESXiHostnameToIPs = [ordered]@{
    "vcf-m01-esx01" = "192.168.110.145"
    "vcf-m01-esx02" = "192.168.110.146"
    "vcf-m01-esx03" = "192.168.110.147"
    "vcf-m01-esx04" = "192.168.110.148"
}

# ── 資源：受限於實體主機 < 256GB RAM，已從官方建議 96GB 下修至 48GB ──
# ── 若實體主機 RAM 更少，請見 README「記憶體預算」表；VCF 管理域 4 節點是硬性下限 ──
$NestedESXivCPU          = "8"    # 主機 32 核，4×8=32 (1:1)
$NestedESXivMEM          = "64"   # GB。主機實測 512GB/460 free → 64×4=256GB，headroom 充足
$NestedESXiCachingvDisk  = "100"  # GB (thin)
$NestedESXiCapacityvDisk = "700"  # GB (thin)  Datastore2 4889GB free，用官方值
#endregion

#region ===== VCF 內部專用網段 (不路由；全部 vlanId 0，僅存在於 nested VDS) =====
$MgmtNetworkCidr = "192.168.110.0/24"

$vMotionCidr    = "192.168.113.0/24"
$vMotionGateway = "192.168.113.254"
$vMotionStartIP = "192.168.113.101"
$vMotionEndIP   = "192.168.113.110"

$vSANCidr    = "192.168.114.0/24"
$vSANGateway = "192.168.114.254"
$vSANStartIP = "192.168.114.101"
$vSANEndIP   = "192.168.114.110"

# NSX Host Overlay TEP — 靜態 IP Pool (本 Lab 無 DHCP，必用 static)
$NSXTepCidr    = "192.168.115.0/24"
$NSXTepGateway = "192.168.115.254"
$NSXTepStartIP = "192.168.115.101"
$NSXTepEndIP   = "192.168.115.110"
$NSXTransportVlanId = 0
#endregion

#region ===== 授權 (留空 = License-Later 60 天評估模式) =====
$VCSALicense = ""
$ESXILicense = ""
$VSANLicense = ""
$NSXLicense  = ""
#endregion

#### ======================= DO NOT EDIT BEYOND HERE ======================= ####

$verboseLogFile = "vcf521-m01-deployment.log"
$random_string  = -join ((65..90) + (97..122) | Get-Random -Count 6 | ForEach-Object {[char]$_})
$VAppName       = "Nested-VCF521-M01-$random_string"
$JsonOutFile    = "vcf-config.json"

$preCheck            = 1
$confirmDeployment   = 0   # 全自動：跳過互動確認
$deployNestedESXiVMs = 1
$deployCloudBuilder  = 1
$moveVMsIntovApp     = 0   # XinDian Cluster DRS=off，vApp 需 DRS → 跳過 (VM 放 cluster 根)
$generateJson        = 1

$StartTime = Get-Date

Function My-Logger {
    param(
        [Parameter(Mandatory=$true)][String]$message,
        [Parameter(Mandatory=$false)][String]$color="green"
    )
    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$timeStamp]"
    Write-Host -ForegroundColor $color " $message"
    "[$timeStamp] $message" | Out-File -Append -LiteralPath $verboseLogFile
}

if($preCheck -eq 1) {
    if($PSVersionTable.PSEdition -ne "Core") {
        Write-Host -ForegroundColor Yellow "`n提示：非 PowerShell Core，於 Windows PowerShell 5.1 + PowerCLI 執行 (部署階段相容)。`n"
    }
    if(-not (Get-Module -ListAvailable VMware.VimAutomation.Core)) {
        Write-Host -ForegroundColor Red "`n未安裝 PowerCLI，請先： Install-Module VMware.PowerCLI`n"; exit
    }
    foreach($p in @($NestedESXiApplianceOVA,$CloudBuilderOVA)) {
        if($p -match "<<FILL>>" -or -not (Test-Path $p)) {
            Write-Host -ForegroundColor Red "`n找不到 OVA 或路徑仍是 <<FILL>>： $p`n"; exit
        }
    }
    foreach($v in @($VMDatacenter,$VMCluster,$VMDatastore,$VMNetwork)) {
        if($v -match "<<FILL") {
            Write-Host -ForegroundColor Red "`n請先填入部署目標資源名稱 (Datacenter/Cluster/Datastore/Portgroup)。見 README 探索指令。`n"; exit
        }
    }
}

if($confirmDeployment -eq 1) {
    Write-Host -ForegroundColor Magenta "`n即將部署以下設定：`n"
    Write-Host -ForegroundColor Yellow "---- VCF 5.2.1 Nested Lab (License-Later 評估模式) ----"
    Write-Host -NoNewline -ForegroundColor Green "Nested ESXi OVA : "; Write-Host -ForegroundColor White $NestedESXiApplianceOVA
    Write-Host -NoNewline -ForegroundColor Green "Cloud Builder OVA: "; Write-Host -ForegroundColor White $CloudBuilderOVA
    Write-Host -ForegroundColor Yellow "`n---- 目標 vCenter ----"
    Write-Host -NoNewline -ForegroundColor Green "vCenter  : "; Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "Cluster  : "; Write-Host -ForegroundColor White $VMCluster
    Write-Host -NoNewline -ForegroundColor Green "Datastore: "; Write-Host -ForegroundColor White $VMDatastore
    Write-Host -NoNewline -ForegroundColor Green "Portgroup: "; Write-Host -ForegroundColor White $VMNetwork
    Write-Host -ForegroundColor Yellow "`n---- Cloud Builder ----"
    Write-Host -NoNewline -ForegroundColor Green "FQDN/IP : "; Write-Host -ForegroundColor White "$CloudbuilderHostname / $CloudbuilderIP"
    Write-Host -ForegroundColor Yellow "`n---- Nested ESXi ($($NestedESXiHostnameToIPs.Count) 台) ----"
    Write-Host -NoNewline -ForegroundColor Green "每台 vCPU/RAM: "; Write-Host -ForegroundColor White "$NestedESXivCPU vCPU / $NestedESXivMEM GB"
    Write-Host -NoNewline -ForegroundColor Green "IPs      : "; Write-Host -ForegroundColor White ($NestedESXiHostnameToIPs.Values -join ", ")
    Write-Host -NoNewline -ForegroundColor Green "Gateway/DNS/NTP: "; Write-Host -ForegroundColor White "$VMGateway / $VMDNS / $VMNTP"
    Write-Host -NoNewline -ForegroundColor Green "Domain   : "; Write-Host -ForegroundColor White $VMDomain
    Write-Host -ForegroundColor Yellow "`n提醒：實體主機 RAM < 256GB，4×$NestedESXivMEM = $([int]$NestedESXivMEM*4)GB nested。請確認實體主機撐得住 (見 README)。"
    $answer = Read-Host -Prompt "`n確認部署？ (Y/N)"
    if($answer -ne "Y" -and $answer -ne "y") { exit }
    Clear-Host
}

if($deployNestedESXiVMs -eq 1 -or $deployCloudBuilder -eq 1) {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    My-Logger "連線到管理 vCenter $VIServer ..."
    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select-Object -First 1
    $cluster   = Get-Cluster  -Server $viConnection -Name $VMCluster
    $vmhost    = $cluster | Get-VMHost | Select-Object -First 1
}

if($deployNestedESXiVMs -eq 1) {
    $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
        $VMName = $_.Key; $VMIPAddress = $_.Value

        $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
        $networkMapLabel = ($ovfconfig.ToHashTable().keys | Where-Object {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
        $ovfconfig.NetworkMapping.$networkMapLabel.value = $VMNetwork
        $ovfconfig.common.guestinfo.hostname.value  = "${VMName}.${VMDomain}"
        $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
        $ovfconfig.common.guestinfo.netmask.value   = $VMNetmask
        $ovfconfig.common.guestinfo.gateway.value   = $VMGateway
        $ovfconfig.common.guestinfo.dns.value       = $VMDNS
        $ovfconfig.common.guestinfo.domain.value    = $VMDomain
        $ovfconfig.common.guestinfo.ntp.value       = $VMNTP
        $ovfconfig.common.guestinfo.syslog.value    = $VMSyslog
        $ovfconfig.common.guestinfo.password.value  = $VMPassword
        $ovfconfig.common.guestinfo.ssh.value       = $true

        My-Logger "部署 Nested ESXi VM $VMName ..."
        $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $VMName -Location $VMCluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

        My-Logger "加 vmnic2/vmnic3 到 $VMName ..."
        New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $VMNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $VMNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        $vm | New-AdvancedSetting -Name "ethernet2.filter4.name"      -Value "dvfilter-maclearn" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
        $vm | New-AdvancedSetting -Name "ethernet2.filter4.onFailure" -Value "failOpen"          -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
        $vm | New-AdvancedSetting -Name "ethernet3.filter4.name"      -Value "dvfilter-maclearn" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
        $vm | New-AdvancedSetting -Name "ethernet3.filter4.onFailure" -Value "failOpen"          -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "設定 vCPU=$NestedESXivCPU / vMEM=$NestedESXivMEM GB ..."
        Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        My-Logger "設定 vSAN Cache=$NestedESXiCachingvDisk GB / Capacity=$NestedESXiCapacityvDisk GB ..."
        Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk  -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "開機 $VMName ..."
        $vm | Start-Vm -RunAsync | Out-Null
    }
}

if($deployCloudBuilder -eq 1) {
    $ovfconfig = Get-OvfConfiguration $CloudBuilderOVA
    $networkMapLabel = ($ovfconfig.ToHashTable().keys | Where-Object {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
    $ovfconfig.NetworkMapping.$networkMapLabel.value       = $VMNetwork
    $ovfconfig.common.guestinfo.hostname.value             = $CloudbuilderHostname
    $ovfconfig.common.guestinfo.ip0.value                  = $CloudbuilderIP
    $ovfconfig.common.guestinfo.netmask0.value             = $VMNetmask
    $ovfconfig.common.guestinfo.gateway.value              = $VMGateway
    $ovfconfig.common.guestinfo.DNS.value                  = $VMDNS
    $ovfconfig.common.guestinfo.domain.value               = $VMDomain
    $ovfconfig.common.guestinfo.searchpath.value           = $VMDomain
    $ovfconfig.common.guestinfo.ntp.value                  = $VMNTP
    $ovfconfig.common.guestinfo.ADMIN_USERNAME.value       = $CloudbuilderAdminUsername
    $ovfconfig.common.guestinfo.ADMIN_PASSWORD.value       = $CloudbuilderAdminPassword
    $ovfconfig.common.guestinfo.ROOT_PASSWORD.value        = $CloudbuilderRootPassword

    My-Logger "部署 Cloud Builder VM $CloudbuilderVMName ..."
    $vm = Import-VApp -Source $CloudBuilderOVA -OvfConfiguration $ovfconfig -Name $CloudbuilderVMName -Location $VMCluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin
    My-Logger "開機 $CloudbuilderVMName ..."
    $vm | Start-Vm -RunAsync | Out-Null
}

if($moveVMsIntovApp -eq 1) {
    My-Logger "建立 vApp $VAppName ..."
    $VApp = New-VApp -Name $VAppName -Server $viConnection -Location $cluster
    if(-Not (Get-Folder $VMFolder -ErrorAction Ignore)) {
        My-Logger "建立 VM Folder $VMFolder ..."
        New-Folder -Name $VMFolder -Server $viConnection -Location (Get-Datacenter $VMDatacenter | Get-Folder vm) | Out-Null
    }
    if($deployNestedESXiVMs -eq 1) {
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            Move-VM -VM (Get-VM -Name $_.Key -Server $viConnection) -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }
    if($deployCloudBuilder -eq 1) {
        Move-VM -VM (Get-VM -Name $CloudbuilderVMName -Server $viConnection) -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
    Move-VApp -Server $viConnection $VAppName -Destination (Get-Folder -Server $viConnection $VMFolder) | Out-File -Append -LiteralPath $verboseLogFile
}

if($deployNestedESXiVMs -eq 1 -or $deployCloudBuilder -eq 1) {
    My-Logger "中斷 vCenter 連線 ..."
    Disconnect-VIServer -Server $viConnection -Confirm:$false
}

if($generateJson -eq 1) {
    $EvaluationMode = ($VCSALicense -eq "" -and $ESXILicense -eq "" -and $VSANLicense -eq "" -and $NSXLicense -eq "")

    $hostSpecs = @()
    $count = 1
    $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
        $hostSpecs += [ordered]@{
            association      = "vcf-m01-dc01"
            ipAddressPrivate = [ordered]@{ ipAddress = $_.Value; cidr = $MgmtNetworkCidr; gateway = $VMGateway }
            hostname         = $_.Key
            credentials      = [ordered]@{ username = "root"; password = $VMPassword }
            sshThumbprint    = "SHA256:DUMMY_VALUE"
            sslThumbprint    = "SHA256:DUMMY_VALUE"
            vSwitch          = "vSwitch0"
            serverId         = "host-$count"
        }
        $count++
    }

    $config = [ordered]@{
        deployWithoutLicenseKeys    = $EvaluationMode
        skipEsxThumbprintValidation = $true
        managementPoolName          = "vcf-m01-rp01"
        sddcManagerSpec = [ordered]@{
            secondUserCredentials = [ordered]@{ username = "vcf"; password = $SddcManagerVcfPassword }
            ipAddress           = $SddcManagerIP
            netmask             = $VMNetmask
            hostname            = $SddcManagerName
            rootUserCredentials = [ordered]@{ username = "root";  password = $SddcManagerRootPassword }
            restApiCredentials  = [ordered]@{ username = "admin"; password = $SddcManagerRestPassword }
            localUserPassword   = $SddcManagerLocalPassword
            vcenterId           = "vcenter-1"
        }
        sddcId       = "vcf-m01"
        esxLicense   = $ESXILicense
        taskName     = "workflowconfig/workflowspec-ems.json"
        ceipEnabled  = $false
        ntpServers   = @($VMNTP)
        dnsSpec      = [ordered]@{ subdomain = $VMDomain; domain = $VMDomain; nameserver = $VMDNS }
        networkSpecs = @(
            [ordered]@{ networkType="MANAGEMENT"; subnet=$MgmtNetworkCidr; gateway=$VMGateway; vlanId="0"; mtu="1500";
                        portGroupKey="vcf-m01-cl01-vds01-pg-mgmt"; standbyUplinks=@(); activeUplinks=@("uplink1","uplink2") },
            [ordered]@{ networkType="VMOTION"; subnet=$vMotionCidr; gateway=$vMotionGateway; vlanId="0"; mtu="1500";
                        portGroupKey="vcf-m01-cl01-vds01-pg-vmotion"; association="vcf-m01-dc01";
                        includeIpAddressRanges=@([ordered]@{startIpAddress=$vMotionStartIP; endIpAddress=$vMotionEndIP});
                        standbyUplinks=@(); activeUplinks=@("uplink1","uplink2") },
            [ordered]@{ networkType="VSAN"; subnet=$vSANCidr; gateway=$vSANGateway; vlanId="0"; mtu="1500";
                        portGroupKey="vcf-m01-cl01-vds01-pg-vsan";
                        includeIpAddressRanges=@([ordered]@{startIpAddress=$vSANStartIP; endIpAddress=$vSANEndIP});
                        standbyUplinks=@(); activeUplinks=@("uplink1","uplink2") }
        )
        nsxtSpec = [ordered]@{
            nsxtManagerSize = $NSXManagerSize
            nsxtManagers    = @([ordered]@{ hostname=$NSXManagerNode1Name; ip=$NSXManagerNode1IP })
            rootNsxtManagerPassword         = $NSXRootPassword
            nsxtAdminPassword               = $NSXAdminPassword
            nsxtAuditPassword               = $NSXAuditPassword
            rootLoginEnabledForNsxtManager  = "true"
            sshEnabledForNsxtManager        = "true"
            overLayTransportZone = [ordered]@{ zoneName="vcf-m01-tz-overlay01"; networkName="netName-overlay" }
            vlanTransportZone    = [ordered]@{ zoneName="vcf-m01-tz-vlan01";    networkName="netName-vlan" }
            vip       = $NSXManagerVIPIP
            vipFqdn   = $NSXManagerVIPName
            nsxtLicense      = $NSXLicense
            transportVlanId  = $NSXTransportVlanId
            ipAddressPoolSpec = [ordered]@{
                name        = "vcf-m01-cl01-tep01"
                description = "ESXi Host Overlay TEP IP Pool"
                subnets     = @([ordered]@{
                    ipAddressPoolRanges = @([ordered]@{ start=$NSXTepStartIP; end=$NSXTepEndIP })
                    cidr    = $NSXTepCidr
                    gateway = $NSXTepGateway
                })
            }
        }
        vsanSpec = [ordered]@{ vsanName="vsan-1"; vsanDedup="false"; licenseFile=$VSANLicense; datastoreName="vcf-m01-cl01-ds-vsan01" }
        dvSwitchVersion = "7.0.0"
        dvsSpecs = @(
            [ordered]@{
                dvsName="vcf-m01-cl01-vds01"; vcenterId="vcenter-1"; vmnics=@("vmnic0","vmnic1"); mtu=9000;  # NSX overlay 需 >=1600；實體 vSwitch0 也已設 9000
                networks=@("MANAGEMENT","VMOTION","VSAN");
                niocSpecs=@(
                    [ordered]@{trafficType="VSAN";value="HIGH"}, [ordered]@{trafficType="VMOTION";value="LOW"},
                    [ordered]@{trafficType="VDP";value="LOW"},   [ordered]@{trafficType="VIRTUALMACHINE";value="HIGH"},
                    [ordered]@{trafficType="MANAGEMENT";value="NORMAL"}, [ordered]@{trafficType="NFS";value="LOW"},
                    [ordered]@{trafficType="HBR";value="LOW"},   [ordered]@{trafficType="FAULTTOLERANCE";value="LOW"},
                    [ordered]@{trafficType="ISCSI";value="LOW"}
                )
                isUsedByNsxt=$true
            }
        )
        clusterSpec = [ordered]@{
            clusterName="vcf-m01-cl01"; vcenterName="vcenter-1"; clusterEvcMode="";
            vmFolders=[ordered]@{ MANAGEMENT="vcf-m01-fd-mgmt"; NETWORKING="vcf-m01-fd-nsx"; EDGENODES="vcf-m01-fd-edge" }
        }
        resourcePoolSpecs = @(
            [ordered]@{ name="vcf-m01-cl01-rp-sddc-mgmt"; type="management"; cpuReservationPercentage=0; cpuLimit=-1; cpuReservationExpandable=$true; cpuSharesLevel="normal"; cpuSharesValue=0; memoryReservationMb=0; memoryLimit=-1; memoryReservationExpandable=$true; memorySharesLevel="normal"; memorySharesValue=0 },
            [ordered]@{ name="vcf-m01-cl01-rp-sddc-edge"; type="network";    cpuReservationPercentage=0; cpuLimit=-1; cpuReservationExpandable=$true; cpuSharesLevel="normal"; cpuSharesValue=0; memoryReservationPercentage=0; memoryLimit=-1; memoryReservationExpandable=$true; memorySharesLevel="normal"; memorySharesValue=0 },
            [ordered]@{ name="vcf-m01-cl01-rp-user-edge"; type="compute";    cpuReservationPercentage=0; cpuLimit=-1; cpuReservationExpandable=$true; cpuSharesLevel="normal"; cpuSharesValue=0; memoryReservationPercentage=0; memoryLimit=-1; memoryReservationExpandable=$true; memorySharesLevel="normal"; memorySharesValue=0 },
            [ordered]@{ name="vcf-m01-cl01-rp-user-vm";   type="compute";    cpuReservationPercentage=0; cpuLimit=-1; cpuReservationExpandable=$true; cpuSharesLevel="normal"; cpuSharesValue=0; memoryReservationPercentage=0; memoryLimit=-1; memoryReservationExpandable=$true; memorySharesLevel="normal"; memorySharesValue=0 }
        )
        pscSpecs = @(
            [ordered]@{ pscId="psc-1"; vcenterId="vcenter-1"; adminUserSsoPassword=$VCSASSOPassword; pscSsoSpec=[ordered]@{ ssoDomain="vsphere.local" } }
        )
        vcenterSpec = [ordered]@{
            vcenterIp=$VCSAIP; vcenterHostname=$VCSAName; vcenterId="vcenter-1"; licenseFile=$VCSALicense;
            vmSize=$VCSASize; storageSize=""; rootVcenterPassword=$VCSARootPassword
        }
        hostSpecs = $hostSpecs
        excludedComponents = @("NSX-V","AVN","EBGP")
    }

    My-Logger "產生 Cloud Builder bringup 設定檔： $JsonOutFile  (EvaluationMode=$EvaluationMode)"
    $config | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $JsonOutFile -Encoding utf8

    My-Logger "======================================================" "yellow"
    My-Logger "NEXT STEPS:" "yellow"
    My-Logger "1. 等 Nested ESXi + Cloud Builder 全部開機 (~10 分)" "yellow"
    My-Logger "2. 確認 ADSrv 上正/反解 DNS 已建好 (prep-dns.ps1)" "yellow"
    My-Logger "3. 執行 .\run-bringup.ps1 提交 $JsonOutFile 給 Cloud Builder" "yellow"
    My-Logger "======================================================" "yellow"
}

$EndTime  = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)
My-Logger "Phase 1 完成！Duration: $duration 分鐘"
