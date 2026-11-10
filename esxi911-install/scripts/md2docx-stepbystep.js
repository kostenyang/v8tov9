// Step-by-step README.md → docx(沿用 lab 文件版面:微軟正黑體、藍表頭、頁尾頁碼、靜態目錄)
// 用法:node md2docx-stepbystep.js <README.md> <out.docx> "<封面標題>" "<副標題>" "<日期/環境說明>"
// 支援:## / ### / #### 標題、段落(**粗體**、`code`、[文字](連結))、表格、![](img/x.png)、```code```、> 引言、- 項目、1. 步驟(含縮排的圖/程式碼)
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, PageBreak, ImageRun,
  LevelFormat, BorderStyle, Footer, PageNumber
} = require('docx');

const [, , SRC, OUT, TITLE, SUBTITLE, META] = process.argv;
const BASE = path.dirname(SRC);
// MD2DOCX_LANG=en:圖說/目錄/頁尾改英文、預設字型改 Calibri(預設維持中文)
const EN = process.env.MD2DOCX_LANG === 'en';
const L = EN ? { fig: 'Figure ', toc: 'Contents', pgPre: '  |  Page ', pgPost: '', font: 'Calibri' }
             : { fig: '圖 ', toc: '目錄', pgPre: '　｜　第 ', pgPost: ' 頁', font: 'Microsoft JhengHei' };
const C = { blue: '1F4E79', gray: '595959', red: 'C00000', note: 'FFF2CC', quoteText: '7F3F00' };
const TW = 9026;
const lines = fs.readFileSync(SRC, 'utf8').replace(/\r/g, '').split('\n');

// ---------- inline ----------
function runs(text, base) {
  base = base || {};
  const out = [];
  text = text.replace(/&#124;/g, '|');
  const re = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)]+\))/g;
  let last = 0, m;
  while ((m = re.exec(text)) !== null) {
    if (m.index > last) out.push(new TextRun(Object.assign({ text: text.slice(last, m.index) }, base)));
    const tok = m[0];
    if (tok.startsWith('**')) {
      out.push(...runs(tok.slice(2, -2), Object.assign({}, base, { bold: true })));
    } else if (tok.startsWith('`')) {
      out.push(new TextRun(Object.assign({}, base, { text: tok.slice(1, -1), font: 'Consolas', size: (base.size || 21) - 2 })));
    } else {
      const lm = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(tok);
      let label = lm[1].replace(/`/g, '');
      const href = lm[2];
      if (/^https?:/.test(href)) {
        out.push(new TextRun(Object.assign({}, base, { text: label, color: C.blue, underline: {} })));
      } else {
        out.push(new TextRun(Object.assign({}, base, { text: label, font: 'Consolas', size: (base.size || 21) - 2 })));
      }
    }
    last = re.lastIndex;
  }
  if (last < text.length) out.push(new TextRun(Object.assign({ text: text.slice(last) }, base)));
  return out;
}

// ---------- blocks ----------
let figNo = 0;
function image(rel, indentLeft, alt) {
  const file = path.join(BASE, rel);
  const b = fs.readFileSync(file);
  const w = b.readUInt32BE(16), h = b.readUInt32BE(20);
  let cw = indentLeft ? 560 : 600, ch = Math.round(h * cw / w);
  // 選用:MD2DOCX_MAXH=<px> 限制圖高(4:3 console 截圖太高時,一頁才放得下兩張)
  const maxH = +process.env.MD2DOCX_MAXH || 0;
  if (maxH && ch > maxH) { cw = Math.round(cw * maxH / ch); ch = maxH; }
  figNo++;
  return [
    // keepNext:圖與圖說不分頁
    new Paragraph({ alignment: AlignmentType.CENTER, keepNext: true, spacing: { before: 80, after: 40 },
      children: [new ImageRun({ type: 'png', data: b, transformation: { width: cw, height: ch } })] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 160 },
      // 圖說:有 alt 文字就用 alt,否則用檔名
      children: [new TextRun({ text: L.fig + figNo + (EN ? '  ' : '　') + (alt || path.basename(rel, '.png')), size: 16, color: C.gray, italics: true })] })
  ];
}
function code(textLines, indent) {
  return new Paragraph({
    children: textLines.map((l, i) => new TextRun({ text: l, font: 'Consolas', size: 16, break: i === 0 ? 0 : 1 })),
    shading: { type: ShadingType.CLEAR, fill: 'F2F2F2' },
    spacing: { before: 60, after: 100 }, indent: { left: indent || 200 }
  });
}
function splitRow(l) {
  let s = l.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split(/(?<!\\)\|/).map(x => x.trim().replace(/\\\|/g, '|'));
}
function table(rows) {
  const header = rows[0], body = rows.slice(2).map(splitRow), hdr = splitRow(header);
  const n = hdr.length;
  // 欄寬:依內容長度估
  const len = hdr.map((h, i) => Math.max(h.length, ...body.map(r => (r[i] || '').length)));
  const tot = len.reduce((a, b) => a + Math.min(b, 60), 0) || 1;
  const widths = len.map(l => Math.max(1150, Math.round(TW * Math.min(l, 60) / tot))); // 1150 dxa 才放得下 6 位數不折行
  const scale = TW / widths.reduce((a, b) => a + b, 0);
  const W = widths.map(w => Math.round(w * scale));
  // 短表(≤15 列)整張不跨頁:每列 keepNext 到最後一列
  const keep = body.length <= 15;
  const mk = (cells, isHdr, isLast) => new TableRow({
    tableHeader: isHdr, cantSplit: true,
    children: Array.from({ length: n }, (_, i) => new TableCell({
      width: { size: W[i], type: WidthType.DXA },
      shading: isHdr ? { type: ShadingType.CLEAR, fill: C.blue } : undefined,
      children: [new Paragraph({ keepNext: keep && !isLast, children: runs(cells[i] || '', isHdr ? { bold: true, color: 'FFFFFF', size: 18 } : { size: 18 }) })]
    }))
  });
  return new Table({ rows: [mk(hdr, true, body.length === 0)].concat(body.map((r, k) => mk(r, false, k === body.length - 1))), width: { size: TW, type: WidthType.DXA }, columnWidths: W });
}

const body = [];
const toc = [];
let h1No = 0;
let stepInstance = 0;
let i = 0;
let title = TITLE;
while (i < lines.length) {
  let l = lines[i];
  if (/^# /.test(l)) { if (!title) title = l.slice(2).trim(); i++; continue; }
  if (/^## /.test(l)) {
    h1No++;
    const t = l.slice(3).trim();
    toc.push(t);
    // 用 pageBreakBefore 而非獨立的 PageBreak 段落:前一頁剛好被圖塞滿時,獨立分頁段落會溢到新頁、多出一張空白頁
    body.push(new Paragraph({ children: runs(t), heading: HeadingLevel.HEADING_1, pageBreakBefore: h1No > 1, keepNext: true, spacing: { before: 240, after: 160 } }));
    i++; continue;
  }
  if (/^### /.test(l)) { body.push(new Paragraph({ children: runs(l.slice(4).trim()), heading: HeadingLevel.HEADING_2, keepNext: true, spacing: { before: 240, after: 120 } })); i++; continue; }
  if (/^#### /.test(l)) { body.push(new Paragraph({ children: runs(l.slice(5).trim()), heading: HeadingLevel.HEADING_3, keepNext: true, spacing: { before: 180, after: 100 } })); i++; continue; }
  if (/^\s*$/.test(l)) { i++; continue; }
  // code block
  if (/^\s*```/.test(l)) {
    const ind = l.match(/^\s*/)[0].length;
    const buf = []; i++;
    while (i < lines.length && !/^\s*```/.test(lines[i])) { buf.push(lines[i].slice(Math.min(ind, lines[i].match(/^\s*/)[0].length))); i++; }
    i++;
    body.push(code(buf, ind ? 760 : 200));
    continue;
  }
  // image
  let im = /^\s*!\[([^\]]*)\]\(([^)]+)\)\s*$/.exec(l);
  if (im) { body.push(...image(im[2], /^\s+/.test(l), im[1].trim())); i++; continue; }
  // table
  if (/^\s*\|/.test(l) && i + 1 < lines.length && /^\s*\|[\s:|-]+\|\s*$/.test(lines[i + 1])) {
    const rows = [];
    while (i < lines.length && /^\s*\|/.test(lines[i])) { rows.push(lines[i]); i++; }
    body.push(table(rows));
    body.push(new Paragraph({ spacing: { after: 80 }, children: [] }));
    continue;
  }
  // blockquote(連續 > 行合併;內含圖片獨立處理)
  if (/^\s*>/.test(l)) {
    const paras = []; let cur = [];
    while (i < lines.length && /^\s*>/.test(lines[i])) {
      const t = lines[i].replace(/^\s*>\s?/, '');
      const qim = /^!\[[^\]]*\]\(([^)]+)\)\s*$/.exec(t.trim());
      if (qim) { if (cur.length) { paras.push({ t: cur.join(' ') }); cur = []; } paras.push({ img: qim[1] }); }
      else if (t.trim() === '') { if (cur.length) { paras.push({ t: cur.join(' ') }); cur = []; } }
      else cur.push(t.trim());
      i++;
    }
    if (cur.length) paras.push({ t: cur.join(' ') });
    for (const p of paras) {
      if (p.img) { body.push(...image(p.img, true)); continue; }
      body.push(new Paragraph({ children: runs(p.t, { size: 20, color: C.quoteText }),
        shading: { type: ShadingType.CLEAR, fill: C.note }, spacing: { before: 60, after: 60 },
        indent: { left: 200 }, border: { left: { style: BorderStyle.SINGLE, size: 18, color: 'BF9000', space: 6 } } }));
    }
    continue;
  }
  // bullet
  let bm = /^(\s*)[-*] (.*)$/.exec(l);
  if (bm) {
    const lvl = bm[1].length >= 2 ? 1 : 0;
    body.push(new Paragraph({ children: runs(bm[2]), numbering: { reference: 'bullets', level: lvl }, spacing: { after: 60 } }));
    i++; continue;
  }
  // numbered
  let nm = /^(\d+)\. (.*)$/.exec(l);
  if (nm) {
    if (nm[1] === '1') stepInstance++;
    // keepNext:步驟文字跟下面的截圖放同一頁
    body.push(new Paragraph({ children: runs(nm[2]), numbering: { reference: 'steps', level: 0, instance: stepInstance }, keepNext: true, spacing: { after: 80 } }));
    i++; continue;
  }
  // paragraph(合併到空行為止)
  const buf = [l.trim()]; i++;
  while (i < lines.length && lines[i].trim() !== '' && !/^\s*(#|```|\||>|!\[|[-*] |\d+\. )/.test(lines[i])) { buf.push(lines[i].trim()); i++; }
  // keepNext:說明文字緊接截圖時,文字跟圖放同一頁
  let nx = i; while (nx < lines.length && lines[nx].trim() === '') nx++;
  const beforeImg = nx < lines.length && /^(!\[|\|)/.test(lines[nx].trim());
  body.push(new Paragraph({ children: runs(buf.join(' ')), keepNext: beforeImg, spacing: { after: 100 }, indent: /^\s{2,}/.test(l) ? { left: 560 } : undefined }));
}

// ---------- cover + static TOC ----------
const cover = [
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 1800, after: 240 },
    children: [new TextRun({ text: title, size: 40, bold: true, color: C.blue })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 160 },
    children: [new TextRun({ text: SUBTITLE || '', size: 26, color: C.gray })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 600 },
    children: [new TextRun({ text: META || '', size: 20, color: C.gray })] }),
  new Paragraph({ border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: 'BFBFBF', space: 1 } }, spacing: { after: 240 } }),
  new Paragraph({ children: [new TextRun({ text: L.toc, bold: true, size: 28, color: C.blue })], spacing: { after: 160 } }),
  ...toc.map((t, k) => new Paragraph({ children: [new TextRun({ text: (/^\d+[.\s]/.test(t) ? '' : (k + 1) + '.  ') + t.replace(/[`*]/g, ''), size: 22 })], spacing: { after: 80 }, indent: { left: 300 } })),
  new Paragraph({ children: [new PageBreak()] })
];

const doc = new Document({
  creator: 'VCF Lab',
  title: title,
  numbering: {
    config: [
      { reference: 'bullets', levels: [
        { level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 560, hanging: 280 } } } },
        { level: 1, format: LevelFormat.BULLET, text: '–', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 1000, hanging: 280 } } } }
      ] },
      { reference: 'steps', levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 560, hanging: 360 } } } }
      ] }
    ]
  },
  styles: {
    default: { document: { run: { font: L.font, size: 21 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', run: { size: 32, bold: true, color: C.blue } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', run: { size: 26, bold: true, color: C.blue } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', run: { size: 23, bold: true, color: '404040' } }
    ]
  },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 }, margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: title + L.pgPre, size: 16, color: C.gray }),
                 new TextRun({ children: [PageNumber.CURRENT], size: 16, color: C.gray }),
                 new TextRun({ text: L.pgPost, size: 16, color: C.gray })]
    })] }) },
    children: cover.concat(body)
  }]
});

Packer.toBuffer(doc).then(b => {
  fs.writeFileSync(OUT, b);
  console.log('OK ' + OUT + '  ' + Math.round(b.length / 1024) + ' KB, figures=' + figNo + ', sections=' + toc.length);
});
