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
6. **创建触发器** → 选 **HTTP API / API 网关触发器**
   - 认证方式选 **None / 无需认证**（课程演示够用）
   - 创建后复制生成的**调用 URL**（形如 `https://xxxx.apig.cn-north-4.huaweicloud.com/...`）
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

1. 同一区域 → **创建函数** → 空白函数
2. 填写：
   - **函数名称**：`seat-scan-func`
   - **运行时**：**Python 3.9**
   - **超时**：**30 秒**（默认 3 秒可能不够，因为它要等后端返回）
3. 代码：粘贴 `timeout_release.py` 或上传 zip；**入口** `timeout_release.handler`
4. **环境变量**（函数配置 → 环境变量）：

| 键 | 值 |
| --- | --- |
| `BACKEND_BASE` | 后端可被公网访问的地址，例如 `https://你的域名`；本地演示填 `http://你的公网IP:8080`（后端在内网时云端访问不到，只能用本地模拟器） |
| `TRIGGER_TOKEN` | 可留空；若要设，需与后端约定同一个值 |

5. **创建触发器** → **定时触发器**
   - **Cron 表达式**：`0 5 0 * * *`（每天 00:05:00，对应需求「每日一次」）
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
