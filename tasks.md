# Tasks ??VCF 5.2.1 ??9.1 ??

## NSX (Part 1)
- [x] ?臬 NSX 9.1 bundle (.mub) + ?亙? EULA
- [x] ?? Upgrade Coordinator ??9.1
- [x] Pre-checks ??嚗? warnings acknowledge嚗?- [x] NSX Manager (MP) ?? ??SUCCESS嚗耨 compute manager ?閮餃?嚗?- [x] NSX Host VIB ?4 ?? ??SUCCESS嚗?/4嚗?  - [x] 閫?vLCM health check嚗???vSAN HCL 皜祈岫
  - [x] 閫?DRS/vCLS嚗耨 nested VM guestId=vmkernel8 + vHW-20嚗WAIT嚗?- [x] NSX Edge ??SUCCESS嚗kip嚗 edge嚗?
## vCenter
- [x] ?? VCSA 9.1 ISO (F:)
- [x] precheck ?券?嚗egacy framework, skip-interop嚗?- [x] **?瑁? migration ?? ??摰? (exit 0)**
  - [x] Stage 1 ?函蔡??appliance (.151)
  - [x] rpminstall / precheck / export / firstboot / import ??SUCCEEDED
  - [x] IP ?? .151 ??.142嚗?璈?璈?  - [x] 撽???vCenter **9.1.0.0100 build 25417926** ??.142?SO OK?? host CONNECTED?nventory 摰

## ESXi ?4 (Broadwell CPU 蝜?)
- [x] 撽???航?嚗sxi9-cputest ????嚗?- [x] **?潛嚗rofile-update 頝臬???9.1 ??Broadwell 銝???llowLegacyCPU嚗sx03 撖西?????嚗?*
- [x] esx03 ??9.1嚗ONNECTED嚗SAN green嚗?- [x] esx02 ??9.1嚗SXi 9.1.0 build-25433460嚗xit MM OK嚗?- [x] esx04 ??9.1嚗?.1.0 build-25433460嚗M Disabled嚗esync 0嚗?- [x] esx01 ??9.1嚗???vCenter嚗?敺?嚗???
- [x] **4 ?啣??9.1.0 build-25433460嚗ONNECTED嚗M Disabled嚗SAN green**

## NSX (Part 2) ??? vCenter 9.1 敺?- [x] **NSX Finalize Upgrade ??SUCCESS**嚗Center 9.1 敺?gate 閫?嚗?- [x] **NSX ? = 9.1.0.0100.25470810**嚗P/HOST/EDGE/FINALIZE ??SUCCESS嚗?
## ?? ??摰? (2026-07-13)
- NSX 9.1.0.0100.25470810 繚 vCenter 9.1.0.0100 build 25417926 繚 ESXi ?4 9.1.0 build-25433460 繚 vSAN green

## ?嗅偏
- [ ] 憭 extension (LCM/SDDC/NSX) ??vCenter ??敺??啗酉??- [ ] ?湧? fleet ?亙熒撽?嚗RS/vCLS/vSAN/NSX/vCenter嚗?- [x] 鈭支??辣?湔嚗oc\*.docx嚗?芸?嚗?- [ ] 鈭支??辣?湔?唳?蝯???- [ ] ?其? github.com/kostenyang/v8tov9嚗?蝣?placeholder嚗?
> ??嚗x] 摰??[~] ?脰?銝准[ ] 敺齒

