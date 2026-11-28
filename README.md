# 智能共享自习室管理系统（项目编号 26）

软件工程实验 · 课程项目。当前阶段：**系统已实现并跑通端到端验证**（后端 22 个 Java 文件、前端 6 个页面、两个云函数；`scripts\e2e.ps1` 64 项断言全过）。

## 一、目录结构

```
F:\workspace\SE\Lab                 ← 设计与交付文档（提交作业时与本目录一起打包）
├─ 需求文档.docx                    课程下发的实验需求（项目编号 26）
├─ 开发计划.docx / 开发计划.pdf      《项目开发计划》填写版
├─ 小组实验流程与分工手册.docx        四人分工、实验流程、自检清单
├─ 数据库设计说明.md                 表清单 / 设计原则 / 数据字典 / 口径 SQL
├─ ER图.png                        9 张表一览
└─ code                            ← 只放可运行代码与 SQL
   ├─ sql
   │  ├─ init.sql                  建库建表 + 初始数据（1 间自习室、10 座、7 账号、单价 4.00）
   │  └─ test_data.sql             演示数据（一天的预约/超时/月卡/包天卡/投诉/变价）
   ├─ scripts
   │  ├─ start_all.ps1             一键启动（云函数模拟 + 后端 + 前端）
   │  ├─ stop_all.ps1              一键停止三个进程
   │  ├─ e2e.ps1                   端到端回归（64 项断言，需先 reset_db）
   │  ├─ reset_db.ps1              一键重置数据库（加 -Demo 连演示数据一起写）
   │  ├─ make_meta.ps1             从 information_schema 导出字段与索引元数据
   │  ├─ build_db_doc.py           由元数据生成《数据库设计说明.md》
   │  └─ build_er.py               生成 ER 图
   ├─ backend                      Spring Boot 3.3.5 + JDK 21（22 个 Java 文件，6 个 Controller）
   ├─ frontend\reading-room-front   Vue 3 + Vite 5（6 个页面：登录/座位/我的/投诉/看板/调价）
   ├─ cloud                        FunctionGraph 云函数（Python 3.9 事件函数）
   ├─ docs                         测试用例与结果、演示脚本、系统实现说明
   ├─ test / video                 测试截图、演示视频（本地，不入库）
   ├─ .env.example                 环境变量样例（复制为 .env，.env 不入库）
   └─ .gitignore
```

## 二、本机环境

| 组件 | 本机版本 | 组内规范 | 说明 |
| --- | --- | --- | --- |
| JDK | 21.0.12.1（`JAVA_HOME` 已配） | 17 及以上 | ✅ 合规 |
| Node / npm | 24.22.3 / 11.19.1（fnm 管理） | 18.x / 20.x LTS | ✅ 高于要求 |
| Git | 2.56.1.windows.1 | 2.50.1 | ✅ 高于要求 |
| VS Code | 1.146.0 + Vue (Official) + 中文包 | 最新版 + 上述两插件 | ✅ 合规（未装 Vetur） |
| IntelliJ IDEA | 2026.2.3（`E:\idea-2026.2.3.win`） | 社区版最新 | ✅ 合规 |
| MySQL | 9.5.0（服务 `MySQL95`，配置 `F:\mysql\my.ini`） | phpStudy 内置 8.0.12 | ⚠ 用现有 9.5，不另装 phpStudy（会与 3306 冲突） |
| DBeaver | 25.3.1（`F:\DBeaver`） | 26.2.5 | ⚠ 版本略低，功能不受影响 |
| npm 镜像 | `https://registry.npmmirror.com` | 同 | ✅ 已配 |
| Git 换行/中文 | `core.autocrlf=true`、`core.quotepath=false` | 同 | ✅ 已配 |

## 三、数据库

| 项 | 值 |
| --- | --- |
| 库名 | `reading_room`（utf8mb4 / utf8mb4_general_ci） |
| 主机 / 端口 | `localhost` / `3306` |
| 管理账号 | `root` / `Root@123456` |
| 应用账号 | `study` / `Study@123456`（已授权 `reading_room.*`，`localhost` 与 `%`） |
| 表数量 | 9 张（room / seat / app_user / reservation / bill_order / credit_log / complaint / price_change / sim_clock） |

DBeaver 连接要点：驱动属性里把 **`allowPublicKeyRetrieval` 设为 `true`**（MySQL 8/9 默认 `caching_sha2_password`，不设会报 `Public Key Retrieval is not allowed`）。

重建数据库（推荐用脚本）：

```powershell
# 只写初始数据
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\reset_db.ps1
# 连演示数据一起写
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\reset_db.ps1 -Demo
```

或直接用命令行：

```powershell
mysql -u root -pRoot@123456 --default-character-set=utf8mb4 < sql\init.sql
mysql -u root -pRoot@123456 --default-character-set=utf8mb4 < sql\test_data.sql
```

改完表结构后同步文档与图：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make_meta.ps1
python scripts\build_db_doc.py
python scripts\build_er.py
```

## 四、演示账号

网页登录用（口令统一 `123456`，与数据库连接账号是两回事）：

| 账号 | 姓名 | 角色 | 说明 |
| --- | --- | --- | --- |
| s001 | 张三 | 自习人员 | 信用 100，余额 200 |
| s002 | 李四 | 自习人员 | 用于演示 15 分钟超时 |
| s003 | 王五 | 自习人员 | 月卡有效期至 2026-12-20 |
| s004 | 赵六 | 自习人员 | 当日包天卡 |
| s005 | 钱七 | 自习人员 | 信用 55，不能预约 |
| m001 | 店长 | 店长 | 调价、处理投诉、看板 |
| a001 | 管理员 | 管理员 | 维护座位 |

## 五、提交清单

- [x] 源代码（`code` 目录）
- [x] `sql\init.sql`、`sql\test_data.sql`
- [x] `README.md`（环境、依赖、初始化数据、启动命令）
- [x] 设计与文档（需求、开发计划、分工手册、数据库设计说明、ER 图）
- [ ] 功能演示视频（`video`，分工确定后录制）
- [ ] 三条 AI 使用记录（见《项目开发计划》附录）

## 六、快速开始

```powershell
# 1) 初始化数据库（首次或需要干净数据时）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\reset_db.ps1 -Demo

# 2) 一键启动（云函数模拟 9100 + 后端 8080 + 前端 5173）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start_all.ps1

# 3) 浏览器打开
#    http://127.0.0.1:5173/      演示账号 s001 / s003 / s004 / s005 / m001 / a001，口令 123456

# 4) 停止
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stop_all.ps1
```

`start_all.ps1` 会：检查 MySQL95 → 起 `scripts\mock_fg.py`（本地模拟 FunctionGraph，端口 9100）→ 若 `target\*.jar` 不存在则用 mvn 打包并以 `FG_ENDPOINT` 指向模拟函数 → 起 Vite（5173，`/api` 代理到 8080）。日志分别在 `backend\serve.log`、`scripts\mock_fg.out.log`、`frontend\reading-room-front\dev.out.log`。

## 七、当前状态

- 数据库：9 张表、69 个字段全部带注释；唯一键保证幂等（`bill_order.uk_order_res_kind`、`credit_log.uk_credit_idem`）；`-Demo` 演示数据为 5 笔订单、营收 36.00、客单价 7.20、复购 1。
- 后端：`com.studyroom` 下 22 个类（6 个 Controller、8 个 Service、BillingMath 核心算法、ClockService 模拟时钟、CloudBillingClient 云端计费与降级）。
- 前端：Vue 3 + Element Plus，6 个页面，顶栏带模拟时钟（+15/+30/重置）。
- 云函数：`cloud\functiongraph\billing`（计费）与 `cloud\functiongraph\timeout_release`（每日超时释放），本地用 `scripts\mock_fg.py` 模拟同一份 handler。
- 验证：`scripts\e2e.ps1` 在干净库上 **64 项断言全过**（记录 `scripts\_e2e.log`），`mvn test` 6 个单元测试通过。
