const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, ImageRun,
  Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType, AlignmentType
} = require('docx');

// 圖片與輸出路徑：預設用本資料夾的 img/，可用環境變數覆寫
const IMG = process.env.ESXI_DOC_IMG || path.join(__dirname, 'img');
const OUT = process.env.ESXI_DOC_OUT || path.join(__dirname, 'ESXi-9.1-Upgrade-Guide.docx');
const FONT = 'Microsoft JhengHei';
const MONO = 'Consolas';

let figN = 0;
function h(text, level) { return new Paragraph({ heading: level, spacing: { before: 260, after: 120 }, children: [new TextRun({ text, font: FONT, bold: true })] }); }
function p(text, opts = {}) { return new Paragraph({ spacing: { after: 100 }, children: [new TextRun({ text, font: FONT, size: opts.size || 22, bold: !!opts.bold, italics: !!opts.italics, color: opts.color })] }); }
function bullet(text, level = 0) { return new Paragraph({ bullet: { level }, spacing: { after: 40 }, children: [new TextRun({ text, font: FONT, size: 22 })] }); }
function num(text) { return new Paragraph({ numbering: { reference: 'steps', level: 0 }, spacing: { after: 60 }, children: [new TextRun({ text, font: FONT, size: 22 })] }); }
function code(lines) {
  return lines.map((ln, i) => new Paragraph({
    spacing: { after: i === lines.length - 1 ? 140 : 0, before: i === 0 ? 60 : 0 },
    shading: { type: ShadingType.CLEAR, color: 'auto', fill: 'F4F4F4' },
    children: [new TextRun({ text: ln || ' ', font: MONO, size: 18 })]
  }));
}
function note(text, color) {
  return new Paragraph({ spacing: { before: 80, after: 140 }, shading: { type: ShadingType.CLEAR, color: 'auto', fill: 'FDF3E7' },
    children: [new TextRun({ text, font: FONT, size: 20, color: color || 'B03A2E' })] });
}
function pngSize(fp) {
  const b = fs.readFileSync(fp).subarray(16, 24);
  return { w: b.readUInt32BE(0), h: b.readUInt32BE(4) };
}
function fig(file, desc, width) {
  width = width || 580;
  figN++;
  const fp = path.join(IMG, file);
  const out = [];
  if (fs.existsSync(fp)) {
    const s = pngSize(fp);
    const hgt = Math.round(width * s.h / s.w);
    out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 80, after: 20 },
      children: [new ImageRun({ type: 'png', data: fs.readFileSync(fp), transformation: { width: width, height: hgt },
        border: { color: 'BBBBBB', space: 1, style: BorderStyle.SINGLE, size: 6 } })] }));
  } else {
    out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 20 }, children: [new TextRun({ text: '[圖待補：' + file + ']', font: FONT, italics: true, color: '999999' })] }));
  }
  out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 180 }, children: [new TextRun({ text: '圖 ' + figN + '　' + desc, font: FONT, size: 18, italics: true, color: '555555' })] }));
  return out;
}
function cell(text, o) {
  o = o || {};
  return new TableCell({ width: { size: o.w, type: WidthType.DXA }, shading: o.shade ? { type: ShadingType.CLEAR, color: 'auto', fill: o.shade } : undefined,
    margins: { top: 50, bottom: 50, left: 90, right: 90 },
    children: String(text).split('\n').map(t => new Paragraph({ children: [new TextRun({ text: t, font: FONT, size: 19, bold: !!o.bold })] })) });
}
function table(widths, header, rows) {
  const total = widths.reduce((a, b) => a + b, 0);
  const trs = [new TableRow({ tableHeader: true, children: header.map((t, i) => cell(t, { bold: true, shade: 'DDE6F0', w: widths[i] })) })];
  rows.forEach(r => trs.push(new TableRow({ children: r.map((t, i) => cell(t, { w: widths[i] })) })));
  return new Table({ columnWidths: widths, width: { size: total, type: WidthType.DXA }, rows: trs });
}
function spacer() { return new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text: '' })] }); }

const c = [];

/* ---------- 封面 ---------- */
c.push(new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'ESXi 9.1 升級實作手冊', font: FONT, bold: true, size: 40, color: '1F3864' })] }));
c.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: '三條升級路徑：esxcli offline bundle / vCenter vLCM image / ISO 開機升級', font: FONT, size: 24, color: '555555' })] }));
c.push(new Paragraph({ spacing: { after: 240 }, children: [new TextRun({ text: '實測日期 2026-09-29　·　來源版本 ESXi 9.1.0.0 build 25370933　·　目標版本 ESXi 9.1.1.0 build 25714478　·　三條路徑全數升級成功', font: FONT, size: 18, italics: true, color: '777777' })] }));

/* ---------- 0 ---------- */
c.push(h('0. 這份文件解決什麼問題', HeadingLevel.HEADING_1));
c.push(p('ESXi 主機要升級，可走的路不只一條，而「你能走哪一條」取決於主機現在被誰管：是 VCF 的 SDDC Manager、是一台單純的 vCenter、還是誰都沒接。走錯路的代價不是失敗，是白做一輪前置作業才發現產品規則擋死。'));
c.push(p('本文把三條路徑各自跑過一次完整流程並逐步截圖，並在附錄 A 收錄「VCF 納管規則」——那些規則決定你到底能不能用 LCM 升級，是選路徑的前提。'));
c.push(spacer());
c.push(p('三條路徑怎麼選：', { bold: true }));
c.push(table([1900, 3000, 2400, 1900],
  ['路徑', '適用情境', '前置需求', '主機中斷'],
  [
    ['A. esxcli\noffline bundle', '主機沒接 vCenter／接了但脫離 LCM 管理；\n或 CPU 不受支援要強制升', 'offline bundle（-depot.zip）\n要能放到主機讀得到的路徑', '進 MM → 重開機'],
    ['B. vCenter vLCM\nimage', '主機掛在 vCenter 下（叢集或獨立主機），\n要走 vCenter 的生命週期管理', 'base image 已在 vLCM depot；\n主機已加入 vCenter', '自動進 MM → 重開機\n→ 自動退 MM'],
    ['C. ISO 開機升級', '沒有 vCenter、沒有 depot 服務；\n或主機狀態異常要用安裝媒體修', '可開機的安裝 ISO\n＋ console 存取', '整段離線\n（人工在 console 操作）']
  ]));
c.push(spacer());
c.push(note('⚠ 本文所有實測在 nested lab 環境進行，CPU 為 Broadcom 已列 discontinued 的 Xeon E5-2682 v4（Broadwell）。文中的 CPU 覆寫步驟會讓環境脫離受支援狀態，正式環境請用受支援硬體並走官方流程。'));

/* ---------- 1 ---------- */
c.push(h('1. 測試環境', HeadingLevel.HEADING_1));
c.push(table([2200, 2500, 2300, 2200],
  ['主機', 'FQDN / IP', '納管狀態', '用來示範'],
  [
    ['vcf-m02-esx11', 'vcf-m02-esx11.home.lab\n10.0.1.11', '未接任何 vCenter', '路徑 A（esxcli）'],
    ['vcf-m02-esx12', 'vcf-m02-esx12.home.lab\n10.0.1.12', 'vCenter 下的「獨立主機」\n（不在叢集裡）', '路徑 B（vLCM image）'],
    ['vcf-m02-esx13', 'vcf-m02-esx13.home.lab\n10.0.1.13', '未接任何 vCenter', '路徑 C（ISO）']
  ]));
c.push(spacer());
c.push(bullet('三台皆為 nested ESXi，4 vCPU / 16 GB，從同一份 ESXi 9.1.0 OVA 範本部署，起點版本完全相同。'));
c.push(bullet('vCenter：vcf-m02-vc01.home.lab（9.1.1.0.25712839），本身由 VCF 管理。'));
c.push(bullet('升級素材：VMware-ESXi-9.1.1.0.25714478-depot.zip（offline bundle）與 VMware-VMvisor-Installer-9.1.1.0.25714478.x86_64.iso（原廠安裝 ISO）。'));
c.push(note('🔑 取得素材的一個實用發現：VCF depot catalog（productVersionCatalog.json）對 9.1.1 的 ESX_HOST 只列出 ISO、沒有列 -depot.zip，但同一個目錄下 -depot.zip 其實是存在的、抓得到 —— 前提是 token 要放在 URL 的 path 裡：https://dl.broadcom.com/<TOKEN>/PROD/COMP/ESX_HOST/<檔名>。下載工具走的是不帶 token 的 URL，所以才會 403。', '1F618D'));

/* ---------- 2 路徑 A ---------- */
c.push(h('2. 路徑 A — esxcli software profile update（offline bundle）', HeadingLevel.HEADING_1));
c.push(p('這是最不依賴周邊服務的一條路：不需要 vCenter、不需要 vLCM、不需要 SDDC Manager，只要主機拿得到 offline bundle。也是 CPU 不受支援時最容易繞過的一條（--no-hardware-warning）。'));

c.push(h('2.1 升級前確認', HeadingLevel.HEADING_2));
c.push(p('登入 ESXi Host Client（https://<主機>/ui/），Host → Summary 確認目前版本。本例為 ESXi 9.1.0.0.25370933，State 顯示「Normal (not connected to any vCenter Server)」。'));
fig('a01-host-before.png', '升級前：esx11 為 ESXi 9.1.0.0.25370933，未接 vCenter').forEach(x => c.push(x));

c.push(h('2.2 把 offline bundle 放到主機讀得到的地方', HeadingLevel.HEADING_2));
c.push(p('esxcli 的 -d 參數吃兩種來源：遠端 depot 的 index.xml（URL），或本機路徑上的 offline bundle .zip。本次實測踩到兩個網路擋點，最後走本機路徑才通 —— 而這也正是離線現場最常見的做法。'));
c.push(spacer());
c.push(p('擋點 1：自己在跳板機起的 HTTP server，主機連不到。', { bold: true }));
c.push(bullet('在 Windows 跳板機（10.0.0.200）用 python -m http.server 8099 提供解壓後的 depot，從跳板機本機 curl 得到 200，但 ESXi 主機上 esxcli 直接 hang 住。'));
c.push(bullet('原因是 Windows 防火牆擋掉 inbound。'));
c.push(spacer());
c.push(p('擋點 2：改指 lab 既有的 depot server（10.0.0.61:8888），一樣連不到。', { bold: true }));
c.push(bullet('從跳板機 curl http://10.0.0.61:8888/... 得到 200，但主機上 nc -z 10.0.0.61 8888 失敗。'));
c.push(bullet('原因是 ESXi 自己的防火牆：outbound 預設只放行 httpClient ruleset 的 80／443，非標準埠一律擋。'));
c.push(note('🔴 所以「offline bundle 只吃本機路徑」這句話在多數現場其實是結果而不是限制 —— 真正的限制是 ESXi outbound 防火牆只開 80/443。要走 URL，depot 就得架在 80 或 443 上。'));
c.push(spacer());
c.push(p('可行做法：在主機本機建一個 VMFS 資料存放區，把 bundle 傳上去。', { bold: true }));
c.push.apply(c, code([
  '# 1) 在一顆空白本機磁碟上建 VMFS（本例用 8GB 那顆）',
  'D=/vmfs/devices/disks/eui.a96c932258a6212c000c2969fdcaa0bd',
  'partedUtil mklabel $D gpt',
  'END=$(partedUtil getptbl $D | tail -1 | awk \'{print $1*$2*$3-1}\')',
  'partedUtil setptbl $D gpt "1 2048 $END AA31E02A400F11DB9590000C2911D1B8 0"',
  'vmkfstools -C vmfs6 -S esx11-local ${D}:1',
  '',
  '# 2) 從跳板機把 offline bundle 傳上去',
  'pscp VMware-ESXi-9.1.1.0.25714478-depot.zip root@10.0.1.11:/vmfs/volumes/esx11-local/'
]));

c.push(h('2.3 執行升級', HeadingLevel.HEADING_2));
c.push.apply(c, code([
  '# 先查 bundle 裡有哪些 image profile（名稱要完全吻合）',
  'esxcli software sources profile list \\',
  '  -d /vmfs/volumes/esx11-local/VMware-ESXi-9.1.1.0.25714478-depot.zip',
  '#   -> ESXi-9.1.1.0-25714478-standard / ESXi-9.1.1.0-25714478-no-tools',
  '',
  'esxcli system maintenanceMode set --enable true',
  '',
  'esxcli software profile update \\',
  '  -d /vmfs/volumes/esx11-local/VMware-ESXi-9.1.1.0.25714478-depot.zip \\',
  '  -p ESXi-9.1.1.0-25714478-standard \\',
  '  --no-hardware-warning',
  '',
  'reboot'
]));
c.push(p('指令成功會回：', { bold: true }));
c.push.apply(c, code([
  'Update Result',
  '   Message: The update completed successfully, but the system needs to be',
  '            rebooted for the changes to be effective.',
  '   VIBs Installed: ... esx-base_9.1.1-0.25714478 ...',
  '   VIBs Removed:   ... esx-base_9.1.0-0.25370933 ...',
  '   VIBs Skipped:   ...（主機上沒有的驅動，維持原狀）',
  '   Reboot Required: true'
]));
c.push(note('⚠ 如果這道指令因為任何原因卡住（例如 depot URL 連不到），它會佔住 esximage 的鎖，之後任何 esxcli software ... 都會跟著 hang。要先把那串 sh / python 行程 kill -9 掉才能繼續：ps -c | grep esxcli'));

c.push(h('2.4 重開機後驗證', HeadingLevel.HEADING_2));
c.push.apply(c, code([
  'esxcli system version get',
  '#   Version: 9.1.1   Build: Releasebuild-25714478',
  'esxcli system maintenanceMode set --enable false'
]));
fig('a02-host-after.png', '升級後：esx11 為 ESXi 9.1.1.0.25714478，已退出維護模式').forEach(x => c.push(x));
c.push(note('✅ 路徑 A 實測結果：Broadwell（已 discontinued）用 --no-hardware-warning 走 profile update 完全不需要額外加 allowLegacyCPU 開機參數。CPU 封鎖是在 ISO 安裝程式層做的檢查，esxcli 升級路徑不會在開機時硬擋。', '1E8449'));

/* ---------- 3 路徑 B ---------- */
c.push(h('3. 路徑 B — vCenter vLCM image（獨立主機）', HeadingLevel.HEADING_1));
c.push(p('vSphere 9.1 的獨立主機（不在叢集裡、直接掛在 datacenter 下的 host）一樣能用 vLCM image 管理與升級，不必為了升級而先把它塞進一個叢集。'));

c.push(h('3.1 前置', HeadingLevel.HEADING_2));
c.push(bullet('目標 base image（本例 9.1.1.0.25714478）必須已經在 vLCM 的 depot 裡。可在 Lifecycle Manager → Image Library 確認，或用 API：GET /api/esx/settings/depot-content/base-images。'));
c.push(bullet('主機已加入 vCenter（本例用 govc host.add 加到 /m01-dc01/host 之下，成為 ComputeResource 而非叢集成員）。'));
c.push(note('🔑 值得記一筆：把主機加進「由 VCF 管理的 vCenter」時，它會自動被套上 Management-Domain-ESXi-Personality 這個 image（也就是管理域目前的 9.1.1 映像），不需要手動 Assign Image。所以加完主機，desired image 就已經是 9.1.1 了。', '1F618D'));
c.push(spacer());
c.push(p('升級前主機狀態：Hypervisor 顯示 VMware ESXi 9.1.0.0.25370933。'));
fig('b01-host-summary-before.png', '升級前：esx12 掛在 m01-dc01 下的獨立主機，版本 9.1.0.0.25370933').forEach(x => c.push(x));

c.push(h('3.2 檢視主機的 image（Updates → Image）', HeadingLevel.HEADING_2));
c.push(p('選取主機 → Updates 分頁 → 左側 Hosts → Image。可見 Image Name、ESXi Version、Vendor Addon、Firmware and Drivers Addon 與 Components。右上 EDIT 可改用別的 image，ASSIGN IMAGE 可換一份既有 image。'));
fig('b02-updates-tab.png', '主機 Updates → Image：desired image 為 9.1.1.0.25714478').forEach(x => c.push(x));

c.push(h('3.3 檢查符合性（Check Compliance）', HeadingLevel.HEADING_2));
c.push(p('點 Image Compliance 區塊右上的 CHECK COMPLIANCE，vCenter 會要求主機去比對目前狀態與 desired image 的差異。'));
fig('b03-compliance-result.png', '符合性檢查結果：Host is out of compliance with the image').forEach(x => c.push(x));
c.push(p('本次檢查回報的警告（正式環境要逐條確認）：'));
c.push(bullet('ESXi 不支援此主機上的 CPU。可以覆寫和強制修復，但官方不支援也不建議（KB 82794）。'));
c.push(bullet('主機上的 nested-esxi-customization(9.1.0-1.0.0) VIB 在映像中遺失，將在修復期間從主機中移除（KB 90188）。要保留就得把等效元件包進 image。'));
c.push(bullet('主機將在修復期間重新開機；主機支援 Quick Boot。'));
c.push(spacer());
c.push(p('往下捲可以看到 Software compliance 的逐項差異，這是升級前最值得截給客戶看的一張表：'));
fig('b04-software-drift.png', 'Software compliance：Host Version 9.1.0.0.25370933 → Image Version 9.1.1.0.25714478').forEach(x => c.push(x));

c.push(h('3.4 執行修復（Remediate）', HeadingLevel.HEADING_2));
c.push(p('點 REMEDIATE，會先跳出「Review Remediation Impact」讓你確認影響範圍：主機將安裝有映像、進入維護模式、重新開機、結束維護模式。'));
fig('b05-remediate-dialog.png', 'Review Remediation Impact：影響範圍與 Quick Boot 說明').forEach(x => c.push(x));
c.push(note('🔑 授權合約在這裡：對話框左下角的「I accept the Foundation Agreement」。純 API 可以把 desired image 設好，但 remediate 之前的合約同意只能在 UI 勾 —— 想全自動化的人會卡在這一哩。'));
c.push(spacer());
c.push(p('左側切到「Applicable remediation settings」可檢視這次修復會套用的設定（VM 電源狀態、重試原則、Quick Boot）。'));
fig('b06-remediation-settings.png', 'Applicable remediation settings：VM 電源狀態／重試原則／Quick Boot').forEach(x => c.push(x));
c.push(p('確認無誤後按 START REMEDIATION。畫面回到 Image Compliance，顯示 Remediating host…，下方 Recent Tasks 可看到「修復主機」的進度。'));
fig('b07-remediation-running.png', '修復進行中（主機會自動進入維護模式並重新開機）').forEach(x => c.push(x));

c.push(h('3.5 完成與驗證', HeadingLevel.HEADING_2));
c.push(p('本次實測從 13:14 開始、13:19 結束，約 5 分鐘（nested 環境、單主機、無 VM 需要疏散）。完成後 Image Compliance 轉為 Host is compliant with the image。'));
fig('b08-compliant-after.png', '修復完成：Host is compliant with the image').forEach(x => c.push(x));
c.push(p('回到 Summary 確認 Hypervisor 版本已是 9.1.1.0.25714478，State 為「已連線」且已退出維護模式。'));
fig('b09-host-summary-after.png', '升級後：esx12 為 ESXi 9.1.1.0.25714478').forEach(x => c.push(x));

/* ---------- 4 路徑 C ---------- */
c.push(h('4. 路徑 C — ISO 開機升級（保留既有設定與 VMFS）', HeadingLevel.HEADING_1));
c.push(p('沒有 vCenter、沒有 depot 服務，或主機狀態已經壞到 esxcli 跑不動時，用安裝 ISO 開機是最後也最可靠的一條路。安裝程式偵測到磁碟上已有 ESXi 時會提供 Upgrade 選項，保留既有設定與資料存放區。'));

c.push(h('4.1 準備媒體並從 CD 開機', HeadingLevel.HEADING_2));
c.push(bullet('本例用原廠 ISO VMware-VMvisor-Installer-9.1.1.0.25714478.x86_64.iso（733,470,720 bytes），不用自組的 OEM ISO —— nested 主機的 Model 是 VMware20,1，套 OEM addon 容易撞硬體判斷。'));
c.push(bullet('實體機用 iDRAC / iLO 掛 virtual media；本例是 nested VM，在外層 vCenter 掛 datastore ISO 並把開機順序改成 CD 優先。'));
c.push.apply(c, code([
  'govc device.cdrom.insert -vm <VM> -device cdrom-16000 -ds ForNFS \\',
  '    "iso/VMware-VMvisor-Installer-9.1.1.0.25714478.x86_64.iso"',
  'govc device.connect -vm <VM> cdrom-16000',
  'govc device.boot    -vm <VM> -order cdrom,disk',
  'govc vm.power -off -force <VM> && govc vm.power -on <VM>'
]));
fig('c01-boot.png', '從 ISO 開機，載入 ESXi installer', 460).forEach(x => c.push(x));

c.push(h('4.2 安裝程式逐步', HeadingLevel.HEADING_2));
c.push(num('Welcome 畫面 → 按 Enter 繼續。'));
fig('c02-welcome.png', 'Welcome to the VMware ESXi 9.1.1 Installation', 460).forEach(x => c.push(x));
c.push(num('End User License Agreement（Foundation Agreement）→ 按 F11 Accept and Continue。'));
fig('c03-eula.png', 'EULA：F11 接受並繼續', 460).forEach(x => c.push(x));
c.push(num('Select a Disk to Install or Upgrade → 選「已經裝有 ESXi 的那顆開機碟」（本例 32 GiB），按 Enter。標示 * 代表該磁碟含 VMFS 分割區。'));
fig('c04-select-disk.png', '選擇磁碟：挑既有的開機碟（32 GiB）', 460).forEach(x => c.push(x));
c.push(num('ESXi Found → 選「Upgrade」（預設已選），按 Enter。選 Install 會清掉既有設定，務必確認。'));
fig('c05-upgrade-choice.png', 'ESXi Found：(X) Upgrade / ( ) Install', 460).forEach(x => c.push(x));
c.push(note('⚠ 9.1.1 安裝程式的選項文字就是簡單的「Upgrade / Install」，不再是舊版那種「Upgrade ESXi, preserve VMFS datastore」的長字串。照舊文件找字串會找不到。'));
c.push(num('系統掃描警告。本例出現 CPU_SUPPORT OVERRIDEWARNING（Broadwell 不受 9.1.1 支援，KB 82794）→ 按 Enter 繼續。'));
fig('c06-cpu-warning.png', '系統掃描警告：CPU_SUPPORT OVERRIDEWARNING（KB 82794）', 460).forEach(x => c.push(x));
c.push(num('確認要強制安裝 → 按 Enter Force Installation。（受支援硬體不會出現這兩步。）'));
fig('c07-force-install.png', 'Force Installation 確認', 460).forEach(x => c.push(x));
c.push(num('Confirm Upgrade → 確認來源與目標版本正確（本例 from ESXi 9.1.0 to ESXi 9.1.1）→ 按 F11 Upgrade。'));
fig('c08-confirm-upgrade.png', 'Confirm Upgrade：from ESXi 9.1.0 to ESXi 9.1.1', 460).forEach(x => c.push(x));
c.push(num('Upgrade Complete → 先把安裝媒體退掉（實體機退 virtual media；nested 用 govc device.disconnect 並把開機順序改回 disk 優先），再按 Enter Reboot。'));
fig('c09-upgrade-complete.png', 'Upgrade Complete：This system has been upgraded to ESXi 9.1.1 successfully', 460).forEach(x => c.push(x));
c.push(note('⚠「Remove the installation media before rebooting」不是客套話。忘了退片，主機會再次從 ISO 開機，又跑一次安裝程式。'));

c.push(h('4.3 驗證', HeadingLevel.HEADING_2));
c.push(p('重開機後 DCUI 直接顯示新版本，IP 與主機名保留。'));
fig('c10-dcui-after.png', '升級後 DCUI：VMware ESXi 9.1.1.0.25714478，IP／主機名皆保留', 460).forEach(x => c.push(x));
c.push.apply(c, code([
  'esxcli system version get',
  '#   Version: 9.1.1   Build: Releasebuild-25714478'
]));

/* ---------- 5 比較 ---------- */
c.push(h('5. 三條路徑實測比較', HeadingLevel.HEADING_1));
c.push(table([1500, 2400, 2400, 2400],
  ['', 'A. esxcli', 'B. vLCM image', 'C. ISO'],
  [
    ['實測結果', '9.1.0 → 9.1.1 成功', '9.1.0 → 9.1.1 成功', '9.1.0 → 9.1.1 成功'],
    ['需要 vCenter', '否', '是', '否'],
    ['需要 depot 服務', '否（本機 zip 即可）', '是（base image 要在 depot）', '否'],
    ['可否遠端無人操作', '可（SSH）', '可，但同意合約那步要 UI', '否，要 console'],
    ['維護模式', '自己進、自己退', 'vLCM 自動進退', '不適用（整台離線）'],
    ['CPU 不受支援', '--no-hardware-warning', 'UI 可覆寫強制修復', 'Enter 兩次強制安裝'],
    ['本次耗時', '傳檔＋安裝數分鐘＋重開機', '約 5 分鐘（含重開機）', '安裝不到 1 分鐘＋重開機']
  ]));

/* ---------- 6 卡點 ---------- */
c.push(h('6. 常見卡點速查', HeadingLevel.HEADING_1));
c.push(table([3600, 5100],
  ['症狀', '原因 / 解法'],
  [
    ['compliance check 失敗：Failed to connect to depot ... urlopen error [Errno -2] Name or service not known（KB 313508）',
     '主機解不到 vCenter 的 FQDN。檢查 esxcli network ip dns server list —— 本次是 OVA 先 DHCP、guestinfo 再補，結果變成兩台 DNS（10.0.0.1 在前解不到 home.lab）。移掉錯的那台即可。'],
    ['esxcli software profile update 掛住不動',
     'depot URL 連不到。ESXi outbound 防火牆預設只放行 80/443，非標準埠會被擋；跳板機自架的 HTTP server 還可能被 Windows 防火牆擋 inbound。改用本機 zip 路徑。'],
    ['後續每一道 esxcli software ... 都跟著 hang',
     '前一道卡住的指令佔著 esximage 鎖。ps -c | grep esxcli 找出那串 sh/python，kill -9。'],
    ['ESXi 不支援此主機上的 CPU（KB 82794）',
     '升級路徑是警告不是硬擋，可覆寫。實測 Broadwell 走 esxcli 與 ISO 兩條路都不需要額外加 allowLegacyCPU。'],
    ['VIB 在映像中遺失，將被移除（KB 90188）',
     '主機上有 image 裡沒有的 VIB（本例 nested-esxi-customization）。要保留就把等效元件加進 image，否則 remediate 會移除它。'],
    ['ISO 升完重開機又跑進安裝程式',
     '沒退安裝媒體，或開機順序還是 CD 優先。'],
    ['找不到「Upgrade ESXi, preserve VMFS datastore」選項',
     '9.1.1 安裝程式的文字已簡化為 Upgrade / Install。']
  ]));

/* ---------- 附錄 A ---------- */
c.push(h('附錄 A：VCF 納管規則（決定你能不能用 LCM 升）', HeadingLevel.HEADING_1));
c.push(p('如果目標是「把主機交給 VCF 的 SDDC Manager 管，之後用 LCM 升級」，下面這些是實測踩到的產品規則。它們不是參數問題，是規則本身擋死，值得在規劃階段就講清楚。'));

c.push(h('A.1 commission 的 ESXi build 必須「完全等於」BOM 版本', HeadingLevel.HEADING_2));
c.push(p('不是「大於等於」。主機比 VCF 當下的 BOM 新或舊都會被擋（CLUSTER_IMAGE_ESXI_VERSION_NOT_VALID）。做法是先把主機升／降到剛好等於 BOM 再 commission。要取得那個特定 build 的 depot zip，用第 1 章提到的 token-in-path URL。'));

c.push(h('A.2 VCF 不允許單主機叢集', HeadingLevel.HEADING_2));
c.push(p('所以「把一台單機 commission 進 VCF、建成單主機叢集、再用 LCM 升級」這條路走不通。單機只能走本文的路徑 B（vCenter vLCM）或路徑 C（ISO）。'));

c.push(h('A.3 帶著開機中 VM 的主機要進 cluster', HeadingLevel.HEADING_2));
c.push(p('可以處理，而且不必刪 VM —— 把 VM 從主機 unregister（取消註冊）即可通過驗證，加入叢集後再註冊回來。另外 vmk0 只能有 Management tag，帶其他 tag 會被擋。'));

c.push(h('A.4 1G NIC 主機能不能 commission', HeadingLevel.HEADING_2));
c.push(p('預設會被擋：Host must have minimum two 10Gig NIC(s)。檢查程式在 operationsmanager 的 HostHardwareValidator，讀 enable.speed.of.physical.nics.validation。'));
c.push.apply(c, code([
  '# 放在對的服務的設定檔裡，否則不會生效',
  '/etc/vmware/vcf/operationsmanager/application.properties   # Day-N commission 進 free pool',
  '/etc/vmware/vcf/domainmanager/application.properties       # bring-up / 建叢集 / 加主機',
  '',
  'enable.speed.of.physical.nics.validation=false',
  '',
  'systemctl restart operationsmanager   # 或 domainmanager'
]));
c.push(note('⚠ 同一把 property 由 domainmanager 與 operationsmanager 各自讀自己的設定檔，放錯檔案會「改了卻沒用」。'));

c.push(h('A.5 單條 uplink 的 VDS', HeadingLevel.HEADING_2));
c.push(p('9.1 預設就支援，不必改參數（feature.vcf.VGL-29478.lag-and-single-pnic 預設為 true）。hostNetworkSpec.vmNics 只給一條是走得通的設計。但要注意：uplink 沒有 link（實體斷線）會在別的地方擋下來，那是連線檢查不是數量檢查。'));

/* ---------- 附錄 B ---------- */
c.push(h('附錄 B：本次測試環境怎麼建的', HeadingLevel.HEADING_1));
c.push(p('留給要重現這份測試的人。'));
c.push.apply(c, code([
  '# 1) 從 OVA 部三台乾淨的 9.1.0 nested 主機（thin、ForNFS、Trunk-Nobinding）',
  'govc import.ova -folder /Datacenter/vm/VCF -host 10.0.0.95 \\',
  '    -options spec-<host>.json Nested_ESXi9.1.0.0_Appliance_Template_v1.0.ova',
  'govc vm.change -vm <VM> -c 4 -m 16384',
  'govc vm.power -on <VM>',
  '',
  '# 2) 建 DNS A + PTR（在 DNS server 上）',
  'Add-DnsServerResourceRecordA -Name <host> -ZoneName home.lab \\',
  '    -IPv4Address <ip> -CreatePtr',
  '',
  '# 3) 修 DNS（OVA 會留下 DHCP 給的那台，解不到 home.lab）',
  'esxcli network ip dns server remove --server=10.0.0.1',
  '',
  '# 4) 路徑 B 用：把主機加進 vCenter 成為獨立主機',
  'govc host.add -hostname <fqdn> -username root -password <pw> \\',
  '    -noverify -folder /m01-dc01/host'
]));
c.push(spacer());
c.push(p('文件版本：2026-09-29　·　內容依據本次 lab 實測，所有截圖皆取自該次流程。', { size: 18, italics: true, color: '777777' }));

/* ---------- 輸出 ---------- */
const doc = new Document({
  numbering: { config: [{ reference: 'steps', levels: [{ level: 0, format: 'decimal', text: '%1.', alignment: AlignmentType.START }] }] },
  styles: { default: { document: { run: { font: FONT, size: 22 } } } },
  sections: [{ properties: { page: { margin: { top: 1100, bottom: 1100, left: 1100, right: 1100 } } }, children: c }]
});
Packer.toBuffer(doc).then(b => {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, b);
  console.log('WROTE', OUT, b.length, 'bytes,', figN, 'figures');
});
