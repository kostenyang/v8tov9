const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, ImageRun,
  Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType, AlignmentType
} = require('docx');

const IMG = 'E:/9.1/docs/vc9-upgrade/img';
const OUT = 'E:/9.1/docs/vc9-upgrade/vc9-0-to-9-1-upgrade-walkthrough.docx';
const FONT = 'Microsoft JhengHei';

let figN = 0;
function h(text, level) { return new Paragraph({ heading: level, spacing: { before: 240, after: 120 }, children: [new TextRun({ text, font: FONT, bold: true })] }); }
function p(text, opts = {}) { return new Paragraph({ spacing: { after: 100 }, children: [new TextRun({ text, font: FONT, size: opts.size || 22, bold: !!opts.bold, italics: !!opts.italics, color: opts.color })] }); }
function bullet(text) { return new Paragraph({ bullet: { level: 0 }, spacing: { after: 40 }, children: [new TextRun({ text, font: FONT, size: 22 })] }); }
function fig(file, desc) {
  figN++;
  const fp = path.join(IMG, file);
  const out = [];
  if (fs.existsSync(fp)) {
    const w = 600, hgt = Math.round(600 * 1033 / 1710);
    out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 80, after: 20 },
      children: [new ImageRun({ type: 'png', data: fs.readFileSync(fp), transformation: { width: w, height: hgt },
        border: { color: 'BBBBBB', space: 1, style: BorderStyle.SINGLE, size: 6 } })] }));
  } else {
    out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 20 }, children: [new TextRun({ text: `[圖待補：${file}]`, font: FONT, italics: true, color: '999999' })] }));
  }
  out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 160 }, children: [new TextRun({ text: `圖 ${figN}　${desc}`, font: FONT, size: 18, italics: true, color: '555555' })] }));
  return out;
}
function cell(text, { bold = false, shade = null, w } = {}) {
  return new TableCell({ width: { size: w, type: WidthType.DXA }, shading: shade ? { type: ShadingType.CLEAR, color: 'auto', fill: shade } : undefined,
    margins: { top: 40, bottom: 40, left: 80, right: 80 }, children: [new Paragraph({ children: [new TextRun({ text, font: FONT, size: 20, bold })] })] });
}
function compareTable() {
  const W = [2600, 3400, 3360]; const total = W.reduce((a, b) => a + b, 0);
  return new Table({ columnWidths: W, width: { size: total, type: WidthType.DXA }, rows: [
    new TableRow({ tableHeader: true, children: [cell('情境', { bold: true, shade: 'DDE6F0', w: W[0] }), cell('官方方法', { bold: true, shade: 'DDE6F0', w: W[1] }), cell('媒體', { bold: true, shade: 'DDE6F0', w: W[2] })] }),
    new TableRow({ children: [cell('跨大版 (8.0 → 9.0)', { w: W[0] }), cell('Upgrade：migration-based（部新 appliance→暫時 IP→遷移→接管）', { w: W[1] }), cell('VMware-VCSA-all-X.iso 安裝器', { w: W[2] })] }),
    new TableRow({ children: [cell('同版 minor (9.0 → 9.1)', { bold: true, w: W[0] }), cell('Update / Patch：in-place（VAMI 或 software-packages），可搭 RDU', { bold: true, shade: 'EAF3E0', w: W[1] }), cell('-updaterepo.zip / patch repo URL', { shade: 'EAF3E0', w: W[2] })] }),
  ] });
}

const c = [];
c.push(new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'vCenter Server 9.0.2 → 9.1 手動升級教學', font: FONT, bold: true, size: 36, color: '1F3864' })] }));
c.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: 'In-place update via VAMI（官方對 minor 升級的建議法）', font: FONT, size: 24, color: '555555' })] }));
c.push(new Paragraph({ spacing: { after: 200 }, children: [new TextRun({ text: '測試環境：vc9test.home.lab (10.0.0.110) · standalone embedded vCenter · 2026-07-27 · 實測結果：升級成功', font: FONT, size: 18, italics: true, color: '777777' })] }));

c.push(h('0. 觀念：Upgrade vs Update（官方定義）', HeadingLevel.HEADING_1));
c.push(compareTable());
c.push(p('官方原文：「you can use the patching process to make minor upgrades to your 9.0 deployment.」本教學走 VAMI in-place update。', { italics: true }));

c.push(h('1. 前置準備', HeadingLevel.HEADING_1));
c.push(bullet('備份（官方硬性建議）：file-based backup 或 VM snapshot。本測試以 VM snapshot「pre-9.1-upgrade-9.0.2」作回滾。'));
c.push(bullet('時鐘：NTP 同步正確來源（本 lab = 10.0.1.254）。'));
c.push(bullet('9.1 更新庫：取得 VMware-vCenter-Server-Appliance-9.1.0.0-updaterepo.zip，解壓後以 HTTPS（或 FTPS）提供服務。VAMI「Specified」repo 只接受 HTTPS/FTPS，不吃純 HTTP。'));
c.push(bullet('本測試：depot(10.0.0.61) 解壓到 /depot/vc91repo/，python https server 提供 https://10.0.0.61:8443/（自簽憑證）。'));

c.push(h('2. 檢視升級前版本（VAMI Summary）', HeadingLevel.HEADING_1));
c.push(p('瀏覽器開 https://vc9test.home.lab:5480 → Administrator@vsphere.local 登入 → Summary。確認 Release Name / Version = 9.0.2.0，Build 25148086，Health 全 Good。'));
fig('01-vami-summary-before-9.0.2.png', '升級前 VAMI Summary：Version 9.0.2.0').forEach(x => c.push(x));

c.push(h('3. 設定更新來源 repository（Update → Settings）', HeadingLevel.HEADING_1));
c.push(p('左側 Update 頁：可見目前版本 9.0.2.0，右上 SETTINGS / CHECK UPDATES。'));
fig('02-vami-update-page-before.png', 'Update 頁（升級前，版本 9.0.2.0）').forEach(x => c.push(x));
c.push(p('點 SETTINGS：Repository Settings URL 選 Specified；URL 填 https://10.0.0.61:8443/；取消勾 Check Certificate（自簽；正式環境用受信任憑證則保持勾選）→ SAVE。'));
fig('03-repo-settings-specified.png', '指定 Specified repository URL（HTTPS）').forEach(x => c.push(x));

c.push(h('4. 檢查可用更新（Check Updates）', HeadingLevel.HEADING_1));
c.push(p('右上 CHECK UPDATES → Check CD ROM + URL。Available updates 出現 Version 9.1.0.0 / Type: Enhancement / Reboot Required: Yes，代表 9.0.2 → 9.1.0.0 是合法 in-place 路徑。'));
fig('04-available-update-9.1.0.0.png', '偵測到可用更新 9.1.0.0（Enhancement）').forEach(x => c.push(x));

c.push(h('5. Stage and Install 精靈', HeadingLevel.HEADING_1));
c.push(p('選取 9.1.0.0 → 點 STAGE AND INSTALL。', { bold: true }));
c.push(h('5.1 EULA', HeadingLevel.HEADING_2));
c.push(p('勾選 I accept the terms of the license agreement → NEXT。'));
fig('05-wizard-eula.png', '接受授權合約').forEach(x => c.push(x));
c.push(h('5.2 Pre-Update Check（自動）', HeadingLevel.HEADING_2));
c.push(p('系統自動跑 pre-update checks。本測試皆為 Warning（非阻斷）：'));
c.push(bullet('LCM 不支援的舊 baseline 檔不複製'));
c.push(bullet('VM 硬體版本過舊 → 升級後依 KB 403995 升 VM compatibility'));
c.push(bullet('無法檢查 Supervisor 互通性（本環境無 Supervisor）'));
c.push(bullet('未做 file-based backup（本測試以 VM snapshot 取代）'));
c.push(bullet('system / memory health degraded（tiny 剛開機的暫時狀態）'));
c.push(p('檢視後點 IGNORE AND CONTINUE（正式環境應先消除警告）。'));
fig('06-preupdate-checks-warnings.png', 'Pre-Update Check 結果（皆為 Warning）').forEach(x => c.push(x));
c.push(h('5.3 Join CEIP / 5.4 Backup', HeadingLevel.HEADING_2));
c.push(p('CEIP 依需求勾選（本測試取消）。Backup 步說明 update 過程會自動建立 LVM snapshot 備份，顯示預估停機約 42 分；勾 I have backed up... → FINISH。'));
fig('07-wizard-backup-step.png', 'Backup 確認步（勾選後 FINISH）').forEach(x => c.push(x));

c.push(h('6. 安裝進行中', HeadingLevel.HEADING_1));
c.push(p('畫面顯示 Installation In Progress：Staging（從 repo 下載 9.1 RPM）→ 安裝 RPM → 自動 LVM 備份 → post-install 資料轉換 → 自動重開機。過程 VAMI/vCenter 服務會中斷並重開，屬正常。'));
fig('08-install-in-progress-staging.png', 'Staging 開始（0%）').forEach(x => c.push(x));
fig('09-install-downloading-rpms.png', '下載 9.1 RPM（來自 repo）').forEach(x => c.push(x));
fig('10-install-lvm-backup.png', '自動 LVM 備份/回滾點（83%）').forEach(x => c.push(x));
fig('11-install-converting-data-96.png', 'Post-install 資料轉換（96%）').forEach(x => c.push(x));

c.push(h('7. 升級後驗證', HeadingLevel.HEADING_1));
c.push(p('重開完成後（web 服務需數分鐘起完）重新登入 VAMI → Summary，確認 Version = 9.1.0.0、Health 全 Good；再登入 vSphere Client（https://vc9test.home.lab）確認版本。'));
fig('12-vami-summary-after-9.1.0.0.png', '升級後 VAMI Summary：Version 9.1.0.0，Health 全 Good').forEach(x => c.push(x));
fig('13-vsphere-client-9.1.png', 'vSphere Client 確認：Release/Version 9.1.0.0、Build 25370922、Health Good').forEach(x => c.push(x));

c.push(h('8. 升級後續（Post-upgrade）', HeadingLevel.HEADING_1));
c.push(bullet('依 KB 403995 升級 vCenter VM hardware compatibility（precheck 警告項）。'));
c.push(bullet('視需要續套 9.1.0.0100 / 0200 patch（同法，repo 換對應 updaterepo）。'));
c.push(bullet('vSphere Client 橫幅提示：如需 license，需部署 VCF Operations 或 VCF Installer appliance。'));

c.push(h('附錄：CLI 等效做法（software-packages）', HeadingLevel.HEADING_1));
['software-packages stage --url https://10.0.0.61:8443/ --acceptEulas',
 'software-packages list --staged',
 'software-packages install --staged',
 '# 或一次到位：software-packages install --url https://10.0.0.61:8443/ --acceptEulas',
 'shutdown now -r "patch reboot"'
].forEach(line => c.push(new Paragraph({ spacing: { after: 20 }, shading: { type: ShadingType.CLEAR, color: 'auto', fill: 'F2F2F2' }, children: [new TextRun({ text: line, font: 'Consolas', size: 18 })] })));

const doc = new Document({ styles: { default: { document: { run: { font: FONT, size: 22 } } } },
  sections: [{ properties: { page: { size: { width: 12240, height: 15840 } } }, children: c }] });
Packer.toBuffer(doc).then(buf => { fs.writeFileSync(OUT, buf); console.log('WROTE ' + OUT + ' (' + buf.length + ' bytes)'); });
