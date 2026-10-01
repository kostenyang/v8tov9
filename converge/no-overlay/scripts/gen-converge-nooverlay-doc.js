const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, ImageRun, PageBreak, BorderStyle
} = require('docx');

const SHOTS = 'E:\\9.1\\doc-shots\\converge-target';
const OUT   = 'E:\\9.1\\VCF911-Converge-NoOverlay.docx';

const C = { blue: '1F4E79', gray: '595959', red: 'C00000', green: '2E7D32', amber: 'B77E00' };
const W_UI = 600;

const H1 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_1, spacing: { before: 340, after: 160 } });
const H2 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_2, spacing: { before: 260, after: 120 } });
const H3 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 100 } });
const P = (t, o = {}) => new Paragraph({
  children: [new TextRun({ text: t, size: o.size || 21, bold: o.bold, color: o.color, italics: o.italics })],
  spacing: { after: o.after != null ? o.after : 110 }, alignment: o.align });
const CODE = t => new Paragraph({
  children: t.split('\n').map((ln, i) => new TextRun({ text: ln, font: 'Consolas', size: 16, break: i ? 1 : 0 })),
  shading: { type: ShadingType.CLEAR, fill: 'F4F4F4' },
  spacing: { before: 70, after: 70 }, indent: { left: 220 } });
const BULLET = t => new Paragraph({
  children: [new TextRun({ text: t, size: 21 })], bullet: { level: 0 }, spacing: { after: 70 } });
const NOTE = (t, fill, color) => new Paragraph({
  children: [new TextRun({ text: t, size: 20, color: color || C.gray })],
  shading: { type: ShadingType.CLEAR, fill: fill || 'FFF6E5' },
  spacing: { before: 90, after: 90 }, indent: { left: 120, right: 120 },
  border: { left: { style: BorderStyle.SINGLE, size: 18, color: color || C.amber } } });
const PB = () => new Paragraph({ children: [new PageBreak()] });

const TOTAL = 9000;
function table(headers, rows, pct) {
  const widths = pct.map(p => Math.round(TOTAL * p / 100));
  const hdr = new TableRow({ tableHeader: true, children: headers.map((h, i) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA },
    shading: { type: ShadingType.CLEAR, fill: C.blue },
    children: [new Paragraph({ children: [new TextRun({ text: h, bold: true, color: 'FFFFFF', size: 19 })] })] })) });
  const body = rows.map((r, ri) => new TableRow({ children: r.map((c, i) => new TableCell({
    width: { size: widths[i], type: WidthType.DXA },
    shading: ri % 2 ? { type: ShadingType.CLEAR, fill: 'F7F9FC' } : undefined,
    children: [new Paragraph({ children: [new TextRun({ text: String(c), size: 18 })] })] })) }));
  return new Table({ rows: [hdr].concat(body), columnWidths: widths, width: { size: TOTAL, type: WidthType.DXA } });
}
function pngSize(p) { const b = fs.readFileSync(p); return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }; }
let figNo = 0;
function fig(dir, file, caption, maxW) {
  const p = path.join(dir, file);
  const out = []; figNo++;
  if (fs.existsSync(p)) {
    const { w, h } = pngSize(p); const cw = maxW || W_UI; const ch = Math.round(cw * h / w);
    out.push(new Paragraph({ children: [new ImageRun({ type: 'png', data: fs.readFileSync(p), transformation: { width: cw, height: ch } })],
      alignment: AlignmentType.CENTER, spacing: { before: 140, after: 40 } }));
  } else {
    out.push(new Paragraph({ children: [new TextRun({ text: '[ 缺圖:' + file + ' ]', italics: true, color: C.red, size: 18 })], alignment: AlignmentType.CENTER }));
  }
  out.push(new Paragraph({ children: [new TextRun({ text: '圖 ' + figNo + '\u3000' + caption, size: 18, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 180 } }));
  return out;
}
const F = (f, c, w) => fig(SHOTS, f, c, w);
const clean = t => t.replace(/\r/g, '')
  .replace(/\u001b\[[0-9;?]*[a-zA-Z]/g, '')
  .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '')
  .trim();
const cli = f => { const p = path.join(SHOTS, 'cli', f); return fs.existsSync(p) ? clean(fs.readFileSync(p, 'utf8')) : '[缺:' + f + ']'; };


const doc = new Document({
  styles: { default: {
    heading1: { run: { size: 30, bold: true, color: C.blue }, paragraph: { spacing: { before: 340, after: 160 } } },
    heading2: { run: { size: 25, bold: true, color: C.blue }, paragraph: { spacing: { before: 260, after: 120 } } },
    heading3: { run: { size: 22, bold: true, color: '2E5F8A' }, paragraph: { spacing: { before: 200, after: 100 } } },
    document: { run: { font: 'Microsoft JhengHei', size: 21 } } } },
  sections: [{ properties: { page: { margin: { top: 900, bottom: 900, left: 1000, right: 1000 } } }, children: [

    // ── 封面 ──
    new Paragraph({ children: [new TextRun({ text: '', size: 24 })], spacing: { after: 1700 } }),
    new Paragraph({ children: [new TextRun({ text: '把既有 vSphere Converge 成 VCF 9.1.1', size: 42, bold: true, color: C.blue })], alignment: AlignmentType.CENTER }),
    new Paragraph({ children: [new TextRun({ text: '不部署 Overlay 的兩種做法與實測', size: 32, bold: true, color: C.blue })], alignment: AlignmentType.CENTER, spacing: { after: 300 } }),
    new Paragraph({ children: [new TextRun({ text: '變體 A:部 NSX 但不設 overlay(vtepless)　／　變體 B:VVF,完全不要 NSX', size: 23, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 160 } }),
    new Paragraph({ children: [new TextRun({ text: '從零建目標端 → 驗證 → 送出 → 結果驗收,全程逐步截圖', size: 21, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 800 } }),
    new Paragraph({ children: [new TextRun({ text: '實作日期:2026-09-30 ~ 10-01', size: 21 })], alignment: AlignmentType.CENTER }),
    new Paragraph({ children: [new TextRun({ text: '結果:COMPLETED_WITH_SUCCESS　181 / 181 子任務　0 失敗　5 小時 26 分', size: 21, bold: true, color: C.green })], alignment: AlignmentType.CENTER, spacing: { before: 120 } }),
    PB(),

    // ── 目錄 ──
    H1('目錄'),
    P('一、摘要與結論'),
    P('二、為什麼要「沒有 overlay」'),
    P('三、環境與前置'),
    P('四、建立 converge 目標端'),
    P('五、兩種「沒有 overlay」的 spec 寫法'),
    P('六、送出 converge(逐步)'),
    P('七、結果驗收'),
    P('八、踩坑速查'),
    P('附錄 A:指令彙整　附錄 B:CLI 輸出'),
    PB(),

    // ── 一 ──
    H1('一、摘要與結論'),
    P('本文把一套「手動建置到 9.1.1、尚未被任何 SDDC Manager 納管」的 vSphere,用 VCF Installer 9.1.1 converge 成 VCF Management Domain,並且刻意**不部署 overlay**。'),
    table(['問題', '答案', '依據'],
      [['可以 converge 成 VCF 但完全不設 overlay 嗎?', '✅ 可以', '變體 A 實測:181/181 成功,4 台 host 全程 vtepless'],
       ['可以 converge 成完全沒有 NSX 的形態嗎?', '✅ 可以(VVF)', 'workflowType=VVF,installer 接受並以 VALIDATION_VVF 驗證'],
       ['不給 TEP 會不會擋住 NSX 部署或 host prep?', '❌ 不會', 'NSX 69/69 成功、cluster Prepared、4 Hosts Up'],
       ['host 會長什麼樣?', 'vtepless', 'TEP IP Address = Not Set、Tunnels = Not Available、ip_assignment_spec = null']],
      [34, 16, 50]),
    NOTE('關鍵欄位:nsxtSpec.skipNsxOverlayOverManagementNetwork = true,而且**刻意不給** transportVlanId 與 ipAddressPoolSpec。NSX 會正常部出來、host 會正常 prepare,只是沒有 TEP、沒有 tunnel。', 'E8F5E9', C.green),
    H2('1.1 五個里程碑'),
    table(['里程碑', '子任務', '耗時'],
      [['Convert the existing vCenter to a new VCF instance', '42 / 42', '4m 37s'],
       ['Deploy and configure NSX', '69 / 69', '31m 10s'],
       ['Deploy and configure VCF Management Platform (VSP)', '21 / 21', '1h 59m 50s'],
       ['Deploy and configure the operations appliance', '15 / 15', '1h 12m 17s'],
       ['Deploy and configure VCF Management Services', '18 / 18', '1h 6m 1s']],
      [58, 20, 22]),
    ...F('50-converge-complete.png', 'VCF Installer:Congratulations! Your deployment completed successfully — 五個里程碑全綠'),
    PB(),

    // ── 二 ──
    H1('二、為什麼要「沒有 overlay」'),
    P('客戶現場常見兩種情形:實體網路只給管理網段、拿不到 NSX Host Overlay(TEP)的 VLAN 與 subnet;或是根本不打算導入 NSX,只想要 vSphere 加上 VCF 的生命週期與授權管理。'),
    P('VCF 9.1 的 converge 流程對這兩種情形各有對應的寫法,但官方文件沒有正面寫清楚「完全不要 overlay」要怎麼填,所以本文把兩種都做出來並留下證據。'),
    table(['變體', '做法', '結果'],
      [['A', 'workflowType=VCF;部 NSX,但 skipNsxOverlayOverManagementNetwork=true 且不給 TEP', '本文完整實作,converge 成功'],
       ['B', 'workflowType=VVF;整個省略 nsxtSpec 與 sddcManagerSpec', '驗證到只差 bundle 未下載,路線確認可行'],
       ['(對照)', 'skipNsxOverlayOverManagementNetwork=false → overlay 走 vmk0,不需要 TEP', '另一份文件已實測,不在本文範圍']],
      [12, 56, 32]),
    NOTE('三者的差別只在 nsxtSpec。A 是「有 NSX、沒有 overlay」,B 是「連 NSX 都沒有」,對照組是「有 overlay 但不用額外 TEP 網段」。', 'FFF6E5', C.amber),
    PB(),

    // ── 三 ──
    H1('三、環境與前置'),
    table(['項目', '值'],
      [['VCF Installer', 'vcf-m02-inst05.home.lab / 10.0.1.44 / 9.1.1.0.25713928(全新、DB 乾淨)'],
       ['Depot', 'http://10.0.0.61:8888(自建 offline depot)'],
       ['目標端 vCenter', 'vcf-m02-vc01.home.lab / 10.0.1.19 / 9.1.1.0.25712839'],
       ['Cluster / Datacenter', 'vcf-m02-cl01 / vcf-m02-dc01(vLCM image 管理)'],
       ['ESXi ×4', 'vcf-m02-esx01~04.home.lab / 10.0.1.14-17 / 9.1.1 build 25714478'],
       ['vSAN', 'OSA,8 TB(每台 100 GB cache + 2×1000 GB capacity)'],
       ['VDS', 'vcf-m02-cl01-vds01,MTU 9000,每台 vmnic0 + vmnic1'],
       ['管理網段', '10.0.0.0/23,gw 10.0.0.1,DNS 10.0.0.200,NTP 10.0.1.254']],
      [26, 74]),
    H2('3.1 🔴 installer 必須是乾淨的'),
    P('做過 bring-up 或前一次 converge 的 installer,資料庫裡會記著舊的 domain。本次特地重部一台全新的 installer,確認 /v1/sddcs、/v1/domains、/v1/hosts 全部回 count=0 之後才開始。'),
    CODE('curl -sk -H "Authorization: Bearer $T" https://<installer>/v1/sddcs    # 必須是 []\n'
       + '# 對照:沿用的舊 installer 會看到前一次的 COMPLETED_WITH_SUCCESS 記錄'),
    H2('3.2 🔴 目標端不可以有 VCF extension'),
    P('如果這座 vCenter 曾被 VCF 納管過,會殘留 com.vmware.sddcManager / com.vmware.vcf.client extension,converge 驗證會判定它已屬於 VCF 而擋下來。全新手動建置的 vCenter 通常沒有,但還是要查。'),
    CODE('govc extension.info | grep -iE "sddcmanager|vcf.client"   # 應該沒有輸出'),
    PB(),

    // ── 四 ──
    H1('四、建立 converge 目標端'),
    P('converge 的前提是「一套已經在跑、但還沒被 VCF 納管的 vSphere」。本章把它從零建出來。NSX 不需要事先安裝 —— converge 會自己部。'),
    H2('4.1 nested ESXi ×4'),
    P('從 Nested_ESXi9.1.0.0 OVA 部 4 台(各 24 vCPU / 192 GB;100 GB cache + 1000 GB capacity),分散在兩顆實體 datastore 上降低 I/O 競爭。部完套用 nested lab 的 vSAN advanced settings。'),
    table(['設定', '值', '用途'],
      [['/LSOM/VSANDeviceMonitoring', '0', '關裝置監控,避免 nested 誤判磁碟錯誤'],
       ['/LSOM/lsomSlowDeviceUnmount', '0', '關慢速磁碟偵測'],
       ['/VSAN/SwapThickProvisionDisabled', '1', '省空間'],
       ['/VSAN/Vsan2ZdomCompZstd', '0', 'CPU 受限環境回退 LZ4'],
       ['/VSAN/FakeSCSIReservations', '1', 'nested vSAN 跑在實體 vSAN 上必要'],
       ['/VSAN/GuestUnmap', '1', 'TRIM/UNMAP 傳遞']],
      [40, 10, 50]),
    NOTE('Prepare-NestedESXi.ps1 不給 -Password 會跳 Get-Credential,在非互動環境下**卡住且完全沒有輸出**。一定要帶 -Password。', 'FFF6E5', C.amber),
    H2('4.2 vCenter 9.1.1(single-node vSAN 引導)'),
    P('用 VCSA ISO 內的 vCSA_with_cluster_on_ESXi.json 範本,在 esx01 上以單節點 vSAN 引導 vCenter,順便把 datacenter 與 vLCM image 管理的 cluster 一起建出來。'),
    CODE('vcsa-deploy install --precheck-only --accept-eula --no-ssl-certificate-verification \\\n'
       + '    --log-dir <logdir> vcsa-install-m02.json\n'
       + 'vcsa-deploy install --accept-eula --no-ssl-certificate-verification \\\n'
       + '    --acknowledge-ceip --log-dir <logdir> vcsa-install-m02.json'),
    NOTE('🔴 範本的 esxi.hostname 要填 **FQDN** 不要填 IP。填 IP 的話 cluster 裡的 host 名稱就會是 IP,VCF 慣例要 FQDN;事後只能用 govc object.rename 補救。', 'FDECEA', C.red),
    H2('4.3 加主機、建 VDS、收 vSAN'),
    P('Build-ConvergeTarget.ps1 一次做完:加 esx02-04、建 VDS 與三個 portgroup、把 vmk0 與 vmnic 搬上 VDS、建 vMotion/vSAN vmkernel、收 vSAN、開 DRS/HA。'),
    NOTE('🔴 搬 VM 到 VDS portgroup 之前,一定要先確認那台主機在 VDS 上**已經有 uplink**。上一次跑到一半失敗時主機已加入 VDS 但 pnic 沒掛上,重跑時判斷式只看「在不在 VDS 上」就跳過,接著把 vCenter 自己的網卡搬到沒有上行的 portgroup —— vCenter 當場失聯。救法是直接連 ESXi 主機繞過 vCenter:govc vm.network.change -vm <vcsa> -net "VM Network" ethernet-0。', 'FDECEA', C.red),
    H2('4.4 用 vLCM 升到 9.1.1'),
    P('OVA 是 9.1.0,目標端要 9.1.1。ESXi 9.x 的 esxcli 已經**不接受遠端 URL 的 offline bundle**,所以改走 vLCM:把 depot zip 以 PULL 方式匯入 vCenter,設 cluster desired image,再 remediate。'),
    CODE('# esxcli 這條路在 9.x 已經不通\n'
       + 'esxcli software profile update -d http://.../VMware-ESXi-9.1.1.0.25714478-depot.zip\n'
       + '  [ValueError] Only server local file path is supported for offline bundles.\n\n'
       + '# 改走 vLCM(vSphere Automation API)\n'
       + 'POST /api/esx/settings/depots/offline?vmw-task=true\n'
       + '     {"source_type":"PULL","location":"http://10.0.0.61:8888/PROD/COMP/ESX_HOST/<zip>"}\n'
       + 'POST /api/esx/settings/clusters/{c}/software/drafts                       # 建 draft\n'
       + 'PUT  /api/esx/settings/clusters/{c}/software/drafts/{d}/software/base-image\n'
       + '     {"version":"9.1.1.0.25714478"}\n'
       + 'POST /api/esx/settings/clusters/{c}/software/drafts/{d}?action=commit&vmw-task=true\n'
       + 'POST /api/esx/settings/clusters/{c}/software?action=apply&vmw-task=true\n'
       + '     {"accept_eula":true}                     # 注意:不是 {"spec":{...}}'),
    ...F('04-vlcm-image.png', 'vLCM Image:ESXi Version 9.1.1.0.25714478,All hosts in this cluster are compliant'),
    CODE(cli('esxi-versions.txt')),
    PB(),

    H2('4.5 🔴 兩個會讓 remediate 假成功 / 真失敗的坑'),
    H3('(1) task 回 SUCCEEDED,但主機版本根本沒變'),
    P('第一次 apply 的 task 狀態是 SUCCEEDED、progress 100,但 4 台 build 完全沒動。真相在 last-apply-result:'),
    CODE('GET /api/esx/settings/clusters/{c}/software/reports/last-apply-result\n'
       + '  skipped_hosts: ["host-12","host-18","host-19","host-20"]\n'
       + '  host_status.*.notifications.errors:\n'
       + '    com.vmware.vcIntegrity.lifecycle.EsxImage.DepotConnectErrorV2\n'
       + '    URL: http://vcf-m02-vc01.home.lab:9084/vum/repository/...\n'
       + '    Error: <urlopen error [Errno -2] Name or service not known>'),
    P('根因是主機的 DNS 清單是 10.0.0.1, 10.0.0.200 —— 排在前面的家用路由器對 home.lab 回 NXDOMAIN,ESXi 的 resolver **不會往後 fallback**,於是解不到 vCenter 的 FQDN,而 vLCM 的 depot 正是掛在 vCenter 的 9084 埠。'),
    CODE('govc host.esxcli -- network ip dns server remove -s 10.0.0.1   # 4 台都做\n'
       + 'govc host.esxcli -- network diag ping -c 1 -H vcf-m02-vc01.home.lab   # 改完等一下負快取過期'),
    NOTE('教訓:vLCM 的 task 狀態不等於主機有升級。一定要看 last-apply-result 的 successful_hosts / skipped_hosts,或直接比對主機 build。', 'FDECEA', C.red),
    H3('(2) Health Check for <cluster> failed'),
    P('DNS 修好後 apply 變成真的 FAILED,錯誤是 com.vmware.vcIntegrity.lifecycle.TaskError.HealthCheckFailed。這是 nested 環境的 vSAN health 擋下 remediation。'),
    P('不要憑印象亂塞一堆 test id —— 先查出真正非綠的項目再靜音:'),
    CODE('# 查(VsanQueryVcClusterHealthSummary):48 項裡只有 3 項非綠\n'
       + '  com.vmware.vsan.health.test.nvmeonhcl                yellow\n'
       + '  com.vmware.vsan.health.test.perfsvcstatus            yellow\n'
       + '  com.vmware.vsan.health.test.vsanenablesupportinsight info\n\n'
       + '# 靜音(VsanHealthSetVsanClusterSilentChecks)只吃「短 id」\n'
       + '  <addSilentChecks>nvmeonhcl</addSilentChecks>\n'
       + '  <addSilentChecks>perfsvcstatus</addSilentChecks>\n'
       + '  <addSilentChecks>vsanenablesupportinsight</addSilentChecks>'),
    NOTE('🔴 靜音 API 吃的是短 id(nvmeonhcl),不是 health summary 回傳的 com.vmware.vsan.health.test.<id> 全名;而且清單裡只要有一個無效 id,**整批 500**:Invalid silent health check id: <x>。', 'FDECEA', C.red),
    NOTE('舊的 vsan-silence.ps1 用 Add-Type 做 ICertificatePolicy,在 PowerShell 7 會編不過(.NET Core 沒這型別)。改用 Invoke-WebRequest -SkipCertificateCheck;錯誤處理也要改,PS7 的 $_.Exception.Response 是 HttpResponseMessage,沒有 GetResponseStream(),要讀 $_.ErrorDetails.Message。', 'FFF6E5', C.amber),
    PB(),

    H2('4.6 容量:FTT=0 + 加碟'),
    P('變體 A 比變體 B 多了 NSX 與 SDDC Manager,installer 的容量檢查因此不過:Insufficient Storage. 3861.8 GB is less than the required 4664.0 GB。兩手並用解決。'),
    CODE(cli('vsan-capacity.txt')),
    NOTE('PowerCLI 13.5 **沒有 Add-VsanDisk**。要往既有 disk group 加 capacity disk 用 New-VsanDisk,而且參數是 -CanonicalName(不是 New-VsanDiskGroup 的 -DataDiskCanonicalName)。', 'FFF6E5', C.amber),
    ...F('22-vsan-8tb.png', '加碟後:vsanDatastore 7.81 TB / free 7.66 TB,容量檢查轉為 SUCCEEDED'),
    PB(),

    // ── 五 ──
    H1('五、兩種「沒有 overlay」的 spec 寫法'),
    H2('5.1 變體 A:部 NSX,但完全不設 overlay'),
    CODE('"workflowType": "VCF",\n'
       + '"vcenterSpec": {\n'
       + '    "vcenterHostname": "vcf-m02-vc01.home.lab",\n'
       + '    "useExistingDeployment": true,\n'
       + '    "sslThumbprint": "<vCenter SHA256 thumbprint>"\n'
       + '},\n'
       + '"nsxtSpec": {\n'
       + '    "useExistingDeployment": false,\n'
       + '    "nsxtManagerSize": "medium",\n'
       + '    "nsxtManagers": [ { "hostname": "vcf-m02-nsx01a.home.lab" } ],\n'
       + '    "vipFqdn": "vcf-m02-nsx01.home.lab",\n'
       + '    "skipNsxOverlayOverManagementNetwork": true\n'
       + '    // 🔴 刻意不給 transportVlanId / ipAddressPoolSpec\n'
       + '}'),
    P('取 vCenter thumbprint:'),
    CODE('echo | openssl s_client -connect <vc>:443 -servername <vc-fqdn> 2>/dev/null \\\n'
       + '  | openssl x509 -noout -fingerprint -sha256 | sed "s/^.*=//"'),
    H2('5.2 變體 B:VVF,完全不要 NSX'),
    P('不用猜 workflowType 的合法值 —— 丟一個假值讓 API 自己吐出來:'),
    CODE('POST /v1/sddcs/validations  {"workflowType":"BOGUS", ...}\n'
       + '  "The property \'workflowType\' in input Specification must be one among:\n'
       + '   [VCF, VCF_EXTEND, VVF, VCF_BOOTSTRAP]"'),
    P('把 workflowType 改成 VVF,並**整個省略 nsxtSpec 與 sddcManagerSpec**,installer 完全接受,validation 以 VALIDATION_VVF 執行,沒有任何「NSX 必填」的抱怨。所需元件清單裡也確實看不到 NSX 與 SDDC Manager:'),
    CODE(cli('validation-b-vvf.txt')),
    H2('5.3 精靈裡長什麼樣'),
    P('UI 的 Deployment Wizard 下拉直接有 VMware vSphere Foundation,不需要猜:'),
    ...F('12-deployment-wizard-menu.png', '下拉選單:VMware Cloud Foundation / VMware vSphere Foundation'),
    ...F('15-vvf-plan.png', 'VVF 精靈 Plan 階段 = converge 入口:「use your existing virtual infrastructure as building blocks … to converge them」+「I have an existing vCenter instance」'),
    ...F('17-vvf-network-options.png', 'VVF 的 Network Options 整頁沒有任何 NSX / TEP / overlay 選項'),
    NOTE('勾選「I have an existing vCenter instance」之後,Plan 的子步驟會少掉 Storage(沿用既有 vCenter 的儲存)。', 'FFF6E5', C.amber),
    PB(),

    H2('5.4 三輪 validation 修了什麼'),
    table(['驗證訊息', '原因與修法'],
      [['ESX thumbprint validation is not skipped and ESX host SSH keys not provided', 'nested lab 不提供 host SSH key → skipEsxThumbprintValidation = true'],
       ['Using auto-generated passwords where passwords were not provided', 'vspCluster / vidb / licenseServer 的 root + admin 密碼沒填 → 全部明寫(自動產生的事後登不進去)'],
       ['IP family mismatch: VCF services runtime, Fleet components and Instance components FQDNs resolve to different IP families', 'vspClusterSpec.instanceFqdn 指的名稱**根本沒有 DNS 記錄** → 補 A + PTR'],
       ['Could not retrieve binary for component ...', 'bundle 沒下載 → PATCH /v1/bundles/{id}'],
       ['Evacuate Offline VMs / Enable Quick Boot / Pre Remediation Power Action upgrade policy does not match default SDDC Manager ESXi upgrade policy', 'cluster 的 vLCM apply policy 與 SDDC Manager 預設不一致 → PUT /api/esx/settings/clusters/{c}/policies/apply 對齊'],
       ['Insufficient Storage', 'FTT=0 + 每台加一顆 1000 GB capacity disk']],
      [42, 58]),
    NOTE('🔴 bundle 下載的 payload **不是** {"operation":"DOWNLOAD"}(會 400 BUNDLE_DOWNLOAD_SPEC_INVALID_DATA),正解是 {"bundleDownloadSpec":{"downloadNow":true}}。', 'FDECEA', C.red),
    NOTE('🔴 SDDC Manager 的錯誤訊息把值寫成 DO_NOT_CHANGE_VMS_POWER,照抄下去 API 會收但讀回來變 _UNKNOWN;正確 enum 是 **DO_NOT_CHANGE_VMS_POWER_STATE**。', 'FDECEA', C.red),
    CODE(cli('validation-a-final.txt')),
    PB(),

    // ── 六 ──
    H1('六、送出 converge(逐步)'),
    P('本次走 installer UI 的「DEPLOY USING JSON SPEC」,用的是前面驗過的同一份 spec。'),
    ...F('30a-cancel-progress.png', '若之前開過 Deployment Wizard,首頁會變成「Deployment Wizard In Progress」。先按 CANCEL PROGRESS 清掉瀏覽器端的進度,DEPLOY USING JSON SPEC 才會回來'),
    ...F('32-spec-uploaded.png', 'Step 1 Upload:spec 上傳後解析出 Summary 六個區塊'),
    ...F('33-spec-summary.png', 'Summary 展開:VSP IP Pool、NSX Manager(medium / nsx01a / VIP nsx01)、SDDC Manager(New SDDC Manager Deployment)'),
    ...F('35-validation-result.png', 'Step 2 Validate & Deploy:11 項驗證,10 項 Succeeded、1 項 Warning'),
    ...F('36-warnings-acknowledged.png', '按 ACKNOWLEDGE ALL WARNINGS 之後,Warning 轉為 Acknowledged,NEXT 轉綠'),
    ...F('37-deploy-started.png', '送出後進入 progress viewer:5 個里程碑'),
    NOTE('唯一的 Warning 是 vLCM 合規提醒;先前兩個 upgrade policy 不一致的警告在對齊 policy 之後就消失了。', 'E8F5E9', C.green),
    PB(),

    // ── 七 ──
    H1('七、結果驗收'),
    H2('7.1 converge 本身'),
    CODE(cli('converge-milestones.txt')),
    H2('7.2 SDDC Manager 納管'),
    CODE(cli('sddcm-inventory.txt')),
    H2('7.3 🔑 「沒有 overlay」的證據鏈'),
    P('converge 完成後再驗一次,4 台 host 仍然是 vtepless:'),
    CODE(cli('nsx-vtepless.txt')),
    ...F('42-nsx-nodes-expanded.png', 'NSX UI:TEP IP Address 一律 Not Set、Tunnels Not Available,但 NSX Configuration Success、Status Up'),
    ...F('41-nsx-host-transport-nodes.png', 'Cluster 層級:4 Hosts Up、Prepared、NSX on DVPG = No'),
    ...F('43-nsx-transport-zones.png', 'Transport Zones:overlay TZ 掛了 4 個 transport node 且 Status Up —— 但因為沒有 TEP,實際上跑不了 overlay 流量'),
    NOTE('精確的說法是「**掛在 overlay TZ 上但 vtepless**」,不是「沒有 overlay transport zone」。TZ 存在、host 也在上面,只是沒有 TEP 就沒有 tunnel。', 'FFF6E5', C.amber),
    H2('7.4 元件上線狀態'),
    table(['元件', 'IP', 'HTTP'],
      [['SDDC Manager', '10.0.1.18', '301'],
       ['vCenter', '10.0.1.19', '200'],
       ['NSX Manager', '10.0.1.20', '302'],
       ['VCF Operations', '10.0.1.22', '200'],
       ['Fleet', '10.0.1.23', '404(Host-header 路由,正常)'],
       ['VSP / VIDB / License server', '10.0.0.172 / .174 / .175', '404 / 404 / 200'],
       ['Ops Collector', '10.0.1.24', '403'],
       ['VSP 節點', '10.0.0.232-235', '4 台 up']],
      [34, 30, 36]),
    PB(),

    // ── 八 ──
    H1('八、踩坑速查'),
    table(['#', '現象', '根因 / 解法'],
      [['1', 'cluster 裡的 host 名稱是 IP 不是 FQDN', 'vcsa-deploy 範本的 esxi.hostname 填了 IP。govc object.rename 補救,下次直接填 FQDN'],
       ['2', 'VDS cmdlet 全部噴 Field not found: VIObjectImpl._connectionId', 'PowerCLI 13.3 與 13.5 混裝。Import-Module -RequiredVersion 13.5.0.25380678(Sdk / Core / Vds / Storage 都要)'],
       ['3', '把 VM 搬到 VDS portgroup 後 vCenter 失聯', 'VDS 上那台主機沒有 uplink。直連 ESXi:govc vm.network.change -vm <vm> -net "VM Network" ethernet-0'],
       ['4', 'vLCM apply 回 SUCCEEDED 但主機沒升級', '看 last-apply-result 的 skipped_hosts。根因是 host DNS 把 10.0.0.1 排前面,解不到 vCenter FQDN'],
       ['5', 'vLCM remediate FAILED:Health Check failed', '先用 VsanQueryVcClusterHealthSummary 查出非綠項目,再用**短 id** 靜音;有無效 id 會整批 500'],
       ['6', 'PowerShell 7 跑不動舊的 vsan-silence 腳本', 'ICertificatePolicy 在 .NET Core 不存在 → -SkipCertificateCheck;錯誤讀 $_.ErrorDetails.Message'],
       ['7', 'Add-VsanDisk 不存在', '用 New-VsanDisk -VsanDiskGroup <dg> -CanonicalName <disk>'],
       ['8', 'pre_remediation_power_action 設了變 _UNKNOWN', '正確 enum 是 DO_NOT_CHANGE_VMS_POWER_STATE(SDDC Manager 訊息裡是截斷的)'],
       ['9', 'PATCH /v1/bundles/{id} 回 400', 'payload 要 {"bundleDownloadSpec":{"downloadNow":true}}'],
       ['10', 'IP family mismatch 看不懂', 'vspClusterSpec.instanceFqdn 的名稱沒有 DNS 記錄'],
       ['11', '監看腳本一直顯示 0/N', 'subtask 成功狀態是 POSTVALIDATION_COMPLETED_WITH_SUCCESS,不是 COMPLETED_WITH_SUCCESS'],
       ['12', 'Prepare-NestedESXi.ps1 卡住沒輸出', '沒給 -Password 時會跳 Get-Credential,非互動環境下會無聲卡死'],
       ['13', 'ESXi 9.x esxcli 不收遠端 bundle URL', 'Only server local file path is supported → 改走 vLCM 匯入 depot']],
      [5, 42, 53]),
    PB(),

    // ── 附錄 ──
    H1('附錄 A:指令彙整'),
    CODE('### 連線\n'
       + 'export GOVC_URL="https://<vc>" GOVC_USERNAME="administrator@vsphere.local" GOVC_PASSWORD="<pw>" GOVC_INSECURE=1\n'
       + 'export MSYS_NO_PATHCONV=1                      # Git-Bash 必加\n'
       + 'S=$(curl -sk -X POST -u "administrator@vsphere.local:<pw>" https://<vc>/api/session | tr -d \'"\')\n'
       + 'T=$(curl -sk -X POST https://<installer>/v1/tokens -H "Content-Type: application/json" \\\n'
       + '      -d \'{"username":"admin@local","password":"<pw>"}\' | jq -r .accessToken)\n\n'
       + '### vLCM 升級\n'
       + 'POST /api/esx/settings/depots/offline?vmw-task=true  {"source_type":"PULL","location":"<zip url>"}\n'
       + 'GET  /api/esx/settings/depot-content/base-images\n'
       + 'POST /api/esx/settings/clusters/{c}/software/drafts\n'
       + 'PUT  /api/esx/settings/clusters/{c}/software/drafts/{d}/software/base-image {"version":"..."}\n'
       + 'POST /api/esx/settings/clusters/{c}/software/drafts/{d}?action=commit&vmw-task=true\n'
       + 'POST /api/esx/settings/clusters/{c}/software?action=apply&vmw-task=true {"accept_eula":true}\n'
       + 'GET  /api/esx/settings/clusters/{c}/software/reports/last-apply-result   # 真相在這\n'
       + 'PUT  /api/esx/settings/clusters/{c}/policies/apply                       # 對齊 SDDC Manager 預設\n\n'
       + '### converge\n'
       + 'POST /v1/sddcs/validations     --data-binary @spec.json\n'
       + 'GET  /v1/sddcs/validations/{id}\n'
       + 'POST /v1/sddcs                 --data-binary @spec.json     # 或走 UI: DEPLOY USING JSON SPEC\n'
       + 'GET  /v1/sddcs/{id}                                         # sddcSubTasks 看進度\n'
       + 'PATCH /v1/bundles/{id}         {"bundleDownloadSpec":{"downloadNow":true}}\n\n'
       + '### 驗收\n'
       + 'GET  https://<sddcm>/v1/{domains,clusters,hosts,nsxt-clusters,vcenters}\n'
       + 'GET  https://<nsx>/api/v1/transport-nodes          # host_switch_spec.ip_assignment_spec\n'
       + 'GET  https://<nsx>/api/v1/transport-nodes/state\n'
       + 'GET  https://<nsx>/api/v1/transport-zones'),
    PB(),
    H1('附錄 B:CLI 輸出'),
    H2('B.1 converge 時間軸'),
    CODE(cli('converge-timeline.log')),
    H2('B.2 NSX transport zones'),
    CODE(cli('nsx-transport-zones.json').slice(0, 1800)),
  ] }]
});

Packer.toBuffer(doc).then(b => { fs.writeFileSync(OUT, b); console.log('written', OUT, b.length, 'bytes, figures:', figNo); });
