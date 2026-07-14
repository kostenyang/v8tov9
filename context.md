# Context ??VCF 5.2.1 ??9.1 ??

## ?? ?桀???????券摰? (2026-07-13)
- ??**NSX = 9.1.0.0100.25470810**嚗P / HOST / EDGE / **FINALIZE** ??SUCCESS嚗?- ??**vCenter = 9.1.0.0100 build 25417926**嚗igration 摰?嚗???.142嚗SO 甇?虜嚗nventory 摰嚗?- ??**ESXi ?4 = 9.1.0 build-25433460**嚗 CONNECTED?M Disabled嚗?- ??**vSAN OVERALL green**嚗隞嗅 healthy?esync 0嚗?- 畾??????vSAN Disk format version嚗n-disk ?澆??舫??嚗erformance service嚗?嚗?- SDDC Manager 隞?5.2.1嚗???VCF LCM嚗?- ??蝬風銝甈∪祕擃??鳴??啣?摰?Ｗ儔嚗CLS 靽桀儔?舀?銋身摰???
## ?啣? / 摮?
| 閫 | IP | 隤? |
|------|-----|------|
| 憭惜 Xindian vCenter | 192.168.110.32 | administrator@vsphere.local / <PHYSICAL_VC_PASSWORD> |
| 撖阡? ESXi (憭惜) | 192.168.110.16 | ESXi 8.0.3 繚 Xeon E5-2682 v4 (Broadwell) |
| Nested vCenter (VCF) | 192.168.110.142 | administrator@vsphere.local / <VC_ESXI_PASSWORD> |
| ??vCenter appliance (?急?) | 192.168.110.151 | root / <VC_ESXI_PASSWORD> |
| Nested NSX Manager | 192.168.110.143 | admin / <NSX_PASSWORD>嚗PI basic嚗
| Nested ESXi ?4 | 192.168.110.145??48 | root / <VC_ESXI_PASSWORD>嚗SH ???API ?嚗
| SDDC Manager | 192.168.110.141 | ??|
| ADSrv / DNS (kosten.lab) | 192.168.110.1 | ??|
| Nested cluster | MoID `domain-c9` (vcf-m01-cl01) | hosts host-12/26/28/30 = esx01/02/03/04 |
| Nested ESXi VM (??Xindian) | vm-29025..29028 = esx01..04 | ??|

## ?瘙箇? + ?
- **guestId ??vmkernel8Guest + vHW-20**嚗? ??nested ESXi VM嚗 Xindian .32嚗???guest type=Other(64bit) 銝? MWAIT ??CRX vCLS ??鈭? ??DRS 憭望??閫?NSX Host ???⊿??????vmx嚗?銋??敺?vCLS ?芸??Ｗ儔嚗?- **? vSAN HCL ?亙熒皜祈岫**嚗ontrollerdiskmode 蝑?嚗ested ??批?冽隤???嚗LCM 隞?overall_health_not_green ??host ??MM??- **vcsa-deploy ??`--upgrade-framework legacy`**嚗?閮?RDU ??nested DRS ?ａ?鞈?撽??⊥香??- **`--skip-product-interop-check`**嚗?皞?vCenter ?暹? NSX 4.2.1嚗???NSX 敺圾?扎?- **NSX ????session+XSRF API 撽?**嚗SX UC ??Angular iframe 撣詨?蝯?CDP嚗creenshot timeout嚗?- **銝? snapshot**嚗蝙?刻?瘙?憭芣嚗?- **allowLegacyCPU=TRUE (boot.cfg kernelopt) + --no-hardware-warning**嚗roadwell 鋡?VCF9 ??discontinued嚗迨瘜?刻府 CPU ?? ESXi 9.1??
## ?瑼?頝臬? (撠???C:\Users\mjalan\Documents\vspher8to9\)
- `vcsa91-upgrade.json` ??vCenter migration 蝭嚗emp IP .151??142, migrateSet core嚗?- `doc\build_doc.py` + `doc\VCF-5.2.1-to-9.1-Manual-Upgrade.docx` ??鈭支??辣嚗?1 蝡?4 ??
- `shots\*.png` ????畾菜??grab.ps1 ??PrintWindow ??Chrome 閬?嚗?- NSX嚗nsx-continue.ps1`嚗ction/component 蝥?嚗nsx-monitor.ps1`?nsx-upg-status.ps1`
- vLCM/vSAN/vCLS 靽桀儔嚗vclcm-recheck.ps1`?vsan-silence.ps1`?vcls-retreat.ps1`?vcls-monitor.ps1`
- MWAIT 靽桀儔嚗xindian-setguestos.ps1`?upgrade-hw-guest.ps1`?enable-ssh.ps1`
- ESXi 9 CPU 蝜?嚗patch-boot.sh`?https_repo.py`嚗 v8tov9 git嚗?- memory嚗~\.claude\...\memory\vcf521-nested-lab.md`嚗??渲萱????

## 撣貊 API / ?誘
- NSX 蝥?嚗POST https://<nsx>/api/v1/upgrade/plan?action=continue&component_type=HOST`嚗? POST /api/session/create ??x-xsrf-token嚗?- NSX ???`GET /api/v1/upgrade/status-summary?component_type=HOST`嚗asic auth嚗?- vLCM precheck嚗POST /api/esx/settings/clusters/domain-c9/software?action=check` body `{}`
- vSAN ?嚗OAP `VsanHealthSetVsanClusterSilentChecks`嚗ttps://vc/vsanHealth, SOAPAction urn:vsan/8.0.2.0嚗?- ?唳? deployment ???`GET https://151:5480/rest/vcenter/deployment`嚗oot basic嚗?- vCenter SOAP嚗?sdk ? SOAPAction `urn:vim25/8.0.2.0`嚗???啗? vim2.5嚗?
