// VCF 9.1.1 既有 VCF Operations + License Server 併入管理網域 — 實作與驗證報告
//   node build-m03-converge.js
const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, ImageRun, PageBreak, BorderStyle
} = require('docx');

const SHOTS = 'E:/9.1/doc-shots/m03-ops';
const DIAG  = 'E:/9.1/doc-shots/m03-ops/diagrams';
const OUT   = 'E:/9.1/VCF911-既有Operations併入管理網域.docx';

const C = { blue: '1F4E79', gray: '595959', red: 'C00000', green: '2E7D32', amber: 'B77E00' };
const W_UI = 600, W_DIAG = 640;

const H1 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_1, spacing: { before: 340, after: 160 } });
const H2 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_2, spacing: { before: 260, after: 120 } });
const H3 = t => new Paragraph({ text: t, heading: HeadingLevel.HEADING_3, spacing: { before: 200, after: 100 } });
const P = (t, o = {}) => new Paragraph({
  children: [new TextRun({ text: t, size: o.size || 21, bold: o.bold, color: o.color, italics: o.italics })],
  spacing: { after: o.after != null ? o.after : 110 }, alignment: o.align });
const CODE = t => new Paragraph({
  children: String(t).split('\n').map((ln, i) => new TextRun({ text: ln, font: 'Consolas', size: 16, break: i ? 1 : 0 })),
  shading: { type: ShadingType.CLEAR, fill: 'F4F4F4' },
  spacing: { before: 70, after: 70 }, indent: { left: 220 } });
const BULLET = t => new Paragraph({
  children: [new TextRun({ text: t, size: 21 })], bullet: { level: 0 }, spacing: { after: 70 } });
const NOTE = (t, fill, color) => new Paragraph({
  children: [new TextRun({ text: t, size: 20, color: color || C.gray })],
  shading: { type: ShadingType.CLEAR, fill: fill || 'FFF6E5' },
  spacing: { before: 90, after: 90 }, indent: { left: 120, right: 120 },
  border: { left: { style: BorderStyle.SINGLE, size: 18, color: color || C.amber } } });
const WARN = t => NOTE(t, 'FDEDED', C.red);
const GOOD = t => NOTE(t, 'EDF7EE', C.green);
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
const missing = [];
function fig(dir, file, caption, maxW) {
  const p = path.join(dir, file);
  const out = []; figNo++;
  if (fs.existsSync(p)) {
    const { w, h } = pngSize(p); const cw = maxW || W_UI; const ch = Math.round(cw * h / w);
    out.push(new Paragraph({ children: [new ImageRun({ type: 'png', data: fs.readFileSync(p), transformation: { width: cw, height: ch } })],
      alignment: AlignmentType.CENTER, spacing: { before: 140, after: 40 } }));
  } else {
    missing.push(file);
    out.push(new Paragraph({ children: [new TextRun({ text: '[ 缺圖:' + file + ' ]', italics: true, color: C.red, size: 18 })], alignment: AlignmentType.CENTER }));
  }
  out.push(new Paragraph({ children: [new TextRun({ text: '圖 ' + figNo + '\u3000' + caption, size: 18, color: C.gray })], alignment: AlignmentType.CENTER, spacing: { after: 180 } }));
  return out;
}
const F = (f, c, w) => fig(SHOTS, f, c, w);
const D = (f, c) => fig(DIAG, f, c, W_DIAG);

const DATE = '2026-10-05';
let body = [];
const add = (...x) => { x.forEach(e => Array.isArray(e) ? body.push(...e) : body.push(e)); };

// ============================ 封面 ============================
add(
  new Paragraph({ spacing: { before: 1800 } }),
  P('VMware Cloud Foundation 9.1.1', { size: 28, color: C.gray, align: AlignmentType.CENTER }),
  new Paragraph({ children: [new TextRun({ text: '把既有的 VCF Operations 與 License Server', size: 44, bold: true, color: C.blue })], alignment: AlignmentType.CENTER, spacing: { after: 80 } }),
  new Paragraph({ children: [new TextRun({ text: '併入管理網域', size: 44, bold: true, color: C.blue })], alignment: AlignmentType.CENTER, spacing: { after: 220 } }),
  P('實作與驗證報告', { size: 26, color: C.gray, align: AlignmentType.CENTER, after: 700 }),
  P('實測環境:home.lab 巢狀實驗室　·　VCF Installer 9.1.1.0.25713928', { size: 20, color: C.gray, align: AlignmentType.CENTER, after: 60 }),
  P(DATE, { size: 20, color: C.gray, align: AlignmentType.CENTER }),
  PB());

// ============================ 目錄 ============================
add(H1('目錄'),
  ...[['一、摘要與結論', ''], ['二、測試拓樸', ''], ['三、三條路徑', ''],
      ['四、階段一:建立「既有環境」', ''], ['五、階段二:VCF Installer 準備', ''],
      ['六、階段三:走錯的那條路 — greenfield', ''], ['七、階段四:正解 — Plan / Existing Component', ''],
      ['八、階段五:驗證與部署', ''], ['九、坑與教訓彙整', ''],
      ['附錄 A:DNS 與 IP 規劃', ''], ['附錄 B:兩條路徑的 spec 對照', ''], ['附錄 C:UI 自動化筆記', '']]
    .map(([t]) => P('　' + t, { size: 21, after: 90 })),
  PB());

// ============================ 一、摘要 ============================
add(H1('一、摘要與結論'));
add(P('本文回答一個具體問題:手上已經有一套 VCF Operations 9.1.1 與 License Server,要怎麼把它們併進新建的 VCF 管理網域。全程以 UI 操作實測,並附上精靈產生的 deployment spec 作為佐證。'));

add(H2('結論'));
add(table(
  ['既有的東西', '做法', '結果'],
  [
    ['License Server', '什麼都不用做。走 converge 路徑時連欄位都不會出現', '✅ 自動繼承'],
    ['VCF Operations 9.1.1', 'Plan → Step 1 Existing Component 勾「I have an existing VCF Operations 9.1 instance」', '✅ UI 原生支援'],
    ['Operations 所在的 vCenter', '上一項勾下去會自動勾選並鎖定,不能不選', '✅ 強制一併併入'],
    ['只有裸 ESXi 主機', 'Existing Component 什麼都不勾,走 greenfield', '⚠ 主機必須乾淨'],
    ['既有 vSphere 叢集(想變 workload domain)', 'VCF Operations → Import a vCenter', '— 不同流程'],
  ], [26, 50, 24]));

add(GOOD('一句話:開關在 Plan 階段的第一步,不在 Prepare。跳過 Plan 直接進 Prepare,精靈就是純 greenfield,對既有環境一定過不了驗證。'));

add(H2('驗證結果'));
add(P('勾選既有元件後重跑,12 項驗證 10 項 Succeeded、2 項可確認的 Warning、零失敗:'));
add(CODE([
  'Deployment Specification                      Succeeded',
  'Security Configuration                        Succeeded',
  'DNS Resolution                                Succeeded',
  'Versions and Bundles                          Succeeded',
  'Existing SDDC Manager Configuration           Succeeded',
  'Password Policies                             Succeeded',
  'Network Configuration                         Succeeded',
  'Existing Components                           Warning  → Acknowledged',
  'Brownfield VCF Management Services validation Succeeded',
  'VCF Installer Required Capacity Calculation   Succeeded',
  'VCF Installer Available Capacity Calculation  Succeeded',
  'VCF Installer Capacity Validation             Warning  → Acknowledged',
].join('\n')));
add(P('精靈回報的三句關鍵訊息:'));
add(CODE([
  'Successfully detected VCF Operations vcf-m03-ops01.home.lab.',
  'Successfully detected vCenter vcf-m03-vc01.home.lab.',
  'Selected cluster vcf-m03-cl01 as the deployment destination.',
].join('\n')));
add(PB());

// ============================ 二、拓樸 ============================
add(H1('二、測試拓樸'));
add(D('fig-topo.png', '測試拓樸 — 既有環境、VCF Installer、以及(結果用不到的)全新乾淨主機'));
add(P('左側是本次測試前就存在的環境:一套 nested vSphere 叢集,上面跑著 vCenter、VCF Operations 9.1.1 與 License Server 9.1.1。右側是為了測 greenfield 路徑而另外建的 4 台全新乾淨主機 —— 後來證實 converge 路徑並不需要它們。'));
add(table(['元件', 'FQDN', 'IP', '說明'], [
  ['既有 vCenter', 'vcf-m03-vc01.home.lab', '10.0.1.60', '9.1.1,管理 4 台 nested ESXi'],
  ['既有 VCF Operations', 'vcf-m03-ops01.home.lab', '10.0.1.61', '9.1.1,單節點'],
  ['既有 License Server', 'vcf-m03-lic01.home.lab', '10.0.1.62', '9.1.1,已向 Operations 註冊'],
  ['VCF Installer', 'vcf-m03-inst01.home.lab', '10.0.1.71', '裝在外層 vCenter,不屬於任何管理網域'],
  ['既有 nested ESXi ×4', 'vcf-m03-esx01~04', '10.0.1.56-59', '9.1.1,vSAN 4 TB'],
], [22, 30, 15, 33]));
add(PB());

// ============================ 三、三條路徑 ============================
add(H1('三、三條路徑'));
add(D('fig-paths.png', '依「既有的是什麼」分岔的三條路徑,以及 Plan 階段勾選後 Prepare 的變化'));
add(PB());

// ============================ 四、階段一 ============================
add(H1('四、階段一:建立「既有環境」'));
add(P('為了讓測試成立,必須先有一套「測試前就存在」的 VCF Operations 與 License Server。這一章記錄它們怎麼建起來的,全程走 vSphere Client 與 Operations 的 UI。'));

add(H2('4.1 部署 VCF Operations'));
add(P('在既有 vCenter 上用 Deploy OVF Template 精靈部署 Operations appliance,再跑它自己的初始設定精靈。'));
add(F('02-actions-menu.png', '叢集 ACTIONS → Deploy OVF Template'));
add(F('03-ovf-wizard-source.png', 'OVF 來源:直接餵 offline depot 的 URL,不必先下載到本機'));
add(F('05-customize-template.png', 'Customize template — 網路參數寫進 vApp 屬性'));
add(F('13-ready-to-complete.png', 'Operations 初始設定精靈 — Ready to Complete'));
add(F('16-cluster-online.png', '叢集啟動完成,狀態 Online'));

add(H2('4.2 取得 License Server 的 registration key'));
add(P('License Server 是獨立 appliance,部署時要餵一組 registration key。這組 key 由 VCF Operations 在本地產生 —— 不需要連外網。'));
add(F('22-licenses-registration.png', 'Operations → Manage → Licensing → Licenses & Registration'));
add(F('23-registration-key-redacted.png', '按下 START 之後本地產生的 registration key(本文已遮蔽)'));
add(GOOD('registration key 是 base64,解開後含有一張憑證與 "hosts":["vcf-m03-ops01.home.lab"] —— 它綁定的是這一台 Operations。重新進入頁面會產生「新的」key,但實測舊 key 不會失效,拿舊 key 部署的 appliance 照樣接得上。'));

add(H2('4.3 部署 License Server'));
add(F('31-lic-ovf-source.png', 'License Server OVA 來源 URL'));
add(F('34-lic-review-details.png', 'Review details — VCF License Server Appliance 9.1.1.0,憑證受信任'));
add(F('37-lic-customize.png', 'Customize template — Unique Registration Key 貼在最上面一欄'));
add(NOTE('OVA 屬性說明原文:「The license server does not connect to the internet, and only needs a network proxy if one is required to connect to VCF Operations.」—— License Server 完全不碰網際網路,proxy 只在連不到 Operations 時才需要。'));
add(F('41-license-servers-connected.png', 'Operations 的 License Servers 清單 — 狀態 Connected'));
add(P('清單顯示 vcf-m03-lic01.home.lab / 9.1.1.0.25679819 / Not Registered / Connected。Not Registered 指的是還沒跟 Broadcom 取得授權,不是沒跟 Operations 接上 —— Connected 才是看連線的那一欄。'));
add(PB());

// ============================ 五、階段二 ============================
add(H1('五、階段二:VCF Installer 準備'));

add(H2('5.1 接 offline depot'));
add(F('46-offline-depot-config.png', 'Offline Depot 設定 — URL 與帳密'));
add(F('47-depot-cert-thumbprint.png', '自簽憑證會跳指紋確認,勾選後才能按 CONFIRM'));
add(WARN('🔴 坑:offline depot 只吃裸 IP,不吃 FQDN。同一組帳密、同一張憑證(SAN 同時含 FQDN 與 IP)、DNS 正反解都正常,四種 FQDN 寫法全部被拒,換成 https://10.0.0.61 立刻成功。而且錯誤訊息會誤導:「The offline depot URL should be a valid URL without query parameters or fragments」—— 那些 URL 根本沒有 query 也沒有 fragment。現場遇到 VMWARE_DEPOT_OFFLINE_INVALID_URL,先換 IP 試。'));
add(table(['URL', '結果'], [
  ['https://vcf9depotserver.home.lab', '❌ VMWARE_DEPOT_OFFLINE_INVALID_URL'],
  ['https://vcf9depotserver.home.lab/', '❌ 同上'],
  ['https://vcf9depotserver.home.lab/PROD', '❌ 同上'],
  ['https://vcf9depotserver.home.lab:443', '❌ 同上'],
  ['https://10.0.0.61', '✅ DEPOT_CONNECTION_SUCCESSFUL'],
], [62, 38]));
add(F('48-depot-configured.png', '接上後顯示 Depot connection active'));

add(H2('5.2 下載 binaries'));
add(F('49-binary-selection.png', '選 VMware Cloud Foundation 9.1.1.0 的全部 16 個元件'));
add(P('16 個元件合計約 64 GB,從 lab 內的 depot 下載花了 22 分鐘(20:17 → 20:39)。最大的三個是 VCF services runtime 16.11 GB、VCF Automation 15.67 GB、vCenter 9.71 GB。'));
add(F('51-binaries-downloaded.png', '16 個元件全部 Success'));
add(PB());

// ============================ 六、階段三 ============================
add(H1('六、階段三:走錯的那條路 — greenfield'));
add(P('第一次跑精靈時,我沒有注意到 Plan 階段,直接進了 Prepare 的 9 步,把既有的 FQDN 填進去。這一章記錄那次的失敗 —— 因為失敗訊息本身很有價值:它完整定義了 greenfield 路徑對「乾淨主機」的要求。'));
add(F('44-deployment-paths.png', 'Deployment Paths — 選 Deploy a new VCF fleet'));
add(F('54-prepare-hosts.png', 'Prepare 第 2 步 Hosts — greenfield 路徑才有的步驟'));
add(F('62-prepare-vds-config.png', 'Prepare 第 7 步 Distributed Switch — greenfield 路徑才有的步驟'));
add(F('67-validation-failed.png', '16 項驗證,4 項失敗'));
add(D('fig-clean.png', 'greenfield 路徑對「乾淨主機」的六項要求,以及既有叢集為什麼全掛'));
add(WARN('最關鍵的一條是 IP_NOT_IN_USE:「IP Address 10.0.1.60 allocated for vcf-m03-vc01.home.lab is already in use」。在 greenfield 路徑下,把既有元件的 FQDN 填進去,精靈只會把它當成「要新部署的目標」,看到 IP 被佔用就報錯。'));
add(PB());

// ============================ 七、階段四 ============================
add(H1('七、階段四:正解 — Plan / Existing Component'));
add(P('精靈分成 Introduction → Plan → Prepare → Deploy 四個階段。「要不要用既有元件」是在 Plan 的第 1 步決定的。'));
add(F('84-plan-existing-component.png', 'Plan 第 1 步 Existing Component — 答案就在這一頁'));
add(table(['選項', '勾選後的效果'], [
  ['I have an existing VCF Operations 9.1 instance', '用既有 Operations 當 fleet 的中央管理台;spec 的 vcfOperationsSpec.useExistingDeployment 變成 true'],
  ['I have an existing vCenter instance', '🔒 勾上面那個會「自動勾選並 DISABLED」—— 精靈強制管理網域的 vCenter 必須是 Operations 所在的那一台'],
  ['The vCenter instance is registered with NSX Manager', '沿用該 vCenter 已註冊的 NSX Manager(本次未使用)'],
  ['I have an existing VCF Automation instance or I will deploy later', '跳過 VCF Automation 部署,省掉 15.67 GB 與 3 個節點;部署後再從 Operations 補'],
], [34, 66]));
add(NOTE('精靈對第一項的說明:「it is recommended you select the vCenter where it is currently deployed to create the VCF Fleet. This allows you to scale the VCF Operations instance, add replica and data nodes, or add cloud proxies directly from the VCF Operations UI.」文字寫 recommended,但 UI 實際是強制的。'));

add(H2('7.1 Size Options — Simple 模式讓資源需求砍半'));
add(F('85-plan-size-options.png', 'Size Options — Simple vs High Availability'));
add(table(['元件', 'High Availability', 'Simple'], [
  ['Cloud proxy', '4 vCPU / 16 GB / 264 GB', '4 vCPU / 16 GB / 264 GB'],
  ['VCF management services', '42 vCPU / 78 GB / 3201 GB', '28 vCPU / 58 GB / 2900 GB'],
  ['NSX Manager', 'Medium ×3 = 18 / 72 / 900', 'Medium ×1 = 6 / 24 / 300'],
], [30, 35, 35]));

add(H2('7.2 Review Prerequisites'));
add(F('87-plan-prerequisites.png', 'Review Prerequisites — 需要哪些 FQDN、要多少資源'));
add(P('這一頁直接點明 License Server 的處理方式:「License Server - 1 FQDN。This will not be required if the VCF Operations already have License Server deployed.」既有 Operations 已經接了 License Server,精靈就不會再問。'));

add(H2('7.3 Prepare 從 9 步變 6 步'));
add(table(['Prepare 階段', 'Greenfield', 'Converge'], [
  ['步數', '9 步', '6 步'],
  ['Hosts', '填 4 台 FQDN + root 密碼 + 確認指紋', '沒有這一步'],
  ['Storage', '選 vSAN 架構 / FTT / datastore 名稱', '沒有這一步'],
  ['Distributed Switch', '選 profile、配 uplink、設 5 個 portgroup', '沒有這一步'],
  ['Networks', '7 個網段 + 2 個 IP pool', '只要 1 個:VCF Management Services IP Pool'],
  ['驗證項目', '16 項', '12 項'],
], [22, 40, 38]));

add(H2('7.4 連上既有 VCF Operations'));
add(F('89-prep-existing-ops.png', 'Prepare 第 2 步 — 填既有 Operations 的 FQDN 與密碼,按 CONNECT'));
add(F('90-prep-ops-thumbprint.png', '憑證指紋確認,另外要勾「I acknowledge」'));
add(P('實測指紋與 openssl 直接取回的 SHA-256 完全相同,確認後出現 Successfully detected VCF Operations vcf-m03-ops01.home.lab。'));
add(F('91-prep-vcfmgmt.png', '連上之後:License Server 欄位整個消失,只剩 Cloud Proxy 與 VCF Management Services'));

add(H2('7.5 連上既有 vCenter'));
add(F('92-prep-existing-vcenter.png', 'Prepare 第 3 步 Existing vCenter'));
add(P('這一頁的說明很關鍵:「The cluster that is running the vCenter appliance will be selected as the deployment destination」—— 目的地叢集不是自己選的,而是「跑著 vCenter appliance 的那個叢集」。'));
add(F('93-prep-vcenter-connected.png', 'Selected cluster vcf-m03-cl01 as the deployment destination'));
add(F('95-prep-networks.png', 'Networks 只剩一個欄位:VCF Management Services IP Pool'));
add(F('96-prep-nsx.png', 'NSX Manager — Simple 模式只要 1 台 appliance'));
add(PB());

// ============================ 八、階段五 ============================
add(H1('八、階段五:驗證與部署'));
add(F('98-review-summary.png', 'Review 摘要'));
add(F('99-validation-converge.png', '12 項驗證 — 10 Succeeded、2 Warning(已 Acknowledge)'));
add(F('100-deploy-started.png', '部署開始 — 五個里程碑共 158 個子任務'));
add(table(['里程碑', '子任務數'], [
  ['Deploy SDDC Manager', '16'],
  ['Convert the existing vCenter to a new VCF instance', '42'],
  ['Deploy and configure NSX', '70'],
  ['Deploy and configure VCF Management Platform', '21'],
  ['Join the existing operations appliance', '9'],
], [72, 28]));
add(P('最後兩個里程碑的名字就是本文問題的答案:既有的 vCenter 被「converted」成 VCF instance,既有的 Operations appliance 被「joined」進來。'));
add(PB());


// ============================ 八之二:失敗與根因 ============================
add(H2('8.1 第一次部署:NSX Manager 失敗'));
add(P('部署跑了約 3 小時後在第三個里程碑停住。前兩個里程碑全數完成 —— 既有 vCenter 已經成功轉成 VCF instance,SDDC Manager 也部署完成。'));
add(table(['里程碑', '結果'], [
  ['Deploy SDDC Manager', '16/16 成功'],
  ['Convert the existing vCenter to a new VCF instance', '42/42 成功'],
  ['Deploy and configure NSX', '25/69 失敗,卡在 Deploy NSX Manager'],
  ['Deploy and configure VCF Management Platform', '0/21 未開始'],
  ['Join the existing operations appliance', '0/9 未開始'],
], [68, 32]));
add(F('101-deploy-failed.png', '部署失敗 — Deploy NSX Manager'));
add(CODE([
  'Failed to deploy NSX Manager vcf-m03-nsx01a on vcf-m03-nsx01a.home.lab.',
  'Error: Task failed on server: No host is compatible with the virtual machine.',
  'Remediation: Please fix the issue reported and retry the workflow.',
  'Reference Token: I2J6CA',
].join(String.fromCharCode(10))));

add(H2('8.2 根因:單台主機的 vCPU 放不下 NSX Manager'));
add(P('NSX Manager Medium 需要 6 vCPU。測試過程中為了另一個(後來證實用不到的)計畫,把叢集四台主機從 16 vCPU 縮成 4 vCPU。VM 的 vCPU 數不能超過主機的邏輯 CPU 數,因此沒有任何一台放得下。'));
add(WARN('這一條值得單獨記住:VCF Installer 的容量驗證只看「叢集總量」,不看「單台主機能不能放下最大的那個 VM」。本次需求是 42 vCPU 的叢集總量,叢集有 4 台乘 4 vCPU 等於 16 vCPU,驗證仍回報 meets the resource requirements —— 但 NSX Manager 的 6 vCPU 大於單台主機的 4 vCPU,要跑到部署第三個里程碑才爆。驗證通過不等於部得起來。'));
add(table(['項目', '驗證看的', '實際擋人的'], [
  ['比較對象', '叢集 vCPU / RAM / 磁碟總量', '單台主機邏輯 CPU 數 vs 最大 VM 的 vCPU'],
  ['本次數字', '需求 42 vCPU,叢集 16 vCPU,仍判定通過', 'NSX Manager 6 vCPU 大於單台 4 vCPU,無相容主機'],
  ['出現時機', 'Validate & Deploy 階段', '部署跑到第三個里程碑才出現'],
], [18, 41, 41]));

add(H2('8.3 修復方式'));
add(P('nested 主機沒開 CPU hot-add,只能關機改。步驟:'));
add(BULLET('把叢集上的 appliance(SDDC Manager / Operations / License Server)優雅關機,vCenter 最後關'));
add(BULLET('關掉四台 nested 主機,改回 16 vCPU(RAM 維持 64 GB),再開機'));
add(BULLET('依序開回 vCenter → License Server → Operations → SDDC Manager'));
add(BULLET('回到精靈按 RETRY,工作流會從失敗的那一步接續'));
add(NOTE('事前檢查的方法:把「要部署的最大 VM 的 vCPU 數」跟「單台主機的邏輯 CPU 數」比一次。Simple 模式下最大的是 NSX Manager Medium(6 vCPU);High Availability 模式一樣是 NSX Manager Medium,但會部三台。'));
add(PB());


// ============================ 九、坑與教訓 ============================
add(H1('九、坑與教訓彙整'));

add(H2('9.1 流程面'));
add(table(['症狀', '真因', '解法'], [
  ['既有環境餵進精靈,驗證六項全掛', '跳過了 Plan 階段,走成純 greenfield', 'Plan → Step 1 Existing Component 勾選既有元件'],
  ['填了既有 vCenter 的 FQDN 卻報 IP 已被佔用', 'greenfield 路徑把 FQDN 當成「要新部署的目標」', '同上。useExistingDeployment 不必手動改 JSON'],
  ['不想要既有 vCenter,只想要既有 Operations', '辦不到 —— 勾了 Operations 會自動勾選並鎖定 vCenter', '接受;或改成先把 Operations 搬到想當管理網域的那個 vCenter'],
  ['目的地叢集不是我要的那個', '目的地 = 跑著 vCenter appliance 的叢集,不能選', '事前把 vCenter 搬到正確的叢集'],
], [30, 36, 34]));

add(H2('9.2 環境面'));
add(table(['症狀', '真因', '解法'], [
  ['offline depot 接不上,錯誤碼 VMWARE_DEPOT_OFFLINE_INVALID_URL', '只吃裸 IP 不吃 FQDN;訊息講 query/fragment 是誤導', 'URL 改成 https://<IP>'],
  ['主機瘦身後 appliance 開不了機', 'HA admission control 的 25% 失效移轉保留吃不下', '關掉該叢集的 HA 或 admission control'],
  ['DNS 同一個 IP 有多筆 A 記錄', '別的測試留下的殘影', '反解 PTR 正確就不影響驗證,但要確認殘影沒指到正在用的機器'],
  ['nested vMotion 卡在 0%', 'CPU 超配造成收端被餓死(不是網路)', '降低 vCPU 總量'],
  ['驗證全過,部署卻報 No host is compatible', '容量驗證只看叢集總量,不看單台主機放不放得下最大的 VM', '確認單台主機的邏輯 CPU >= 最大 VM 的 vCPU(NSX Manager Medium = 6)'],
], [30, 36, 34]));

add(WARN('🔴 本次差點出事:DNS 裡 vcf-m03-nsx01b 指向 10.0.1.59、vcf-m03-nsx01c 指向 10.0.1.60 —— 那正是本次環境的 esx04 與 vCenter。NSX 三節點在 HA 模式是必填,照著這兩個名字部下去會直接打到正在跑的主機和 vCenter。部署前務必逐一確認要用的 FQDN 沒有指到活著的機器。'));
add(PB());

// ============================ 附錄 A ============================
add(H1('附錄 A:DNS 與 IP 規劃'));
add(table(['FQDN', 'IP', '角色', '狀態'], [
  ['vcf-m03-esx01~04', '10.0.1.56-59', '既有 nested ESXi', '測試前存在'],
  ['vcf-m03-vc01', '10.0.1.60', '既有 vCenter → 管理網域 vCenter', '測試前存在'],
  ['vcf-m03-ops01', '10.0.1.61', '既有 VCF Operations', '測試前存在'],
  ['vcf-m03-lic01', '10.0.1.62', '既有 License Server', '測試前存在'],
  ['vcf-m03-nsx01', '10.0.1.63', 'NSX Manager VIP', '部署時建立'],
  ['vcf-m03-nsx01a', '10.0.1.64', 'NSX Manager appliance', '部署時建立'],
  ['vcf-m03-sddcm01', '10.0.1.65', 'SDDC Manager', '部署時建立'],
  ['vcf-m03-opsc01', '10.0.1.66', 'Cloud Proxy', '部署時建立'],
  ['vcf-m03-fleet01', '10.0.1.67', 'Fleet components', '部署時建立'],
  ['vcf-m03-vsp01', '10.0.1.69', 'VCF services runtime', '部署時建立'],
  ['vcf-m03-vidb', '10.0.1.70', 'Identity Broker', '部署時建立'],
  ['vcf-m03-inst01', '10.0.1.71', 'VCF Installer', '測試前存在'],
  ['vcf-m03-shared01', '10.0.1.74', 'Instance components', '部署時建立'],
  ['(IP pool)', '10.0.1.80-95', 'VCF Management Services IP Pool', '16 個'],
], [26, 20, 36, 18]));
add(NOTE('converge 路徑不需要 vMotion / vSAN / NSX overlay 的網段規劃 —— 那些全部從既有叢集繼承。只有 VCF Management Services IP Pool 要自己給。'));
add(PB());

// ============================ 附錄 B ============================
add(H1('附錄 B:兩條路徑的 spec 對照'));
add(P('同一個精靈,Plan 階段勾不勾既有元件,產生的 deployment spec 差異極大。'));
add(H2('greenfield(什麼都不勾)'));
add(CODE([
  '"vcfOperationsSpec": { ..., "useExistingDeployment": false,',
  '                       "nodes": [ master + replica ] },   // 強制兩節點',
  '"vcenterSpec":       { ..., "useExistingDeployment": false },',
  '"sddcManagerSpec":   { ..., "useExistingDeployment": false },',
  '"vcfAutomationSpec": { ..., "useExistingDeployment": false },',
  '"licenseServerSpec": { "hostname": "vcf-m03-lic01.home.lab" },',
  '"hostSpecs": [...], "clusterSpec": {...}, "datastoreSpec": {...},',
  '"dvsSpecs": [...],  "networkSpecs": [...]',
].join(String.fromCharCode(10))));
add(H2('converge(勾既有 Operations + vCenter)'));
add(CODE([
  '"vcfOperationsSpec": { "useExistingDeployment": true,',
  '                       "nodes": [{ "hostname": "vcf-m03-ops01.home.lab",',
  '                                   "sslThumbprint": "6D:8F:B7:...",',
  '                                   "type": "master" }] },   // 單節點就夠',
  '"vcenterSpec":       { "vcenterHostname": "vcf-m03-vc01.home.lab",',
  '                       "sslThumbprint": "5E:3E:07:...",',
  '                       "useExistingDeployment": true },',
  '"sddcManagerSpec":   { "useExistingDeployment": false },   // 新部署',
  '"nsxtSpec":          { "nsxtManagerSize": "medium",',
  '                       "nsxtManagers": [ 1 台 ],',
  '                       "useExistingDeployment": false },',
  '',
  '// 以下 key 整個不存在:',
  '//   licenseServerSpec  — 既有 Operations 已經有 License Server',
  '//   vcfAutomationSpec  — 選了「稍後再接」',
  '//   hostSpecs / clusterSpec / datastoreSpec / dvsSpecs / networkSpecs',
  '//                      — 全部繼承既有叢集',
].join(String.fromCharCode(10))));
add(GOOD('兩份 spec 都是精靈自己產生的(Review 頁 → DOWNLOAD JSON SPEC),不是手改的。這是「UI 有沒有支援」最直接的證據。'));
add(PB());

// ============================ 附錄 C ============================
add(H1('附錄 C:UI 自動化筆記'));
add(P('本文的操作與截圖以 Python Playwright 連上既有的有頭 Chrome(CDP 9222)完成,保留登入狀態與截圖品質。以下是過程中踩到、值得記錄的細節。'));
add(table(['症狀', '真因', '解法'], [
  ['下拉選單(ACTIONS、DEPLOYMENT WIZARD)點不開', 'Clarity 的 dropdown toggle 不吃合成滑鼠事件', '元素 focus() 後送鍵盤 Enter,而且要含 char 事件'],
  ['選單開了但項目點不下去', '選單項目反過來只吃 DOM 事件', 'pointerover→pointerdown→pointerup→click→el.click() 整串'],
  ['欄位有字但驗證永遠 invalid', 'Input.insertText 不會讓 Angular form control 變 dirty', '逐字送 keyDown/keyUp(帶 text)'],
  ['打 home.lab 變成 homelab', 'charCodeAt 當 VK:"." 是 46,而 VK 46 = Delete', '只有 A-Z0-9 給正確 VK,其餘給 0'],
  ['toggle 點不到', '對話框會非同步重新排版,座標會變', '點之前重新量 getBoundingClientRect'],
  ['以為精靈沒開,結果疊開了 4 個', 'modal 內容不會出現在 document.body.innerText', '查 .modal-dialog 或直接截圖判斷'],
  ['NEXT 按鈕定位不到', 'class 每一步都不同,DOM 文字是 " Next "(大寫是 CSS)', '用 innerText 找「可見且未 disabled」的那一顆'],
], [30, 36, 34]));
add(GOOD('結論:Clarity/Angular 的 UI 自動化不要自己刻 CDP 事件。Playwright 的 locator 會自動等待可操作狀態並送真實事件,上面七項有六項直接消失。'));


// ============================ 組檔 ============================
const doc = new Document({
  styles: { default: {
    document:  { run: { font: 'Microsoft JhengHei', size: 21 } },
    heading1:  { run: { font: 'Microsoft JhengHei', size: 30, bold: true, color: C.blue } },
    heading2:  { run: { font: 'Microsoft JhengHei', size: 25, bold: true, color: C.blue } },
    heading3:  { run: { font: 'Microsoft JhengHei', size: 22, bold: true, color: C.gray } },
  } },
  sections: [{ properties: { page: { margin: { top: 1000, bottom: 1000, left: 1000, right: 1000 } } }, children: body }],
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUT, buf);
  console.log('OK ->', OUT, (buf.length / 1024 / 1024).toFixed(2) + ' MB');
  console.log('圖數 =', figNo);
  if (missing.length) { console.log('🔴 缺圖 ' + missing.length + ' 張:'); missing.forEach(m => console.log('   ' + m)); }
  else console.log('所有圖都找到了');
}).catch(e => { console.error('FAILED', e); process.exit(1); });
