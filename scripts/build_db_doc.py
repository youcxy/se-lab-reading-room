# -*- coding: utf-8 -*-
"""从 information_schema 导出的 TSV 生成《数据库设计说明.md》。"""
import io
import os

ROOT = r"F:\workspace\SE\Lab\code"
LAB = r"F:\workspace\SE\Lab"
COLS = os.path.join(ROOT, "scripts", "_cols.tsv")
IDX = os.path.join(ROOT, "scripts", "_idx.tsv")
OUT = os.path.join(LAB, "数据库设计说明.md")

CN = {
    "room": ("自习室", "保存自习室与当前生效单价；1 间 10 座"),
    "seat": ("座位", "座位状态机载体，暂离仍占座由 leave_flag 表达"),
    "app_user": ("用户", "三类角色、信用分、余额、月卡与包天卡"),
    "reservation": ("预约与使用记录", "一次预约的生命周期与单价快照"),
    "bill_order": ("账单", "计费、超时违约金、包天卡三类金额，幂等键在这张表"),
    "credit_log": ("信用流水", "信用变动留痕，超时用 TIMEOUT-预约号 做幂等"),
    "complaint": ("投诉", "处理结果必填才能置为已处理"),
    "price_change": ("变价记录", "每次变价一条，含占用数/总数/上座率/原价/新价"),
    "sim_clock": ("模拟时钟", "演示 15 分钟超时用的时间偏移"),
}
ORDER = ["room", "seat", "app_user", "reservation", "bill_order",
         "credit_log", "complaint", "price_change", "sim_clock"]


def read_tsv(path):
    rows = []
    with io.open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n").rstrip("\r")
            if not line.strip():
                continue
            rows.append(line.split("\t"))
    return rows


def md_cell(s):
    return (s or "").replace("|", "\\|").strip() or "—"


def main():
    cols = read_tsv(COLS)
    idx = read_tsv(IDX)

    by_table = {}
    for r in cols:
        while len(r) < 7:
            r.append("")
        by_table.setdefault(r[0], []).append(r)
    idx_by = {}
    for r in idx:
        while len(r) < 4:
            r.append("")
        idx_by.setdefault(r[0], []).append(r)

    L = []
    w = L.append
    w("# 智能共享自习室管理系统 · 数据库设计说明")
    w("")
    w("> 项目编号 26　课程：软件工程实验　数据库：MySQL 9.5.0（InnoDB / utf8mb4 / utf8mb4_general_ci）")
    w("> 库名 `reading_room`，共 %d 张表；本文与 `sql/init.sql`（建表+初始数据）、`sql/test_data.sql`（演示数据）一致。" % len(ORDER))
    w("")
    w("## 1 表清单")
    w("")
    w("| 表名 | 中文名 | 作用 |")
    w("| --- | --- | --- |")
    for t in ORDER:
        cn, use = CN[t]
        w("| `%s` | %s | %s |" % (t, cn, use))
    w("")
    w("## 2 设计原则")
    w("")
    w("1. **状态显式化**：座位状态只有 `FREE / RESERVED / IN_USE` 三态，暂离不改状态、只用 `seat.leave_flag` 标记，"
      "因此“暂离期间座位仍计占用、他人不可预订”在数据层就是天然成立的，不需要额外规则。")
    w("2. **计费可追溯**：每条账单同时保存 `minutes`、`unit_price`、`amount`、`source`，"
      "`reservation.unit_price` 保存“开始使用那一刻”的单价快照——涨价只影响之后再开始的计次，已开始的 30 分钟仍是 2.00 元。")
    w("3. **幂等交给数据库**：超时处理与签退都用唯一键挡重复，而不是依赖调度器“恰好投递一次”。"
      "`bill_order.uk_order_res_kind (reservation_id, kind)` 保证同一预约的同一类账单只有一条；"
      "`credit_log.uk_credit_idem (idem_key)` 保证同一预约的扣分只有一条（键值形如 `TIMEOUT-12`）。"
      "重复处理时数据库抛 1062，接口转成 409，页面表现为“已处理，不产生第二条记录”。")
    w("4. **金额两位小数**：金额字段统一 `DECIMAL(10,2)`，计算时按分钟向上取整、结果四舍五入到分，避免浮点误差（云端函数与本地实现同一规则）。")
    w("5. **规则不叠加**：卡类型 `card_type`（NONE/MONTHLY/DAY）与账单类型 `kind`（USAGE/OVERTIME/DAY_CARD）组合表达，"
      "月卡 0 元时不会再生出按分钟计费的行。")
    w("6. **变价留痕**：`price_change` 每变一次写一条，带上占用数、总数、上座率、原价、新价与操作人，导出与对账都从这张表来。")
    w("7. **无物理外键**：表间关系靠索引与业务校验维持，便于课程环境下删表重建与造数据；唯一键与索引均已显式建立。")
    w("")
    w("## 3 表间关系")
    w("")
    w("![数据库 ER 图](ER图.png)")
    w("")
    w("| 关系 | 说明 |")
    w("| --- | --- |")
    w("| `seat.room_id → room.id` | 一间自习室 10 个座位 |")
    w("| `seat.current_user_id → app_user.id` | 当前使用人，空表示无人 |")
    w("| `reservation.user_id → app_user.id`、`reservation.seat_id → seat.id` | 一次预约把一个人绑到一个座位 |")
    w("| `bill_order.reservation_id → reservation.id` | 账单由某次使用产生，与 `kind` 组成幂等键 |")
    w("| `credit_log.user_id → app_user.id` | 信用变动留痕 |")
    w("| `complaint.user_id / handler_id → app_user.id` | 投诉人与处理人 |")
    w("| `price_change.room_id → room.id` | 变价记录挂在自习室上 |")
    w("")
    w("## 4 数据字典")
    w("")
    for i, t in enumerate(ORDER, start=1):
        cn, use = CN[t]
        w("### 4.%d %s（`%s`）" % (i, cn, t))
        w("")
        w(use + "。")
        w("")
        w("| 字段 | 类型 | 允许空 | 键 | 默认值 | 说明 |")
        w("| --- | --- | --- | --- | --- | --- |")
        for r in by_table.get(t, []):
            name, typ, nullable, key, default, comment = r[1], r[2], r[3], r[4], r[5], r[6]
            keytxt = {"PRI": "PK", "UNI": "UK", "MUL": ""}.get(key, "")
            w("| `%s` | %s | %s | %s | %s | %s |" % (
                name, typ, "是" if nullable == "YES" else "否",
                keytxt or "—", md_cell(default), md_cell(comment)))
        w("")
        idx_rows = idx_by.get(t, [])
        if idx_rows:
            parts = []
            for r in idx_rows:
                kind = "唯一索引" if r[3] == "UNIQUE" else "普通索引"
                parts.append("`%s(%s)` %s" % (r[1], r[2].replace(",", ", "), kind))
            w("索引：" + "；".join(parts) + "。")
            w("")

    w("## 5 状态机与枚举取值")
    w("")
    w("### 5.1 座位状态（`seat.status` + `seat.leave_flag`）")
    w("")
    w("| 当前 | 操作 | 之后 | 附加变化 |")
    w("| --- | --- | --- | --- |")
    w("| FREE | 预约 | RESERVED | 写 `reservation`，`expire_at` = 预约时间 + 15 分钟 |")
    w("| RESERVED | 签到 | IN_USE | `checkin_at` 落库，`current_user_id` 置为用户 |")
    w("| RESERVED | 超时（未签到） | FREE | 信用 −10、写 `OVERTIME` 账单 4.00、`reservation.status = EXPIRED` |")
    w("| IN_USE | 暂离 | IN_USE | `leave_flag = 1`，座位仍占用，计费继续 |")
    w("| IN_USE | 结束暂离 | IN_USE | `leave_flag = 0` |")
    w("| IN_USE | 签退 | FREE | 写 `USAGE` 账单，`checkout_at` 落库 |")
    w("")
    w("### 5.2 取值枚举")
    w("")
    w("| 字段 | 取值 | 含义 |")
    w("| --- | --- | --- |")
    w("| `app_user.role` | MEMBER / MANAGER / ADMIN | 自习人员 / 店长 / 管理员 |")
    w("| `reservation.status` | RESERVED / IN_USE / TEMP_LEAVE / CHECKED_OUT / EXPIRED / CANCELLED | 已预约 / 使用中 / 暂离 / 已签退 / 超时释放 / 已取消 |")
    w("| `bill_order.kind` | USAGE / OVERTIME / DAY_CARD | 按分钟计费 / 超时违约金 / 包天卡 |")
    w("| `bill_order.card_type` | NONE / MONTHLY / DAY | 无卡 / 月卡 / 包天卡 |")
    w("| `bill_order.source` | CLOUD / LOCAL | 华为云函数工作流计算 / 本地兜底计算 |")
    w("| `complaint.status` | PENDING / DONE | 待处理 / 已处理（必须有处理结果） |")
    w("")
    w("## 6 关键口径 SQL")
    w("")
    w("看板三指标（订单数、客单价、复购人数），日期区间用 `[from, to]`：")
    w("")
    w("```sql")
    w("-- 订单数与营收")
    w("SELECT COUNT(*) AS orders, ROUND(SUM(amount), 2) AS revenue")
    w("  FROM bill_order")
    w(" WHERE created_at >= ? AND created_at < DATE_ADD(?, INTERVAL 1 DAY);")
    w("")
    w("-- 客单价 = 营收 ÷ 订单数")
    w("SELECT ROUND(SUM(amount) / NULLIF(COUNT(*), 0), 2) AS avg_ticket")
    w("  FROM bill_order")
    w(" WHERE created_at >= ? AND created_at < DATE_ADD(?, INTERVAL 1 DAY);")
    w("")
    w("-- 复购人数 = 所选日期内订单不少于 2 笔的人数")
    w("SELECT COUNT(*) AS repeat_users FROM (")
    w("  SELECT user_id FROM bill_order")
    w("   WHERE created_at >= ? AND created_at < DATE_ADD(?, INTERVAL 1 DAY)")
    w("   GROUP BY user_id HAVING COUNT(*) >= 2) t;")
    w("```")
    w("")
    w("上座率与调价判定（占用 9 / 总数 10 = 90% > 80% → 4.00 × 1.2 = 4.80）：")
    w("")
    w("```sql")
    w("SELECT SUM(status <> 'FREE') AS occupied, COUNT(*) AS total,")
    w("       ROUND(SUM(status <> 'FREE') / COUNT(*), 4) AS rate")
    w("  FROM seat WHERE room_id = ?;")
    w("```")
    w("")
    w("当天是否已用包天卡（决定再次入座不再扣 30 元）：")
    w("")
    w("```sql")
    w("SELECT COUNT(*) FROM bill_order")
    w(" WHERE user_id = ? AND kind = 'DAY_CARD'")
    w("   AND DATE(created_at) = CURDATE();")
    w("```")
    w("")
    w("## 7 演示数据与自检结果")
    w("")
    w("`sql/init.sql` 写入 1 间自习室、10 个座位（A01–A10，全空闲）、单价 4.00 元/小时、7 个账号；"
      "`sql/test_data.sql` 写入“一天”的完整场景，用来验证需求第三节的每条规则：")
    w("")
    w("| 场景 | 数据表现 | 期望 |")
    w("| --- | --- | --- |")
    w("| 张三用 30 分钟 | `bill_order` USAGE 30 分钟 2.00，`source = CLOUD` | 4.00 × 30 ÷ 60 = 2.00 |")
    w("| 李四预约未签到 | `reservation.status = EXPIRED`，信用 100→90，OVERTIME 4.00 | 释放 + 扣分 + 违约金 |")
    w("| 王五月卡使用 60 分钟 | USAGE 金额 0.00，`card_type = MONTHLY` | 有效期内 0 元，不叠加按分钟 2.00 |")
    w("| 赵六包天卡 | 首次 DAY_CARD 30.00，当天第二次入座 0.00 | 当天固定 30 元且不重复扣 |")
    w("| 看板（今日） | 订单 5 笔、营收 36.00、客单价 7.20、复购 1 人 | 与订单明细一致 |")
    w("| 变价 | 9/10 座 4.00→4.80；7/10 座 4.80→4.00 | 超 80% 才涨，每次一条记录 |")
    w("")
    w("幂等实测（同一事件重复写入，数据库直接拒绝）：")
    w("")
    w("```text")
    w("ERROR 1062 (23000) at line 1: Duplicate entry '2-OVERTIME' for key 'bill_order.uk_order_res_kind'")
    w("ERROR 1062 (23000) at line 1: Duplicate entry 'TIMEOUT-2' for key 'credit_log.uk_credit_idem'")
    w("```")
    w("")
    w("## 8 如何查看")
    w("")
    w("| 项 | 值 |")
    w("| --- | --- |")
    w("| 主机 / 端口 | 127.0.0.1 / 3306 |")
    w("| 数据库 | `reading_room` |")
    w("| 账号（应用用） | `study` / `Study@123456` |")
    w("| 账号（管理员） | `root` / `Root@123456` |")
    w("| 配置文件 | `F:\\mysql\\my.ini`，数据目录 `F:\\mysql\\data` |")
    w("| Windows 服务 | `MySQL95`（自动启动） |")
    w("")
    w("DBeaver：新建 MySQL 连接 → 主机 127.0.0.1、端口 3306、库 `reading_room`、用户 `study`、口令 `Study@123456` → "
      "驱动属性里把 `allowPublicKeyRetrieval` 设为 `true`（MySQL 8+ 默认 caching_sha2_password 需要）。")
    w("")
    w("命令行重建（清空重来）：")
    w("")
    w("```powershell")
    w("$mysql = 'C:\\Program Files\\MySQL\\MySQL Server 9.5\\bin\\mysql.exe'")
    w("cmd /c \"\"$mysql\" --default-character-set=utf8mb4 -u study -pStudy@123456 reading_room < sql\\init.sql\"")
    w("cmd /c \"\"$mysql\" --default-character-set=utf8mb4 -u study -pStudy@123456 reading_room < sql\\init.sql\"")
    w("cmd /c \"\"$mysql\" --default-character-set=utf8mb4 -u study -pStudy@123456 reading_room < sql\\test_data.sql\"")
    w("```")
    w("")

    text = "\n".join(L)
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("saved", OUT, len(text), "chars")


if __name__ == "__main__":
    main()
