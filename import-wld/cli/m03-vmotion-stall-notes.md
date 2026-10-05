# m03 vMotion 停滯的真正原因:實體 CPU 超配(2026-10-05)

## 症狀
- vLCM remediate esx01 卡在 EnterMaintenanceMode 2%,超過 1 小時
- 手動 `vm.migrate` 也永遠停在 0%
- vCenter 事件只說 "Hot migrating ... " 之後沒有下文

## 排除過的(都不是原因)
| 檢查 | 結果 |
|---|---|
| vmk0 / vmk1 ICMP | 通,50 包 0 丟失 |
| 1472 與 8972 不分片 | 都通 |
| vmk MTU | 1500 → 改 9000 對齊 m02,仍卡 |
| 外層 `Trunk-Nobinding` SecurityPolicy | promisc / forged / macChange 全 True(正常) |
| VM CD-ROM | Connected=false,不是 `_ovfenv.iso` 擋熱遷移那個坑 |
| vMotion 防火牆規則 | enabled |
| TCP 8000 | 連線 ESTABLISHED,走專用網段 192.168.35.x |

## 真正的原因
`esxcli network ip connection list` 顯示:
```
esx01  Send-Q 545828  192.168.35.11:63389 -> 192.168.35.14:8000  ESTABLISHED
esx04  Recv-Q  80532  192.168.35.14:8000  <- 192.168.35.11:63389 ESTABLISHED
```
資料送得出去也收得到,但**收端的 vmotionStreamHelper 沒在消化**,最後
`vob.vmotion.stream.keepalive.read.fail ... possibly due to timeout`。

量實體主機:
```
host95  32 實體核心  CPU 66154/79999 MHz = 83%
  m02 4 × 24 vCPU = 96
  w01 3 × 16 vCPU = 48
  m03 4 × 16 vCPU = 64
  其他             =  8
  合計 216 vCPU / 32 核 = 6.75:1
```
同一台實體機上兩台 nested ESXi 之間 RTT **7 ms**(正常 <1 ms)= CPU 嚴重排隊。
vMotion(尤其加密)很吃 CPU,worker world 被餓死 → 串流推不動 → keepalive timeout。

m02 當初升主機會動,是因為那時 w01 / m03 都還不存在。

## 解法
關掉不需要的 nested 環境釋放 CPU(只是關機,可逆):
- w01 3 台 → 釋出 48 vCPU / 288 GB
- m02 4 台 + installer → 釋出 96 vCPU / 786 GB

## 順手修正的既有問題
`E:\9.1\converge-target\Toggle-TrunkPromiscuous.ps1` 寫的是 `MacManagementPolicy`,
但外層 `Trunk-Nobinding` 實際用的是 `SecurityPolicy` → 那支腳本在這個 portgroup 上無效
(讀回來前後都是空值)。要改政策得走 `DefaultPortConfig.SecurityPolicy`。
