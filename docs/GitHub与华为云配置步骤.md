# GitHub 与华为云配置步骤（照着做即可）

> 这份是**操作手册**，只写「点哪里、填什么、怎么验证」。
> 账号相关的操作必须你本人登录后完成，我没法代点；代码和配置我已经准备好（见第四、五节）。

---

## 一、GitHub 开启双因素认证（2FA）

GitHub 现在强制 2FA，不开会导致推送失败。

1. 浏览器登录 https://github.com/
2. 右上角头像 → **Settings**
3. 左侧 **Password and authentication**
4. 找到 **Two-factor authentication** → 点 **Enable two-factor authentication**
5. 选择方式（二选一）：
   - **Authenticator app（推荐）**：手机装 Microsoft Authenticator / Google Authenticator / 1Password，扫描页面二维码 → 输入 App 显示的 6 位数字
   - **SMS number**：输手机号收短信验证码（部分虚拟号段不支持）
6. 点 **Download** 把 **恢复码（recovery codes）** 存到本地（`D:\` 或网盘），这串只能用一次，丢了锁号很麻烦
7. 完成后刷新页面，`Two-factor authentication` 应显示 **Enabled**

**验证标准**：退出登录再登入，要求输入 6 位验证码，输入正确即通过。

---

## 二、创建 Personal Access Token（PAT）

开了 2FA 后，命令行 `git push` 不能用账号密码，要用 token 当密码。

1. 头像 → **Settings** → 左侧最下 **Developer settings**
2. **Personal access tokens** → **Tokens (classic)** → 右上 **Generate new token (classic)**
3. 填写：
   - **Note**：`SE-Lab-自习室`（随便起，方便以后识别）
   - **Expiration**：30 days 或 90 days（课程项目够用）
   - **Select scopes**：勾 **`repo`**（必勾，含读写仓库）；如果仓库要跑 GitHub Actions，再勾 **`workflow`**
4. 点 **Generate token** → **立刻复制** `ghp_` 开头的那串（页面关掉就再也看不到）

**第一次 push 时怎么用**：

```cmd
git push -u origin main
# Username: 你的 GitHub 用户名
# Password: 粘贴刚才的 ghp_ 开头 token（不是账号密码）
```

我已经在本机把凭据保存方式设成了 Git Credential Manager（`credential.helper = manager`，版本 2.9.1），**第一次输入后会自动记住**，之后不用重复输入。

**验证标准**：`git push` 不再报 403 / `Authentication failed`，仓库网页上能看到你的提交。

> 备选（更省事）：配 SSH 公钥（规范 4.3），`ssh -T git@github.com` 返回 `Hi 用户名!` 即通。

---

## 三、华为云 AK/SK

> 说明：**我们这套实现其实不依赖 AK/SK** —— 后端调计费函数走的是 HTTP 触发器地址（`FG_ENDPOINT`），定时函数回调后端也是普通 HTTP。AK/SK 是组内规范要求的「万一要用 SDK / CLI 调用」的凭证，按规范办即可，但**绝不能写进代码或仓库**。

1. 登录 https://www.huaweicloud.com/ （实名认证你说已经做了 ✅）
2. 右上角账号名 → **我的凭证**
3. 左侧 **访问密钥** → **新增访问密钥**
4. 验证身份（短信/密码）→ 生成后**立即下载 `credentials.csv`**
   - 里面是 `Access Key Id`（AK）与 `Secret Access Key`（SK）
   - **这个 csv 只能下载一次**
5. 把 csv 放到**仓库外**的目录（例如 `F:\secrets\`），**不要放进 `code` 目录**
   - 我们的 `.gitignore` 已经忽略了 `*.csv`，但别依赖它，物理上分开最稳
6. 需要调 API 时再设环境变量（不要写进 `.env` 提交）：

```cmd
setx HUAWEICLOUD_SDK_AK "你的AK"
setx HUAWEICLOUD_SDK_SK "你的SK"
```

**验证标准**：`我的凭证 → 访问密钥` 里能看到 1 个「已启用」的密钥；本地 `F:\secrets\credentials.csv` 存在且不在 git 仓库内（`git status` 看不到它）。

---

## 四、FunctionGraph 函数一：计费函数 `billing-func`

**代码已写好**：`code\cloud\functiongraph\billing\billing.py`（另有打包好的 `billing.zip`）。
口径：金额 = 单价 × 分钟 ÷ 60，四舍五入两位小数；`4.00 × 30 ÷ 60 = 2.00`。

1. 控制台搜索 **函数工作流 FunctionGraph** → 进服务（首次进入点「立即使用」/开通，免费额度足够）
2. 右上角选区域，例如 **华北-北京四**（记住这个区域，两个函数放同一区域）
3. **创建函数** → 选 **创建空白函数**
4. 填写：
   - **函数名称**：`billing-func`
   - **函数类型**：事件函数
   - **运行时**：**Python 3.9**
   - **委托 / 内存 / 超时**：默认即可（内存 128MB，超时 30 秒）
5. 代码页：
   - 方式 A：把 `billing.py` 全文复制进在线编辑器
   - 方式 B：上传 `billing.zip`
   - **入口**：`billing.handler`（文件名 `billing` + 函数名 `handler`，中间是点）
6. ⚠️ **2026-11 重要变更：这一步已无法免费完成，不要点「创建实例」。**
   华为云官方公告：**API 网关共享版已于 2025/04/30 在中国站退市**，新用户只能使用 **APIG 专享版**（按实例规格 + 公网带宽计费）。当前控制台创建 APIG 触发器时，「实例 / 分组 / 发布环境」都是必填且下拉为空，旁边的「创建实例」会进入购买流程，**与需求文档第六节「不得为此付费」冲突**。
   - 推荐：**跳过第 6、8 步**，用第 7 步的控制台「测试」演示云端计算；页面上的 `CLOUD` 由 `scripts/mock_fg.py` 本地模拟器提供（组员原设计，需求允许「接口形式自定」）。
   - 若必须让页面显示真实云端结果：改用 AK/SK 直接调用 FunctionGraph 同步执行 API `POST /v2/{project_id}/fgs/functions/{function_urn}/invocations`，绕开 APIG；密钥只放本机环境变量、**不得进仓库**。
   - 关于安全认证：将来若确有免费 HTTP 入口，仍选 **None**。后端 `CloudBillingClient` 只发裸 POST（无签名、无 token），选 App/IAM 会返回 401 并静默回退 `LOCAL`，页面再也显示不出 `CLOUD`。
7. 控制台点 **测试**，用这个事件：

```json
{"unitPrice": 4.00, "minutes": 30}
```

**验证标准**：返回

```json
{"statusCode": 200, "body": "{\"amount\": \"2.00\", \"unitPrice\": \"4.00\", \"minutes\": 30, \"formula\": \"4.00 x 30 / 60\"}"}
```

再测一组 `{"unitPrice": 4.80, "minutes": 30}` 应得 `2.40`。

8. 把 HTTP 调用 URL 填进后端环境变量（演示「云端计算」时用）：

```cmd
setx FG_ENDPOINT "https://你的HTTP触发器地址"
```

> 注意：`setx` 后要**重开终端**才会生效；后端重启后，签退页面上的金额来源会从 `LOCAL` 变成 `CLOUD`。

---

## 五、FunctionGraph 函数二：定时释放 `seat-scan-func`

**代码已写好**：`code\cloud\functiongraph\timeout_release\timeout_release.py`（另有 `timeout_release.zip`）。
它不自己算规则，而是按时调用后端 `/api/timeout/run`，保证「手工触发」与「定时触发」结果完全一致。

### 免费公网通道（2026-11 补充，让定时函数真的能回调本机）

云函数跑在华为云上，访问不到 `127.0.0.1`。用 SSH 反向隧道把本机 8080 暴露成临时 HTTPS 地址，**免费且无需注册**。

**在自己的 PowerShell 窗口里跑**（脚本会自动重连；不要用 AI 工具临时起的后台进程，那些会随会话被回收）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start_tunnel.ps1
```

脚本会自动生成/使用 `.workbuddy\bin\tunnel_key_win`。等价的裸命令（Git Bash，用另一把 `tunnel_key`）：

```bash
ssh -T -n -i "D:/workspace/SE/Lab/.workbuddy/bin/tunnel_key" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes \
  -R 80:127.0.0.1:8080 localhost.run
```

- 输出里的 `https://xxxx.app.lhr.life` 就是 `BACKEND_BASE`；**窗口要一直开着**，域名每次重连都会变，变了要回填云函数环境变量；演示完按 `Ctrl+C` 关闭。
- ⚠️ **PowerShell 与 Git Bash 的密钥不能混用**：Windows 自带 OpenSSH 会拒绝 ACL 过宽的私钥，报 `UNPROTECTED PRIVATE KEY FILE` 并卡在输密码。所以 PowerShell 用 `tunnel_key_win`（由 Windows `ssh-keygen` 生成，权限正确），Git Bash 用 `tunnel_key`。两把密钥本机都已生成好；脚本缺密钥时会自行用 Windows `ssh-keygen` 重建。
- 本机若被 PowerShell 的 `$ErrorActionPreference = 'Stop'` 影响，ssh 的 stderr 欢迎信息会被当成终止性错误导致重连循环退出；脚本已设为 `Continue`，无需额外处理。
- ⚠️ 脚本**故意只用 ASCII 字符**：Windows PowerShell 5.1 会把无 BOM 的 `.ps1` 按 GBK 读，脚本里写中文会导致「字符串缺少终止符」的语法错误、直接跑不起来。若要改脚本，请保持纯英文，或另存为「UTF-8 带 BOM」。已实测脚本可正常连上并输出 `*.app.lhr.life` 域名。
- 已实测：`curl --noproxy '*' https://<域名>/api/health` 返回 200；`POST /api/timeout/run` 返回 `{"code":0,"data":0}`，连调两次结果一致（幂等）。本机若配置了 `HTTPS_PROXY`，curl 必须加 `--noproxy '*'`，否则会误报 502。
- ⚠️ 该地址会把无认证的后端暴露到公网，仅用于课程演示，结束后务必关闭。若华为云侧访问 `*.app.lhr.life` 不通，退回文末的本地模拟器方案，并在实验报告中说明。
- **控制台测试返回 `HTTP Error 502: Bad Gateway` 时**：先确认隧道进程还活着。免费 SSH 隧道会自行断开且域名轮换，旧域名随即失效（本机 `curl` 也会变 502，而本机 `127.0.0.1:8080` 仍为 200）。重连拿到新域名后，把 `BACKEND_BASE` 改成新值再测一次即可。这属于隧道问题，**不是华为云访问不到公网，也不是函数代码错误**。

1. 同一区域 → **创建函数** → 空白函数
2. 填写：
   - **函数名称**：`seat-scan-func`
   - **运行时**：**Python 3.9**
   - **超时**：**30 秒**（默认 3 秒可能不够，因为它要等后端返回）
   - **高级设置**：确认「**函数访问公网**」为开启（它要 POST 公网 `BACKEND_BASE`）；「日志记录」保持默认即可，LTS 每月读写/索引/存储各赠 500MB，课程演示远低于额度
3. 代码：粘贴 `timeout_release.py` 或上传 zip；**入口** `timeout_release.handler`
4. **环境变量**（函数配置 → 环境变量）：

| 键 | 值 |
| --- | --- |
| `BACKEND_BASE` | 填上面隧道给出的 `https://xxxx.app.lhr.life`（**不要带结尾斜杠**）。若隧道不可用，保留默认 `http://127.0.0.1:8080`，此时云端定时执行会报连接错误，但触发器配置本身仍有效，演示改用手工触发 |
| `TRIGGER_TOKEN` | 可留空；若要设，需与后端约定同一个值 |

5. **创建触发器** → **定时触发器**
   - **Cron 表达式**：`0 5 0 * * *`（6 位，第一位是秒；需求只要求「每日一次」，具体时刻不重要）
   - ⚠️ Cron **默认按 UTC 解析**：上式实际是北京时间 08:05。若控制台有时区下拉，选 `Asia/Shanghai`；或在表达式前加 `CRON_TZ=Asia/Shanghai`。配完看「下次执行时间」核对。
   - 触发器名称：`daily-release`
6. 手工测一次：控制台 **测试** → 事件留 `{}` → 执行

**验证标准**：
- 返回 `{"handled": 0, ...}` 或 `{"handled": 1, ...}`（没有超时预约时是 0，正常）
- 数据库 `credit_log` 不会因为重复触发多出记录（`idem_key` 唯一键挡住）
- 触发器列表里能看到「下次执行时间」

> 本地演示没有公网地址时，用 `code\scripts\mock_fg.py` 在本机模拟这两个函数（已实测：计费返回 `2.00`，后端 `source=CLOUD`）。FunctionGraph 上的真实函数主要用来满足需求第六节「云端计算」与录屏演示。

---

## 六、做完后自检

| 检查 | 通过标准 |
| --- | --- |
| GitHub 2FA | Settings 里显示 Enabled，登录需 6 位码 |
| PAT | `git push` 成功，不再要求账号密码 |
| AK/SK | 「我的凭证 → 访问密钥」有 1 个启用项；csv 不在仓库里 |
| 计费函数 | 测试 `4.00 × 30` 返回 `2.00`，`4.80 × 30` 返回 `2.40` |
| 定时函数 | 手工测试返回 `handled`，触发器有下次执行时间 |
| 后端对接 | `FG_ENDPOINT` 配好后，签退金额来源显示 `CLOUD` |

三个值（HTTP URL、AK、SK）**只放本机环境变量**，不要写进 `application.yml`、`.env`、README 或任何会提交的文件。

---

## 七、ECS 购买入口（可选，使用 100 元代金券）

> 需求文档全文**没有任何一条要求付费**。ECS 只是为了让「定时函数稳定回调」和「公网演示」更省事；零账单方案（免费隧道 / 手工触发）同样可交。

### 在哪买

**必须登录中国站控制台**（`console.huaweicloud.com`）。`www.huaweicloud.com/intl/zh-cn` 是**国际站**，与华北-北京四的资源、100 元代金券都不互通。

- 控制台首页（切到华北-北京四）：<https://console.huaweicloud.com/console/?region=cn-north-4&locale=zh-cn#/home>
- ECS 购买页（自定义购买）：<https://console.huaweicloud.com/ecm/?region=cn-north-4&locale=zh-cn#/ecs/create/custom>
- 菜单路径：控制台右上确认区域「**华北-北京四**」 → 左上角「所有服务」 → **计算 → 弹性云服务器 ECS** → 右上「**购买弹性云服务器**」 → 选「**自定义购买**」页签。

### ⚠️ 坑：快速配置页里没有「登录凭证 / 密钥对」

购买页有两个模式。若地址栏是 `#/ecs/create/simple`（页面顶部是「基础配置 / 购买对比 / 高性能型」、一页到底、右侧只有配置概要），那是**快速配置**模式，**整页没有「登录凭证」区块**，因此找不到「密钥对」，也下载不到 `.pem`。

要密钥登录必须进**自定义购买**（`#/ecs/create/custom`）：可以点规格卡片下方那行蓝色「**自定义购买**」链接，或直接打开上面的购买页 URL。自定义购买是分栏表单，「登录凭证」在「**云服务器管理**」区块里（在网络/安全组/公网访问之后、高级配置之前），可选「密码」或「**密钥对**」。

密钥对要先建、私钥只下载一次：ECS 控制台左侧导航「**密钥对**」 → 「创建密钥对」 → 名称填 `KeyPair-xxxx`、类型保持 `SSH_RSA_2048` → 两个复选框这样选：

- ❌ **「我同意将密钥对私钥托管」不要勾**：那会把私钥加密托管到云端（KMS），课程用不到，还会多一步 KMS 密钥选择；我们要的是本地 `.pem`。
- ✅ **「我已阅读并同意《密钥对管理服务免责声明》」必须勾**，否则「确定」不可点。免责声明 2.2 明确「密钥对管理服务当前完全免费」，所以创建本身不花钱。

点「确定」后**浏览器自动下载 `.pem`**（未托管时私钥**仅能下载一次**，丢了只能重建密钥对或改走密码版），存到 `C:\Users\uccen\Downloads\` 之类无中文/空格的路径。回到购买页在「密钥对」下拉里选中它（必要时刷新页面）。

> 顶部蓝条提示「首次创建账号密钥对需具有 Tenant Administrator 系统角色的用户完成」：主账号登录一般没问题；若用 IAM 子账号报权限不足，可切到「**私有密钥对**」页签创建，或退回路线路 B（密码版脚本）。橙色提示「未开通账号密钥对的用户该参数无效」只是说首次会默认建 `SSH_RSA_2048`，属正常。

> 若下拉里没有密钥对，说明还没创建；先去左侧「密钥对」建好再回来刷新下拉。
>
> **不想重填配置**：可以直接用快速配置页下单，创建完到 ECS 列表「更多 → 重置密码」设置 root 密码，然后改用 `deploy/pack_for_ecs_pwd.sh`（密码版部署脚本，会交互提示两次密码），不必再折腾密钥对。

### 下单前先查券

控制台右上账号名 → **费用与成本 / 费用中心** → **优惠与折扣 → 代金券**：核对适用产品（ECS、EIP）、计费模式（**按需**）、适用区域、有效期、是否「仅新购 / 不可与特价套餐同享」。顺便设预算告警（50 元提醒）。

### 购买页逐项（按页面从上到下）

> ⚠️ **先改第一项再填其它**：自定义购买页**默认选中「包年/包月」**，底部还有「购买时长 1 个月」，配置概要显示 ¥224.00 —— 一张订单就超过 100 元券，且包月实例**不能直接删除、只能退订**。切到「**按需计费**」后「购买时长」会消失、价格变成按小时计（约 ¥0.38/h），并出现「设置定时删除时间」。

| 区块 | 项 | 选值 |
| --- | --- | --- |
| 基础配置 | 计费模式 | ✅ **按需计费**（先改这个，页面会重排） |
| 基础配置 | 区域 / 可用区 | 华北-北京四 / 随机分配（保持默认） |
| 实例 | 规格 | 点 **x1.2u.4g（2vCPUs / 4GiB）**；不要默认的 x1.2u.2g / 2GiB（JDK21+MySQL8 容易 OOM） |
| 操作系统 | 镜像 | 点 **Ubuntu** 图标，下拉选 **Ubuntu 22.04**（脚本走 apt 最稳） |
| 主机安全 | 开启主机安全防护 | ❌ **取消勾选**（默认勾选、免费一个月，但页面标注「启用后需要单独计费」；课程用不到） |
| 存储与备份 | 系统盘 | 通用型 SSD **40 GiB**（保持） |
| 存储与备份 | 数据盘 / 开启备份 | 都不加、不勾（云备份收费） |
| 网络 | VPC / 子网 / IP | vpc-default / subnet-default / 自动分配（保持默认） |
| 安全组 | 选择安全组 | **Sys-WebServer**（保持；默认已放通 22/80/443/3389 + ICMP，橙色高危端口警告可忽略） |
| 公网访问 | 弹性公网 IP | **现在购买**，线路 全动态BGP |
| 公网访问 | 计费方式 | 建议 **按流量计费**（¥0.80/GB，演示流量极小），比按带宽 5M 更省 |
| 公网访问 | 带宽 / 随实例释放 | 5 Mbit/s；如有「**随实例释放**」务必勾上，删 ECS 时 EIP 一起释放 |
| 云服务器管理 | 名称 | 随意（如 `ecs-studyroom`） |
| 云服务器管理 | 登录凭证 | **密钥对** → 下拉选刚建的 `KeyPair-xxxx` |
| 云服务器管理 | 确认私钥 | ✅ **必须勾**「确认我已获取密钥对的私钥文件(KeyPair-xxxx.pem)」，否则提交被拦 |
| 高级配置 | 云监控 / 委托 / 注入 | 保持默认（详细监控免费） |
| 购买量 | 定时删除 | 按需模式下勾「**设置定时删除时间**」，设 4~6 小时后自动删除，防忘删超券 |
| 服务声明 | 协议 | 勾选后点「立即购买」 |

改完看右侧「配置概要」核对：按需计费 / 2vCPUs 4GiB / Ubuntu 22.04 / Sys-WebServer / 按流量 5 Mbit/s / 密钥对 KeyPair-xxxx。底部价格应从 **¥224.00** 变成「约 ¥0.xx/小时 + 少量流量费」。

### ⚠️ 安全组要放行 22 和 80

`deploy/pack_for_ecs.sh` 通过 **SSH（TCP 22）** 上传并执行部署，页面走 **HTTP（TCP 80）**。所以入方向必须放行 **22**（建议来源限定为本机公网 IP，临时演示可用 `0.0.0.0/0`）和 **80**（`0.0.0.0/0`）。**8080 / 3306 / 9100 不要对公网开放**（nginx 在 80 上反代 `/api`）。

购买页默认选中的 **Sys-WebServer** 安全组入方向已放通 22 / 80 / 443 / 3389，通常**不用手动改**；若你换成了自定义安全组，请自行补上 22 和 80。

> 勘误：此前口头步骤里写的「只放行 80」是错的，只放行 80 会导致 `scp/ssh` 超时。

### 常见拦截

- 提示需**实名认证**：按引导完成（本人操作）。
- 提示**余额不足**：代金券抵扣的是账单，按需下单仍可能校验现金余额；先看券面说明，或截图发来再判断，不要直接充值大额。
- 提交后约 1–3 分钟创建完成，在 ECS 列表复制「弹性公网 IP」：
  - 密钥登录版：`bash deploy/pack_for_ecs.sh <公网IP> /c/Users/uccen/Downloads/KeyPair-xxxx.pem`
  - 密码登录版（快速配置买机时）：先「更多 → 重置密码」，再 `bash deploy/pack_for_ecs_pwd.sh <公网IP>`

### 实例创建成功后：先关掉「初始化配置」弹窗

ECS 创建完会自动弹出「**初始化配置 → 在线重置密码**」引导页。**用密钥对登录时请直接点右下角「跳过」**，不要在这里设 root 密码：在线重置密码需要短信/操作保护验证码，且运行中的实例要重启才生效；而部署脚本走的是 `.pem` 私钥，与密码无关。点 X 关闭同样可以，不影响实例。

- 私钥 `.pem` 由浏览器下载一次，之后可能被移动。本机实际位置为 `D:\workspace\SE\Lab\KeyPair-d37d.pem`（Git Bash 路径 `/d/workspace/SE/Lab/KeyPair-d37d.pem`）；可用 `ssh-keygen -y -f <pem>` 校验文件有效。
- 华为云**公共镜像（含 Ubuntu 22.04）默认登录用户名是 `root`**（官方文档《通过 macOS 主机登录 Linux ECS》明确写「非 CoreOS 的公共镜像，用户名为 root」），脚本里的 `root@EIP` 无需改。
- 控制台 IP 列常把公网 IP 显示成 `120.46.19...`，**要鼠标悬停或点复制图标取完整四段**；`192.168.x.x` 是私网 IP，不能用于 SSH。
- 部署命令（Git Bash，在 `code/` 目录）：`bash deploy/pack_for_ecs.sh <公网IP> /d/workspace/SE/Lab/KeyPair-d37d.pem`，约 3–8 分钟，窗口别关。若报 `Connection timed out` 先检查安全组 22 端口；`Permission denied (publickey)` 检查密钥对是否绑定的是这一把。
- 部署成功后：`http://<公网IP>/` 出现登录页、`http://<公网IP>/api/health` 返回 `status:UP`；再把 `seat-scan-func` 的 `BACKEND_BASE` 改成 `http://<公网IP>`（不带端口/斜杠）并点「测试」。
- 若购买时勾了「设置定时删除时间」，先到「更多 → 定时任务」确认时间点晚于演示结束时间，需要就往后改，避免机器中途被自动删掉。

### 部署实测记录（2026-11-28，ECS `120.46.192.201`）

执行 `bash deploy/pack_for_ecs.sh 120.46.192.201 /d/workspace/SE/Lab/KeyPair-d37d.pem` 完成部署，Ubuntu 22.04.5 / root 密钥登录 / 2vCPU 4GiB。期间修复了两个真实问题，脚本已同步：

1. **大文件上传被断流**：本机 OpenSSH 10.3 的 `scp` 默认走 SFTP，传 22MB 部署包时报 `Connection closed by <ip> port 22`（小文件正常、SFTP 子系统正常）。改用 `scp -O`（legacy SCP 协议）后 md5 校验一致。两个 `pack_for_ecs*.sh` 都已加 `-O`。
2. **模拟器启动失败导致来源变 LOCAL**：`scripts/mock_fg.py` 会 `import billing` / `import timeout_release`，并按 `ROOT/cloud/functiongraph/{billing,timeout_release}` 找代码。原打包只带了 `mock_fg.py`，ECS 上 `studyroom-mockfg.service` 一直 `ModuleNotFoundError` 重启失败。现打包脚本会一并复制两个 `.py`；补传后 `systemctl restart studyroom-mockfg` 即恢复。

验收（均从公网 `http://120.46.192.201` 实测）：

| 检查 | 结果 |
| --- | --- |
| 首页 / 静态 JS | HTTP 200 / 200 |
| `/api/health` | `status: UP` |
| 登录 `s001/123456` | 返回张三，credit 100、balance 200.00 |
| `/api/cloud/quote` 4.00×30 / 4.80×30 | `2.00` / `2.40`，`source: CLOUD` |
| `/api/timeout/run` 连点两次 | 均为 `data: 0`（幂等） |
| 数据库 | 10 座位、7 账号、单价 4.00 |

> 注意：本节记录的是 **2026-11-28 首次部署时**的状态，当时 `CLOUD` 来自 ECS 上的本地模拟器 `mock_fg.py`（与云端函数同一份 handler 代码），并非 FunctionGraph 真实返回。**2026-11-28 22:20 已按第八章完成 AK/SK 配置**，现在 `/api/cloud/status` 返回 `mode: FUNCTIONGRAPH_AKSK`、`akConfigured: true`，`4.00×30 → 2.00` 与 `4.80×30 → 2.40` 的 `CLOUD` 均由华为云 FunctionGraph 同步执行 API 真实返回（见第八章实测记录）。只有删除访问密钥或清空 `cloud.env` 后才会回落到模拟器通路。

### 按需计费「不用的时候怎么关」：删除，不是关机

官方《按需计费》关机策略：普通实例关机后 **vCPU / 内存 / 镜像停止计费**，但**云硬盘（系统盘、数据盘）与弹性公网 IP 带宽照常计费**。所以关机只能省一部分，账单不会归零。

**正确做法**：ECS 列表 → 实例「更多 → 删除」→ 弹窗里**勾选同步删除关联资源（系统盘 + 弹性公网 IP）**→ 按提示输入 `DELETE` 确认。若 EIP 单独残留，还要去 EIP 列表点「**释放**」（解绑不停费）。

**最省心的做法**：购买页「购买量 → 使用时长」勾「**设置定时删除时间**」，设 4~6 小时后自动删除，到点自动执行上述删除（含关联资源），不用记着手动关。创建后仍可在 ECS 列表「更多 → 定时任务」里修改/取消（官方 API `UpdateServerAutoTerminateTime`，最短须设在当前时间半小时后）。

删完三查：ECS 列表无实例、EIP 列表无空闲 IP、云硬盘列表无 40 GiB 残留；再看费用中心账单不再增长、券余额，截图「0 自费」放进报告。若买过 APIG 专享版，删**实例**而非删 API。

> 删 ECS 后 `seat-scan-func` 的 `BACKEND_BASE` 会失效（测试变 502），但定时触发器配置仍在、不产生费用；演示视频录完后可停用触发器，避免每天产生失败日志。

---

## 八、真·云端计费：AK/SK 直调 FunctionGraph（不买 APIG）

> 需求第三节第 6 条：「按小时计费的金额**由华为云函数工作流计算，页面显示云端结果**」；第六节第 2 条：「**接口形式由小组自行设计，访问密钥不得写入仓库**」。
> 这两句合起来允许用 AK/SK 签名直调 **同步执行函数 API** `POST /v2/{project_id}/fgs/functions/{function_urn}/invocations`，绕开 2025/04 退市后只能付费购买的 APIG 专享版。FunctionGraph 调用仍在每月 100 万次 / 40 万 GB·s 免费额度内，**不新增任何账单**。

### 已完成的改造（2026-11-28 实测）

| 文件 | 改动 |
| --- | --- |
| `backend/pom.xml` | 引入官方 SDK `com.huaweicloud.sdk:huaweicloud-sdk-functiongraph:3.1.225`（签名由官方实现，不手写） |
| `CloudBillingClient.java` | 三条通路按优先级择一：① AK/SK 直调（真云端）② HTTP endpoint（APIG / 本地模拟器）③ 本地算法；递归解包 `amount`，兼容 `body` 字符串、SDK v1 `result` 包装、纯文本金额 |
| `AppProperties.java` / `application.yml` | 新增 `FG_SDK_AK / SK / PROJECT_ID / FUNCTION_URN / FUNCTION_NAME / REGION / ENDPOINT`，全部从环境变量读，默认空 |
| `ReservationController.java` | 新增 `GET /api/cloud/status`，返回当前通路与 URN（**不含任何密钥**） |
| `DashboardView.vue` | 云函数卡片头部加「当前通路」标签：`FUNCTIONGRAPH_AKSK` 显示绿色「华为云 FunctionGraph（AK/SK 直调）」 |
| `deploy/ecs_setup.sh` | systemd 增加 `EnvironmentFile=-/etc/studyroom/cloud.env`（`-` 表示文件缺失也能启动）、`-Xmx768m`、自检加 `/api/cloud/status` |
| `deploy/setup_aksk.sh` | ECS 上交互式填写 AK/SK（`read -s` 不回显）→ 写 600 环境文件 → 重启 → 自检，密钥不进仓库/日志 |
| `deploy/cloud.env.example`、`.env.example` | 仓库里的空模板（**不含密钥**） |

本地验证：用 mock 端点捕获到 SDK 发出的
`POST /v2/{projectId}/fgs/functions/{urn}/invocations`，请求头含
`Authorization: SDK-HMAC-SHA256 Access=..., SignedHeaders=host;user-agent;x-cff-request-version;x-project-id;x-sdk-date, Signature=...`、
`X-Sdk-Date`、`X-CFF-Request-Version: v1`，请求体 `{"unitPrice":"4.00","minutes":30}`；返回解包成 `2.00 / CLOUD`。单元测试 14 项全过。

### 步骤 1｜IAM 创建访问密钥（只需一次）

控制台右上账号名 → **我的凭证** → **访问密钥** → **新增访问密钥** → 完成短信/邮箱验证 → **下载 `credentials.csv`**（私钥只下载一次，丢了只能删除重建）。文件里 `Access Key Id` 是 AK，`Secret Access Key` 是 SK。

⚠️ 这两个值**只写进 ECS 的环境文件**，不要发到聊天、不要写进 `.env`、代码、README 或任何会提交的文件。

### 步骤 2｜取项目 ID 与函数 URN

- **项目 ID**：我的凭证 → **项目列表** → 区域切到 **华北-北京四** → 复制 32 位「项目 ID」。区域必须和两个函数一致。
- **函数 URN**：FunctionGraph → `billing-func` → 函数详情/概览里复制完整 URN，形如
  `urn:fss:cn-north-4:<projectId>:function:default:billing-func:latest`。
- 找不到 URN 也没关系：只填**函数名** `billing-func`，后端会按上述格式自动拼接（已单元测试验证）。

### 步骤 3（推荐）｜一条命令交互填写，密钥不进对话

拿好 AK/SK 与项目 ID 后，在**你自己的 Git Bash** 里执行（脚本已放在 ECS 上）：

```bash
ssh -t -i /d/workspace/SE/Lab/KeyPair-d37d.pem root@120.46.192.201 \
    'bash /opt/studyroom/deploy/setup_aksk.sh'
```

依次提示：函数名（回车用 `billing-func`）→ 项目 ID → **AK（不回显）** → **SK（不回显）** → 完整 URN（可留空）。
脚本会自动写 `/etc/studyroom/cloud.env`（权限 600）、`systemctl restart studyroom`、等待就绪后打印 `/api/cloud/status` 与 `/api/cloud/quote` 的结果。

密钥只经过你的终端，不会进入聊天记录、命令行历史、代码仓库或服务端日志。`-t` 是必须的（要给 `read -s` 分配 TTY）。

下面的「步骤 3 / 步骤 4」是脚本内部所做的等价手动流程，供理解与排错用。

### 步骤 3（手动）｜填 ECS 上的环境文件

```bash
ssh -i /path/to/KeyPair-d37d.pem root@120.46.192.201
sudo vi /etc/studyroom/cloud.env
```

把下面 4 项填好（文件已存在、权限 `600`、属主 root）：

```ini
FG_SDK_AK=你的AK
FG_SDK_SK=你的SK
FG_SDK_PROJECT_ID=华北-北京四的项目ID
FG_SDK_FUNCTION_NAME=billing-func
FG_SDK_REGION=cn-north-4
```

也可以不改函数名，直接写 `FG_SDK_FUNCTION_URN=粘贴完整URN`（优先级更高）。
`FG_SDK_ENDPOINT` 只在本地 mock 联调时覆盖 SDK 端点，**正式部署必须留空**。

### 步骤 4（手动）｜重启并自检

```bash
sudo systemctl daemon-reload && sudo systemctl restart studyroom
curl http://127.0.0.1/api/cloud/status
curl -X POST -H 'Content-Type: application/json' \
     -d '{"unitPrice":4.00,"minutes":30}' http://127.0.0.1/api/cloud/quote
```

期望：

- `/api/cloud/status` → `{"mode":"FUNCTIONGRAPH_AKSK","functionUrn":"urn:fss:...","akConfigured":true,...}`
- `/api/cloud/quote` → `{"amount":2.00,"source":"CLOUD","detail":"华为云 FunctionGraph 同步执行 · urn:... · 与本地核算一致"}`
- 公网打开 `http://120.46.192.201/#/dashboard`，第二张卡片头部出现**绿色标签**「当前通路：华为云 FunctionGraph（AK/SK 直调）」

再用 `4.80 × 30` 复测应得 `2.40`。`detail` 里的「与本地核算一致」是后端加的校验，不一致会明确提示，不会静默通过。

**实测记录（2026-11-28 22:20，ECS `120.46.192.201`）**：IAM 访问密钥 + 华北-北京四项目 ID `01a1f69e439670e18a9d6d8c8b838339` 配好后，重启一次即全部符合上述期望——

- `/api/cloud/status` → `{"mode":"FUNCTIONGRAPH_AKSK","region":"cn-north-4","functionUrn":"urn:fss:cn-north-4:01a1f69e439670e18a9d6d8c8b838339:function:default:billing-func:latest","akConfigured":true}`
- `/api/cloud/quote` `4.00×30` → `2.00 / CLOUD`、`4.80×30` → `2.40 / CLOUD`，`detail` 均为「华为云 FunctionGraph 同步执行 · urn:... · 与本地核算一致」。
- 前端构建产物 `assets/index-Dg4_xN-1.js` 已含 `FUNCTIONGRAPH_AKSK` 分支，看板第二张卡片头部显示绿色「当前通路」标签。

### 排错

| 现象 | 处理 |
| --- | --- |
| `mode` 仍是 `HTTP_ENDPOINT` | 四个必填项（`AK/SK/PROJECT_ID/URN` 或 `FUNCTION_NAME`）缺一，或忘了重启；`sudo systemctl show studyroom -p Environment` 可查实际注入值 |
| `source: LOCAL`，detail `HTTP 401` | AK/SK 填错、复制带空格、或密钥已被删除；去 IAM 重建 |
| `HTTP 403 / FGS.00xx` | 项目 ID 与区域不匹配（必须是华北-北京四），或该 AK/SK 无 FunctionGraph 权限 |
| `HTTP 404` / function not found | URN 拼错；去控制台复制完整 URN 填 `FG_SDK_FUNCTION_URN` |
| detail「与本地核算不一致」 | 云端 `billing.py` 是旧版本，重新上传 `billing.zip` |
| 连接超时 | ECS 安全组出站需放通 443；函数无需「访问公网」（是后端主动出站在调云端） |
| 页面金额变 `LOCAL` | 云端调用失败时**不会**偷偷退回模拟器（避免假 CLOUD），看 `detail` 里的错误码 |

### 安全收尾（删 ECS 前必做）

1. `sudo shred -u /etc/studyroom/cloud.env`（或 `sudo tee /etc/studyroom/cloud.env < /dev/null` 清空）。
2. IAM → 访问密钥 → **删除**本次创建的密钥。
3. 再按第七章删除 ECS 实例（勾选同步释放系统盘 + EIP），查账单与券余额。

> 未填 AK/SK 时的行为：页面仍显示 `CLOUD`，但来自 ECS 上的 `mock_fg.py` 模拟器，`/api/cloud/status` 会如实显示 `HTTP_ENDPOINT`。录演示视频时请以 `/api/cloud/status` 的标签为准，不要把模拟器结果说成华为云真算的。
