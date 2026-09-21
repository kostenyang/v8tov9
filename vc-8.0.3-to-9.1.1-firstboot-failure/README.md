# vCenter 8.0.3 → 9.1.1 GUI 升級在 firstboot 失敗：根因、Lab 重現、三種修復（含 RDU）

客戶（VCD 環境，vCenter 為 VCF 納管但 SDDC Manager 已壞，改走 standalone 升級）用 GUI installer 從 8.0.3 升 9.1.1，Stage 2 在 firstboot 第 2 步 `vmafd-firstboot` 失敗：

```
ldap3.core.exceptions.LDAPSocketOpenError: socket connection error while opening: [Errno 111] Connection refused
Failed to start services. Firstboot Error.
```

本目錄是從 support bundle 追根因 → 用客戶備份在 lab 還原出同一套 inventory 重現 → 三種修復都實測過的完整記錄（2026-09-21）。交付文件在 [`doc/`](doc/)。

> 🔑 密碼一律已改成 `<PLACEHOLDER>`；主機名為客戶內部命名（`tko-*.evs.vs.local`），IP 為 lab 私網。

---

## 🏆 根因一句話

**Stage 1（部署新 appliance）完成後新機被關機，10 天後再開機跑 Stage 2。** 9.1.1 的 rpminstall 已把 `lwsmd / vmafdd / vmcad / vmdird` 設為開機自啟，重開機後這四個服務在 firstboot 之前就以「空 DB」狀態跑起來；firstboot 匯入舊 vCenter 資料後只做 `systemctl start`（已 active → no-op，**沒有 restart**），舊的 stale 程序留在原地：

| 服務 | stale 的後果 | log 證據 |
|---|---|---|
| vmdird | 沒開 389 port（等第一次 replication）→ `open_ldap_connection` Connection refused | `vmdird.log: Have NOT yet started listening on LDAP port (389)` |
| vmafdd | 讀不到 firstboot 換進來的新 `afd.db`（EACCES）→ `vecs-cli force-refresh` Error 14 | `vmafdd.log: lstat(/storage/db/vmware-vmafd/afd.db) (13) / Failed to update trusted roots. Error [14]` |

程式碼位置（新機 `/usr/lib/vmware-vmafd/firstboot/identityinstall/`）：

- `vmdirUpgrade.py:498 start_upgrade()` → `import_data_files()`（rmtree + copytree data.mdb）→ … → `upgrade_maintenance_delete_legacy_schema()` line 112 → `open_ldap_connection()` line 855 ← 失敗點
- `LinuxUtils.py:126 start_service()` → `systemctl start vmdird` + `lwsm status` 看到 `running` 就當成功（stale 程序也回 running）

失敗後 `invoke_upgrade.sh` 的 `error_exit → exit_cleanup` 會跑 `/bin/prune-sensitive-info`，**刪掉 15 個密碼類 install parameter**（bundle 裡的「Pruning sensitive information」）— 這是就地修復要先補回參數的原因。

## Lab 重現（逐行相同）

1. 客戶 `vCenter.zip`（file-based backup）→ VCSA 8.0 U3g GUI installer **Restore**（PNID 不能改、IP 可以改；匿名 FTP 餵備份）。
2. 同一支 9.1.1 ISO（25712839）GUI 兩階段升級；Stage 1 完成後 `govc vm.power -off`（確認 poweredOff）再 `-on`。
3. Stage 2 → firstboot 失敗，traceback **同檔同行號**（919 → 518 → 112 → 779 → 855）、vmdird / vmafdd 的兩條 log 也一樣。

> lab 沿路踩到的 precheck 坑（都跟根因無關、客戶也遇過同類）：暫時 IP 不能有既存 PTR、來源 NTP 不能是 169.254.x、CEIP/analytics 警告（KB 311872）重跑就過、VCF SDDC Manager WARNING 不擋。**重設 SSO 密碼會害 Stage 2「Unable to authorize user」**，要用原密碼。

## 三種修復（都實測）

### A. 回復舊機、重跑（官方路徑）
export 只停服務+關機，來源資料沒動：關新機 → 開回舊 8.0.3 → 重跑 Stage 1 → **立刻**接 Stage 2。Lab 實證開回來服務全起、SSO 登入 OK。

### B. 在失敗的新機上就地修復（lab 實證、非官方）
腳本在 [`scripts/`](scripts/)：

1. `restore_params.sh` — 用原始密碼把被 prune 的參數直接 `printf > /etc/vmware/install-defaults/<key>`（`/bin/install-parameter` 在非 login shell 會靜默失敗）。
2. **`systemctl stop vmdird vmcad vmafdd lwsmd`**（四個全停；只停 vmdird 會過了 vmdir 再卡 vmafd Error 14）、移走 `/var/log/firstboot/failed`。
3. `resume_upgrade.sh` — mount `/dev/sdb` → `source common-install.sh` → `prune_sensitive_param=False` → `firstboot`（18 分）→ `upgrade_import`（6 分）→ `post_install_cleanup` → `configured`。
4. 手動 `/bin/prune-sensitive-info` + `release_temp_addresses.sh`。

結果：firstboot 45/45、import SUCCESS、9.1.1 build 25712839、客戶 inventory 1 DC / 1 cluster / 4 host / 23 VM 全在。

### C. ★ 回復舊機後改用 RDU（建議）
從來源 8.0 U3 的 vSphere Client 驅動（vCenter 物件 → 更新 → vCenter Server → 升級），ISO 掛 CD-ROM 即可。自動部署 → 複寫 → 切換，**沒有兩階段之間可以被關機的空窗**。Lab 從客戶備份還原的 8.0.3 → 9.1.1：

| 時間 (UTC) | 階段 |
|---|---|
| 13:06 | 開始（外掛先 8.0.3.00600 → 9.1.1.0，UI 自動重載）|
| 13:11 | OVA 部署，新機開機（暫時 IP）|
| 13:11–13:31 | 72%「Deploying the new version appliance」（新機 firstboot）|
| 13:32 | 複寫 |
| 13:33 | 自動切換：vSphere Client 503 → 跳到 `/lcm-ui/?view=standaloneUi` |
| 13:39 | **100% vCenter upgrade completed successfully**（33 分、停機約 5 分）|

截圖在 [`shots/`](shots/)。切換方式可選 Automated / Manual / Scheduled。

**KB 396777 真的會踩**：來源若曾用 file-based backup 還原（lab 就是），`/var/cache/svcaccounts/vsphere-ui/.vsphere-ui` 不存在，RDU 切換時 vsphere-ui 起不來 → 先在來源跑 `scripts/fix-vsphere-ui-svcaccount.py`（KB 原文腳本）。

## 第二輪(2026-09-22):逐步圖解手冊 + 三個新坑

用客戶備份再 restore 一台乾淨的 8.0.3(`chtvcd-src2`),把 **方式 B(就地修復)** 和 **方式 A(回復重跑)** 各完整走一遍,每一步都截圖(GUI installer + appliance console):[`doc/vCenter-9.1.1-Upgrade-Failure-StepByStep.docx`](doc/)(41 頁)、截圖在 [`shots/stepbystep/`](shots/stepbystep/)、console 用的短腳本在 [`scripts/fix/`](scripts/fix/)。

這一輪新踩到的:

| 坑 | 結果 |
|---|---|
| **Step 0:要等 installer 的失敗清理跑完** | Stage 2 顯示 traceback 後,`invoke_upgrade.sh` 的 `exit_cleanup` 還在背景跑 1–3 分才 `prune-sensitive-info`;太早補參數會被再刪一次 → firstboot 在 `vmidentity-firstboot` 報 `Install-parameter vmdir.password not set`。`scripts/fix/0-wait.sh` 等 `invoke_upgrade` 消失、密碼參數只剩 `db.password_services` 再動手 |
| **就地續跑只能跑一次** | 第一次 resume 中途失敗後,再 resume 會在 `vpostgres-firstboot`「Upgrade import step failed」:第一次已把匯出的 DB 消耗掉並初始化 vpostgres(留下 `vpostgres.backup.*`),無法重匯 → 續跑中途失敗就改走方式 A |
| **RDU 過的舊機不能再當 GUI 升級的來源** | RDU「Expanding the source configuration」會把來源 VCDB schema 就地升到 9.1(`vc.vpx_version=911`),之後 GUI 的 vpxd_firstboot in-place VCDB upgrade 撞 `vsan_historical_cluster` unique constraint。RDU 切換時還會把舊機退役(暫時 IP + `[Link] Unmanaged=true`、hostname=localhost、mask lwsmd/vmafdd/vmdird/vmcad、vmon `.state_*.json` 全 DISABLED)— rollback 不是開機就好 |

方式 A 實測:關新機 → 開回舊機(服務全起、23 VM)→ Stage 1(10 分)→ **立刻 CONTINUE** → Stage 2(export 7 分 + firstboot 9 分 + import 5 分)→ Complete。

## 檔案

| 檔案 | 說明 |
|---|---|
| [`doc/vCenter-8.0.3-to-9.1.1-Upgrade-Failure-RCA.docx`](doc/) | 交付文件（17 頁：摘要 / 時間軸 / 根因 / 重現 / 三種修復 / 建議 / 附錄）|
| `scripts/resume_upgrade.sh` | 就地續跑 firstboot → import → cleanup |
| `scripts/restore_params.sh` | 補回被 prune 的 install parameter（範本，填自己的密碼）|
| `scripts/fix2.sh` | 停四個 stale 服務 + 清 failed 標記 + 啟動續跑 |
| `scripts/evidence.sh` | 從新機抓 traceback / journal / vmafdd.log / firstbootStatus 證據 |
| `scripts/fix-vsphere-ui-svcaccount.py` | KB 396777 修復腳本 |
| `scripts/cdp-frame.mjs` | 🔧 用 CDP 在 vSphere Client **plugin iframe**（藏在 shadow DOM）的 context 跑 JS — 主頁面 `querySelectorAll('button')` 找不到精靈按鈕就是這個原因；精靈 modal 又是另一個 frame（`prepare-target-wizard` / `schedule-upgrade`）|

## 給客戶的建議

1. 關掉失敗的新機、開回舊 8.0.3，**改用 RDU** 升 9.1.1；升級前 `ls /var/cache/svcaccounts/vsphere-ui/.vsphere-ui`。
2. 若仍走兩階段 GUI/CLI：Stage 1 完成後**不要**關機 / 重開 / 還原快照，直接 Stage 2；真的重開了，Stage 2 前先 `systemctl stop vmdird vmcad vmafdd lwsmd`。
3. 向 Broadcom 開 case 確認 `vmdirUpgrade / vmafdUpgrade` 在服務已 active 時不 restart 是否為已知問題（9.1.1 build 25712839）。
