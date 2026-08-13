const fs = require('fs');
const path = require('path');
const { Document, Packer, Paragraph, TextRun, HeadingLevel, ImageRun, Table, TableRow, TableCell,
  WidthType, BorderStyle, ShadingType, AlignmentType, PageBreak } = require('docx');

const IMG = 'E:/9.1/docs/vc8-to-91-upgrade/img';
const OUT = 'E:/9.1/docs/vc8-to-91-upgrade/vc8-0-3-to-9-1-migration-upgrade.docx';
const FONT = 'Microsoft JhengHei';

let figN = 0;
function h(t, l) { return new Paragraph({ heading: l, spacing: { before: 120, after: 120 }, children: [new TextRun({ text: t, font: FONT, bold: true })] }); }
function p(t, o = {}) { return new Paragraph({ spacing: { after: 90 }, children: [new TextRun({ text: t, font: FONT, size: o.size || 22, bold: !!o.bold, italics: !!o.italics, color: o.color })] }); }
function bullet(t) { return new Paragraph({ bullet: { level: 0 }, spacing: { after: 40 }, children: [new TextRun({ text: t, font: FONT, size: 21 })] }); }
function pagebreak() { return new Paragraph({ children: [new PageBreak()] }); }
function fig(file, desc, w = 640) {
  figN++;
  const fp = path.join(IMG, file); const out = [];
  const hh = Math.round(w * 1033 / 1710);
  if (fs.existsSync(fp)) {
    out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 60, after: 20 },
      children: [new ImageRun({ type: 'png', data: fs.readFileSync(fp), transformation: { width: w, height: hh },
        border: { color: 'BBBBBB', space: 1, style: BorderStyle.SINGLE, size: 6 } })] }));
  } else { out.push(p('[圖待補：' + file + ']', { italics: true, color: '999999' })); }
  out.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 120 }, children: [new TextRun({ text: '圖 ' + figN + '　' + desc, font: FONT, size: 18, italics: true, color: '555555' })] }));
  return out;
}
function cell(t, { bold = false, shade = null, w } = {}) {
  return new TableCell({ width: { size: w, type: WidthType.DXA }, shading: shade ? { type: ShadingType.CLEAR, color: 'auto', fill: shade } : undefined,
    margins: { top: 40, bottom: 40, left: 80, right: 80 }, children: [new Paragraph({ children: [new TextRun({ text: t, font: FONT, size: 19, bold })] })] });
}
function compareTable() {
  const W = [2400, 3500, 3300]; const total = W.reduce((a, b) => a + b, 0);
  return new Table({ columnWidths: W, width: { size: total, type: WidthType.DXA }, rows: [
    new TableRow({ tableHeader: true, children: [cell('情境', { bold: true, shade: 'DDE6F0', w: W[0] }), cell('官方方法', { bold: true, shade: 'DDE6F0', w: W[1] }), cell('媒體', { bold: true, shade: 'DDE6F0', w: W[2] })] }),
    new TableRow({ children: [cell('同版 minor (9.0 → 9.1)', { w: W[0] }), cell('Update：in-place（VAMI / software-packages）', { w: W[1] }), cell('-updaterepo.zip（更新庫 URL）', { w: W[2] })] }),
    new TableRow({ children: [cell('跨大版 (8.x → 9.1)', { bold: true, w: W[0] }), cell('Upgrade：migration（新機+遷移+接管 IP），可搭 RDU', { bold: true, shade: 'EAF3E0', w: W[1] }), cell('VMware-VCSA-all-9.1.x.iso 安裝器', { shade: 'EAF3E0', w: W[2] })] }),
  ] });
}

const c = [];
// ===== Page 1: 概念 + 流程圖 =====
c.push(new Paragraph({ spacing: { after: 60 }, children: [new TextRun({ text: 'vCenter 8.0.3 → 9.1 升級教學', font: FONT, bold: true, size: 34, color: '1F3864' })] }));
c.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: '跨大版 Migration Upgrade（新機 + 遷移，含 Reduced Downtime Upgrade）', font: FONT, size: 23, color: '555555' })] }));
c.push(new Paragraph({ spacing: { after: 120 }, children: [new TextRun({ text: '測試環境：vc8test.home.lab (10.0.0.112) · 2026-07 · 實測結果：8.0.3 → 9.1.0.0 升級成功', font: FONT, size: 18, italics: true, color: '777777' })] }));
c.push(h('0. 觀念：8→9.1 為什麼走 Migration', HeadingLevel.HEADING_2));
c.push(p('跨大版（8.x→9.1）與同版 minor（9.0→9.1）走的路不同：'));
c.push(compareTable());
c.push(p('本例 8.0.3（U3 GA, build 24022515）早於 9.1 baseline → 官方支援直升 9.1.0（須避開 8.0 U3j/U3k 的 back-in-time 限制）。', { italics: true }));
fig('00-migration-diagram.png', '8.0.3 → 9.1 兩階段 Migration 流程（部新機 → 遷移 → 接管 IP → 關舊機）', 660).forEach(x => c.push(x));

// ===== Page 2: 前置 + 升級前 =====
c.push(pagebreak());
c.push(h('1. 前置準備與升級前狀態', HeadingLevel.HEADING_2));
c.push(bullet('9.1 安裝器 ISO：VMware-VCSA-all-9.1.0.0.iso（掛載後用其 GUI 或 CLI 安裝器）。'));
c.push(bullet('來源版本檢查：8.0.3 (U3 GA) 支援直升 9.1.0；勿用 8.0 U3j/U3k（back-in-time 擋）。'));
c.push(bullet('備份 / 回滾：官方建議 file-based backup；本測試另建 VM 快照 pre-9.1-migration-8.0.3。'));
c.push(bullet('保留一個暫時 IP（本例 10.0.0.113）供新機在遷移期間使用。'));
fig('01-before-8.0.3.png', '升級前驗證：vc8test 為 vCenter 8.0.3（build 24022515）', 660).forEach(x => c.push(x));

// ===== Page 3: 執行 CLI =====
c.push(pagebreak());
c.push(h('2. 執行升級（vcsa-deploy upgrade）', HeadingLevel.HEADING_2));
c.push(p('掛載 9.1 安裝器 ISO 後，用 CLI（vcsa-deploy upgrade）搭 JSON 範本一鍵啟動；也可改用 GUI 安裝器（vcsa-ui-installer\\installer.exe）走兩階段精靈。範本關鍵：新機部署目標、暫時網路、來源 vCenter、遷移資料量。'));
fig('02-cli-upgrade.png', 'vcsa-deploy upgrade 指令與 JSON 範本關鍵段', 660).forEach(x => c.push(x));

// ===== Page 4: RDU 進度 =====
c.push(pagebreak());
c.push(h('3. 升級進行中（RDU 兩階段）', HeadingLevel.HEADING_2));
c.push(p('系統採 Reduced Downtime Upgrade：Stage 1 在暫時 IP 部好新 9.1 並同步資料；Stage 2 最後一刻切換，由新機接管來源 IP、啟動服務、移除舊資料。對外停機極短，舊 8.0.3 機收尾後自動關閉（保留可回滾）。'));
fig('03-rdu-progress.png', 'RDU 兩階段實際進度（部署 → 準備 → 切換接管 → 收尾）', 660).forEach(x => c.push(x));

// ===== Page 5: 升級後 =====
c.push(pagebreak());
c.push(h('4. 升級後驗證', HeadingLevel.HEADING_2));
c.push(p('主機名與 IP 不變（vc8test.home.lab / 10.0.0.112），底層換成全新 9.1.0.0 appliance。以 govc / VAMI / vSphere Client 確認版本為 9.1.0.0、健康 Good。'));
fig('04-after-9.1.png', '升級後驗證：vc8test = vCenter 9.1.0.0（build 25370922），同 IP 接管', 660).forEach(x => c.push(x));
c.push(h('5. 升級後續（Post-upgrade）', HeadingLevel.HEADING_2));
c.push(bullet('依 KB 403995 升級 vCenter VM hardware compatibility。'));
c.push(bullet('確認新機一切正常後，可刪除已關機的舊 8.0.3 appliance 與 VM 快照。'));
c.push(bullet('如需 license：依提示部署 VCF Operations / VCF Installer appliance。'));

const doc = new Document({ styles: { default: { document: { run: { font: FONT, size: 22 } } } },
  sections: [{ properties: { page: { size: { width: 12240, height: 15840 } } }, children: c }] });
Packer.toBuffer(doc).then(b => { fs.writeFileSync(OUT, b); console.log('WROTE ' + OUT + ' (' + b.length + ' bytes)'); });
