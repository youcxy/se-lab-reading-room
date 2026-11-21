# 智能共享自习室管理系统（项目编号 26）

软件工程实验 · 课程项目。当前阶段：**数据库设计与初始化脚本已完成**，后端 / 前端代码骨架已就位但按分工尚未开始开发。

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
   │  ├─ reset_db.ps1              一键重置数据库（加 -Demo 连演示数据一起写）
   │  ├─ make_meta.ps1             从 information_schema 导出字段与索引元数据
   │  ├─ build_db_doc.py           由元数据生成《数据库设计说明.md》
   │  └─ build_er.py               生成 ER 图
   ├─ backend                      Spring Boot 3.3.5 + JDK 21（IDEA 打开，暂未开发）
   ├─ frontend\reading-room-front   Vue 3 + Vite 5（VS Code 打开，暂未开发）
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

## 六、当前状态

- 数据库：9 张表、69 个字段全部带注释，唯一键保证幂等（`bill_order.uk_order_res_kind`、`credit_log.uk_credit_idem`），演示数据自检通过（5 笔订单、营收 36.00、客单价 7.20、复购 1）。
- 后端 / 前端：代码骨架在 `backend`、`frontend\reading-room-front`，**尚未按分工继续开发**，暂不纳入本次交付。
