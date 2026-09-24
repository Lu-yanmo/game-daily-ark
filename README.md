# 明日方舟端游每日清体力（MAA + 计划任务，无人值守）

每天 08:00 / 20:00 自动把方舟端游的日常跑完：**公招 / 基建 / 信用 / 领奖 + 把当天理智刷干**，
跑完自动收尾（关 MAA、关端游）。理智刷什么由脚本判断：有活动刷活动图，长草刷常驻材料本。

用的还是 **MAA** 本身 —— 这里只做「今天该刷什么 → 改 MAA 配置 → 拉起端游和 MAA → 看日志判断结果 → 收尾」。

---

## 0. 用之前先看这三条

- **本仓库只有 PowerShell 脚本，不含 MAA、不含端游客户端、不含任何游戏素材。** MAA 是 AGPL-3.0 的第三方软件，端游要你自己从官方渠道装（许可见 [第 8 节](#8-许可免责与隐私)）。脚本只是启动 MAA、读它的日志和配置文件。
- **游戏用户协议禁止脚本/自动化。** 这类工具在圈子里被默认容忍 ≠ 官方许可；处罚风险由使用者自行承担，建议只在个人账号上用。
- **判定逻辑和 MAA 版本强耦合。** MAA 升级后改了 `gui.log` 文案或配置字段，判定就可能失效，所以脚本在「日志在涨却一条认识的标志都没有」时明确报 `unknown-format`，并且**不会**据此判定日常已清完。看到这个状态按 [第 6 节](#6-出问题怎么查) 对一遍日志再更新 `lib\maa.ps1` 里的正则。

**默认策略里有两条是硬编码的偏好，先说在前面**：

- **不吃理智药**：脚本每次都会把 `UseMedicine / UseStone / UseExpiringMedicine` 压成 `false`。
- **不自动打没确认过的活动**：版本更新出了新活动、你还没手动通一遍时，本轮只跑非战斗部分（公招/基建/信用/领奖），理智留着，等你确认（第 3 节门 1）。

## 1. 四个入口

| 想做什么 | 怎么做 |
| --- | --- |
| 看今天会怎么跑（**什么都不改、不启动**） | `pwsh -File status.ps1` 或 `pwsh -File daily-clear.ps1 -DryRun` |
| 手动跑一轮（**注册过任务后不再弹 UAC**） | 双击 `run-daily.cmd`，等价于 `pwsh -File run-via-task.ps1` |
| 每天按 `config\settings.json` 里 `schedule.times` 的时间自动跑 | `pwsh -File install-task.ps1`（注册计划任务，弹一次 UAC） |
| 不想记命令，只想瞟一眼今天怎么样 | 双击 `panel.cmd`（图形状态面板，见第 1.1 节） |

### 1.1 图形状态面板（`panel.cmd` / `tools\panel.ps1`）

一屏显示：今天会刷什么、两道手动门的状态、定时任务下次几点跑、上一轮结果；
按钮上留着：今天会跑什么（预演）/ 开始跑一轮 / 环境体检 / 我打过活动了 / 商店已领空 / 打开日志目录。

面板**只是外壳**：每个按钮都是去调上面那几个脚本，不自己算结论，所以面板里看到的和命令行跑出来的是同一个。
「开始跑一轮」要连点两次才真的开跑。不想用鼠标的人可以 `pwsh -File tools\panel.ps1 -SelfTest`（不显示窗口，
把状态摘要、参数探测、布局检查打出来）。打包成 exe 的场合对应动词是 `--panel`。

命令行常用姿势：

```powershell
.\daily-clear.ps1 -DryRun              # 预览：今天判定成什么、将要改哪些配置
.\daily-clear.ps1                      # 真跑一轮（会弹一次 UAC，除非走计划任务通道）
.\daily-clear.ps1 -Ack                 # 「新活动我手动打过了」→ 之后每天自动刷活动图
.\daily-clear.ps1 -ShopDone            # 「活动商店我已领空」→ 之后不再刷活动，剩余理智转长草
.\daily-clear.ps1 -ShopReset           # 误标了/活动又开新一批兑换 → 撤销领空标记
.\daily-clear.ps1 -Stage SK-5          # 临时指定刷某个关卡
.\daily-clear.ps1 -SkipCleanup         # 跑完不关端游（自己接着玩）
.\daily-clear.ps1 -NoElevate           # 禁止自动提权（只想看输出）
```

退出码：`0` 全部完成 / `1` 部分完成 / `2` 失败。运行日志在 `logs\`，历史汇总在 `state\history.csv`。

**为什么需要管理员**：明日方舟端游要管理员权限，MAA 未提权时连不上它（Windows UIPI 挡住输入注入），
表现是 MAA 一直停在「正在连接模拟器……」。三条路：

1. **计划任务通道（推荐，注册一次以后不再弹）**：`install-task.ps1` 除了两个每日任务，还会注册一个无触发器的
   按需任务（同样最高权限）。`run-via-task.ps1` 只负责点火、跟日志、回传退出码 —— 普通权限就能触发自己账号下的
   最高权限任务，所以**不弹 UAC**。按需任务不存在时自动退回直跑。
2. **自我提权**：直接跑 `daily-clear.ps1` 时若不是管理员，用同样参数以管理员身份重启自己，等子轮结束原样返回退出码（弹一次 UAC）。
   pwsh 若是 Microsoft Store(WindowsApps) 版，系统不允许直接对它提权，脚本会改用 `System32\cmd.exe` 做提权载体（UAC 上显示 cmd.exe，属正常）。
3. **`-NoElevate`**：不提权直跑，只对手动场景有意义（端游那一路大概率连不上）。

## 2. 每天到底刷什么（自动判定）

读 MAA 官方活动接口 `api.maa.plus/.../StageActivityV2.json`（拉不到就退回 MAA 本地缓存 `cache\gui\StageActivityV2.json`）：

- 有进行中的活动关卡 → 理智全刷活动图（活动代币优先）；标记过「商店已领空」的活动会被跳过（第 3 节门 2）；
- 没有活动（长草）→ 按 `config\settings.json` 的 `ark.defaultStage` / `planByWeekday` 刷，默认 `CE-5,LS-5`
  （龙门币 + 经验，都是每天开放的常驻本；MAA 的「剩余理智」会按列表顺序把理智刷干）；
- 关卡代号建议对着 MAA 自带 `resource/stages.json` 核一遍再填。**材料本轮哪几天开放由游戏服务端决定，脚本不猜**：
  想固定刷某种材料，就把当天开放的关卡代号写进 `planByWeekday`（键 `1`=周一 … `7`=周日）。

### 2.1 被弹窗挡住时的视觉兜底（可选，默认开着）

MAA 认界面靠模板匹配，**它的模板集里没有的东西它就看不见**。最常见的坑：版本更新后端游启动画面上盖一层新活动公告，
「START」按钮被压在下面 —— MAA 会一直点，点几百次也不动，`gui.log` 却一个字都不再吐，于是这一轮被判 `stalled`。

判到卡住之后、宣布失败之前，脚本可以做一次兜底：把端游窗口截一张图交给视觉模型，让它回答「有什么挡住流程的东西、
该点哪里关掉」，然后由脚本在管理员通道里点那一下，并再拍一张比对，确认画面真的变了（没变就算没成功，不会连着点）。

点那一下走的是**真实鼠标**（把端游窗口切到前台 → 移动指针 → 按下/松开左键 → 指针回到原来的位置），
不是往窗口发消息：这个端游自己渲染鼠标、只认真实输入，实测过消息发成功、坐标也压在按钮上，弹窗却不动。
所以兜底发生的瞬间你会看到游戏窗口跳到最前、鼠标动了一下 —— 不想被打断就别在用它的时候手动跑这一轮。
窗口如果被最小化了，脚本会先把它恢复再截图（最小化时拍到的只会是一张空图）。

- **只在异常路径触发**：正常一轮一个网络请求都不发。默认每轮最多兜底 2 次（`runtime.visionMaxRescue`）。
- **只准点「关闭」这一类**：提示词硬性禁止点领取 / 前往参与 / 确定这类会推进游戏状态的按钮，每次最多 1 击，
  坐标超出客户区或落在标题栏一律拒掉；抢不到前台时就退回发消息（宁可点不动，也不会把真实点击打进你正在用的窗口）。
- **要额外配一样东西**：一个视觉模型的 API key（阿里云百炼 / DashScope）。填 `runtime.visionApiKey`
  或设环境变量 `DASHSCOPE_API_KEY`（环境变量优先，`settings.json` 不入版本库）。**没有 key 就不兜底**，
  只按原来的方式说明原因，不会报错卡住；不想用就把 `runtime.arkVisionRescue` 改 `false`。
- **地址可以换**：`runtime.visionBaseUrl` 不限于百炼公共端点，任何兼容 OpenAI 的 chat/completions 接口、且**能接受图片输入**的
  服务都行（自建网关、套餐网关都可以）。末尾只写到 `/v1` 也没关系，脚本会自己补上 `/chat/completions`。
  模型名以那个服务实际支持的为准（`runtime.visionModel`，一般 `GET <base>/models` 能列出来）——写了它不支持的名字会直接
  404 `Model not exist`，那种情况下兜底只留一句"模型调用失败"就放弃，不会连着重试。
- **隐私**：兜底那一刻会把端游窗口的一张截图 POST 到 `runtime.visionBaseUrl` 指向的接口（默认是 DashScope 的
  OpenAI 兼容地址）。窗口里当时显示什么就可能发出去什么，所以这一步只在「已经卡住」时发生，且日志里不会记录 key。
- 模型默认 `qwen3.8-flash`（`runtime.visionModel`），换任何支持图片输入的 OpenAI 兼容模型都可以，只要它认这个响应格式。
- 兜底试过没成功，失败结论里会带一句「视觉兜底试过 N 次，最后一次……」；这条链子的离线自检在 `tools\test-ark.ps1` 的 `[t13]`
  （全程不联网、不截图、不点击）。

## 3. 两道手动门：活动确认 + 商店领空

**门 1：活动确认**（「版本更新了但我还没打活动关卡就先别刷」）

```powershell
.\daily-clear.ps1 -Ack -DryRun    # 只登记确认，不跑
.\daily-clear.ps1 -Ack            # 登记确认 + 顺手跑一轮
```

确认状态存在 `state\ark-event-ack.json`（按活动 id 记，一个活动确认一次）。不想用这道门：
`config\settings.json` 里 `ark.eventRequiresAck` 改 `false`。临时越过用 `-Force`。

**门 2：商店领空**（「活动商店换完了就别再刷活动了」）

```powershell
.\daily-clear.ps1 -ShopDone       # 标记当前活动商店已领空
```

之后每一轮该活动被从候选里剔除，剩余理智改刷长草计划；还有别的已确认活动时会自动改刷那个。
标记按活动 id / 版本号记（`state\ark-shop-done.json`），新版本或新活动自动不适用，**不用记得回来取消**；恢复刷活动用 `-ShopReset`。
不想用这道门：`ark.shopDoneStopsEvent` 改 `false`。

这道门必须手动：MAA 的活动接口只给「活动在不在开、哪些关掉代币」，看不到你的商店兑换进度；
游戏里也没有可靠的「商店已空」信号（MAA 日志里根本没有活动商店相关记录），猜出来的只会误判。

## 4. 首次使用（新机器上一次性）

0. **生成配置**：仓库里只有 `config\settings.example.json`（`settings.json` 被 `.gitignore` 排除，见第 8 节）。

   ```powershell
   pwsh -File setup.ps1 -DryRun     # 只看探测到什么，不写文件
   pwsh -File setup.ps1             # 探测 + 写入 config\settings.json
   pwsh -File setup.ps1 -MaaDir "D:\Tools\MAA" -ArkExe "D:\Games\Arknights\Arknights.exe"   # 探测不到就手工指定
   ```

   探测优先级：**命令行指定 > 现有 `settings.json` 里仍有效的路径 > 正在运行的进程 > 卸载表 > 固定磁盘浅层扫描**。
   每项都打印来源，`Downloads\`、`xx (2)\` 这类副本目录会被排到最后并标注。退出码 `2` = 还有必填项没填（手填也可以）。
   **脚本只保证「路径存在」，不保证那是你想用的那份 MAA 配置**，探测完一定看一眼输出。

1. **允许一次 UAC**：跑 `install-task.ps1` 时点「是」，之后定时和双击 `run-daily.cmd` 都不再弹。
2. **端游由脚本拉起**：MAA 的配置里其实没存端游路径（`StartGame=true` 也只会报「未找到窗口」），所以 `daily-clear.ps1`
   会先启动 `paths.arknightsExe` 指向的端游、等窗口出现、再把 `StartGame` 关掉后启动 MAA 去连。
   端游退出后需要重新登录/更新的话，日常会卡在这一步（报 `not-started` 并通知你，时限 `runtime.arkStartTimeoutMinutes`）。
3. **不要锁屏**：保持登录、允许熄屏即可（运行期间脚本临时顶住睡眠和熄屏，跑完恢复）。
   设了「无人操作自动锁屏」请先关掉 —— 锁屏 = 桌面不可用 = 截图失败。
4. MAA 那边不需要额外设置，脚本每轮直接改它的配置文件（改前都在 `backups\` 留副本）。

## 5. 计划任务

```powershell
pwsh -File install-task.ps1 -DryRun            # 先看要建什么
pwsh -File install-task.ps1                    # 注册两个每日任务 + 一个按需任务
pwsh -File install-task.ps1 -Times 07:30,19:30
pwsh -File install-task.ps1 -Uninstall
```

任务跑在**当前用户会话**里（MAA 要连本机 GUI，所以「只在登录时运行」），并以**最高权限**运行
（注册这种任务本身要提权，脚本自动弹 UAC）。错过时间点会尽快补跑（`StartWhenAvailable`），单次最长 3 小时被强杀。

## 6. 出问题怎么查

- `pwsh -File status.ps1` —— 环境、进程、今天判定、MAA 队列、确认状态、最近记录，一次看完。
- `pwsh -File tools\test-ark.ps1` —— 纯逻辑自检（只读：不改配置、不启动任何程序、不发网络请求），106 条断言，`powershell.exe -File` 同样能跑。
  改过 settings 或判定代码后跑一遍最放心。
- `pwsh -File tools\probe-decisions.ps1` —— 把活动接口逐条窗口打出来，怀疑判定不对时看这个。
- MAA 自己的日志：`<maaDir>\debug\gui.log`（目录见 `config\settings.json` 的 `paths`）。
  **gui.log 静默的时候 `debug\asst.log` 往往还在写** —— 那是 MAA 内核的流水账，里面的
  `"cur_task"` / `"exec_times"` / `Win32Controller click` 能告诉你它到底卡在哪个子任务、在同一点上重复了多少次
  （脚本判到卡住时会把这条线索直接写进结论，`paths.maaAsstLog` 可改路径）。
- 被脚本改过的配置都在 `backups\` 留了最近 20 份，出问题直接覆盖回去即可。

判定规则小结：

| | 成功 | 卡住 |
| --- | --- | --- |
| MAA | `gui.log` 出现 `任务已全部完成！` | MAA 自己的「日志无更新/停滞」告警，或 22 分钟无新日志（`stalled`，宣布之前会先试一次[视觉兜底](#21-被弹窗挡住时的视觉兜底可选默认开着)）；端游没被拉起且无链路完成（`not-started`）；日志在涨却一条标志都没认出 → `unknown-format` |

`unknown-format` 是唯一「结果不可信」的状态：它不猜原因，只告诉你别按这一轮判定理智是否清完。

失败会自动重试一次（`runtime.retryOnce`），但 `not-started` / `unknown-format` 不重试（重试只是白等）；再失败就收尾 + 弹通知，不会整晚挂着。

## 7. 文件结构

```
  setup.ps1            第一次用：探测 MAA / 端游装在哪 → 生成 config\settings.json
  daily-clear.ps1      编排：判定 → 改配置 → 拉起端游 + MAA → 重试 → 收尾 → 通知
  status.ps1           只读体检
  install-task.ps1     计划任务注册/卸载
  run-daily.cmd        双击手动跑
  panel.cmd            双击打开图形状态面板（转调上面那些脚本，见第 1.1 节）
  config\settings.example.json  配置模板（入仓）
  config\settings.json  唯一需要配的文件（不入仓）
  lib\common.ps1       日志/JSON/备份/防睡眠/进程/通知
  lib\detect.ps1       安装位置探测：进程 → 卸载表 → 磁盘浅层扫描
  lib\decisions.ps1    今天刷什么：活动窗口、确认门、关卡校验
  lib\maa.ps1          MAA 队列改写 + 启动 + gui.log 判定
  lib\vision-rescue.ps1 卡住时的视觉兜底（截图→模型→点一下关闭；见第 2.1 节，不想要就关）
  tools\panel.ps1      面板本体（-SelfTest 不显示窗口，给自动化验证用）
  tools\               自检 / 探测脚本
  logs\ state\ backups\  运行时生成（不入仓）
```

依赖：PowerShell 7（`pwsh`）最省事，但**没装也行**——本仓库的脚本 Windows PowerShell 5.1（系统自带）和 7 都能跑，
`run-daily.cmd` 会自己挑一个能用的引擎；下文示例里的 `pwsh` 换成 `powershell` 是同一条命令。
不放心可以跑 `tools\check-ps51.ps1` 自检（在 5.1 里跑出来的结论才算数）。不需要 adb。

## 8. 许可、免责与隐私

**许可**：本仓库脚本按 MIT 发布（见 `LICENSE`），只含原创 PowerShell 代码。

**不含第三方程序**：MAA（AGPL-3.0）、明日方舟端游客户端及其素材/名称都**不**在本仓库内，也不由本仓库分发，
请自行从官方渠道安装。MAA 的许可条款以它自己的仓库为准，本仓库的 MIT 不改变也不覆盖它们的要求。

**免责**：软件按「现状」提供，不含任何明示或暗示的保证。游戏用户协议禁止脚本与自动化，
使用本仓库可能带来账号处罚、时间损失或数据损失，风险由使用者自行承担。

**隐私与脱敏**：`.gitignore` 排除了这几类内容，因为里面是你的机器和个人信息 ——
`config\settings.json`（绝对路径、`notify.webhook`）、`logs\`（每轮时间点/耗时/失败原因，攒起来是作息表）、
`state\`（历史汇总、你参与过的活动 id 与版本号）、`backups\`（MAA 配置历史副本，可能含账号字段）。
克隆下来只会得到模板，跑 `setup.ps1` 生成自己的配置。**别把这些目录重新加进版本库，也别把日志原样贴进 issue**，
需要贴的先自己打码。

**这个仓库往外发的东西一共三处**，都不带密钥：① 判定活动时 `ark.activityApiUrl` 那一次 GET（就是 MAA 自己也在用的公开接口）；
② 你填了 `notify.webhook` 才发的每轮结果；③ [第 2.1 节](#21-被弹窗挡住时的视觉兜底可选默认开着)兜底时的一张端游窗口截图
（要你自己配了模型 key 才会有，没配就是不发）。除这三处之外脚本不联网。
