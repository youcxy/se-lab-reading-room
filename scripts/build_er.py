# -*- coding: utf-8 -*-
"""生成数据库 ER 图（docs/ER图.png）。纯 Pillow 绘制，外键以 -> 目标表.字段 标注。"""
from PIL import Image, ImageDraw, ImageFont
import os

FONT = "C:/Windows/Fonts/msyh.ttc"
f_title = ImageFont.truetype(FONT, 22)
f_field = ImageFont.truetype(FONT, 17)
f_type = ImageFont.truetype(FONT, 15)
f_tag = ImageFont.truetype(FONT, 14)
f_legend = ImageFont.truetype(FONT, 18)
f_head = ImageFont.truetype(FONT, 30)

W, H = 1900, 1220
C_TITLE = (37, 99, 235)
C_BORDER = (148, 163, 184)
C_TEXT = (30, 41, 59)
C_TYPE = (100, 116, 139)
C_FK = (13, 148, 136)
C_PK = (220, 38, 38)
C_UK = (147, 51, 234)

img = Image.new("RGB", (W, H), (255, 255, 255))
d = ImageDraw.Draw(img)

# name, type, tag(PK/UK/-), fk(目标表.字段 或 None), 中文注释
T = {}

T["room"] = dict(x=40, y=110, cn="自习室", fields=[
    ("id", "BIGINT", "PK", None, "自习室编号"),
    ("name", "VARCHAR(64)", "", None, "名称"),
    ("seat_count", "INT", "", None, "座位总数"),
    ("base_price", "DECIMAL(10,2)", "", None, "基准单价"),
    ("current_price", "DECIMAL(10,2)", "", None, "当前生效单价"),
    ("updated_at", "DATETIME", "", None, "更新时间"),
])

T["seat"] = dict(x=40, y=500, cn="座位", fields=[
    ("id", "BIGINT", "PK", None, "座位编号"),
    ("room_id", "BIGINT", "", "room.id", "所属自习室"),
    ("code", "VARCHAR(16)", "UK", None, "座位号 A01~A10"),
    ("status", "VARCHAR(16)", "", None, "FREE/RESERVED/IN_USE"),
    ("current_user_id", "BIGINT", "", "app_user.id", "当前使用人"),
    ("leave_flag", "TINYINT", "", None, "1=暂离中"),
    ("version", "INT", "", None, "乐观锁版本"),
])

T["sim_clock"] = dict(x=40, y=830, cn="模拟时钟", fields=[
    ("id", "BIGINT", "PK", None, "固定为 1"),
    ("offset_seconds", "BIGINT", "", None, "时间偏移（秒）"),
])

T["reservation"] = dict(x=660, y=110, cn="预约与使用记录", fields=[
    ("id", "BIGINT", "PK", None, "预约编号"),
    ("user_id", "BIGINT", "", "app_user.id", "预约人"),
    ("seat_id", "BIGINT", "", "seat.id", "座位"),
    ("status", "VARCHAR(16)", "", None, "RESERVED/IN_USE/TEMP_LEAVE/CHECKED_OUT/EXPIRED"),
    ("created_at", "DATETIME", "", None, "预约时间"),
    ("expire_at", "DATETIME", "", None, "签到截止（+15 分钟）"),
    ("checkin_at", "DATETIME", "", None, "签到时间"),
    ("leave_at", "DATETIME", "", None, "暂离时间"),
    ("checkout_at", "DATETIME", "", None, "签退时间"),
    ("unit_price", "DECIMAL(10,2)", "", None, "开始使用时的单价快照"),
])

T["app_user"] = dict(x=660, y=500, cn="用户", fields=[
    ("id", "BIGINT", "PK", None, "用户编号"),
    ("login", "VARCHAR(32)", "UK", None, "登录名"),
    ("password", "VARCHAR(64)", "", None, "口令（演示用明文）"),
    ("display_name", "VARCHAR(32)", "", None, "姓名"),
    ("role", "VARCHAR(16)", "", None, "MEMBER/MANAGER/ADMIN"),
    ("credit", "INT", "", None, "信用分，初始 100"),
    ("balance", "DECIMAL(10,2)", "", None, "余额"),
    ("monthly_expire_date", "DATE", "", None, "月卡有效期"),
    ("day_pass_date", "DATE", "", None, "包天卡日期"),
])

T["complaint"] = dict(x=660, y=830, cn="投诉", fields=[
    ("id", "BIGINT", "PK", None, "投诉编号"),
    ("user_id", "BIGINT", "", "app_user.id", "投诉人"),
    ("content", "VARCHAR(500)", "", None, "投诉内容"),
    ("status", "VARCHAR(16)", "", None, "PENDING/DONE"),
    ("handle_result", "VARCHAR(500)", "", None, "处理结果（非空才能置 DONE）"),
    ("handler_id", "BIGINT", "", "app_user.id", "处理人"),
    ("created_at", "DATETIME", "", None, "提交时间"),
    ("handled_at", "DATETIME", "", None, "处理时间"),
])

T["bill_order"] = dict(x=1290, y=110, cn="账单", fields=[
    ("id", "BIGINT", "PK", None, "账单编号"),
    ("order_no", "VARCHAR(32)", "UK", None, "账单号"),
    ("reservation_id", "BIGINT", "UK", "reservation.id", "关联预约（与 kind 组成幂等键）"),
    ("user_id", "BIGINT", "", "app_user.id", "用户"),
    ("kind", "VARCHAR(16)", "", None, "USAGE/OVERTIME/DAY_CARD"),
    ("minutes", "INT", "", None, "计费分钟数"),
    ("unit_price", "DECIMAL(10,2)", "", None, "计费单价"),
    ("amount", "DECIMAL(10,2)", "", None, "金额"),
    ("card_type", "VARCHAR(16)", "", None, "NONE/MONTHLY/DAY"),
    ("source", "VARCHAR(8)", "", None, "CLOUD 云端 / LOCAL 本地"),
    ("created_at", "DATETIME", "", None, "生成时间"),
])

T["credit_log"] = dict(x=1290, y=500, cn="信用流水", fields=[
    ("id", "BIGINT", "PK", None, "流水编号"),
    ("user_id", "BIGINT", "", "app_user.id", "用户"),
    ("delta", "INT", "", None, "变动值（-10 / +10）"),
    ("reason", "VARCHAR(64)", "", None, "变动原因"),
    ("idem_key", "VARCHAR(128)", "UK", None, "幂等键 TIMEOUT-预约号"),
    ("created_at", "DATETIME", "", None, "发生时间"),
])

T["price_change"] = dict(x=1290, y=830, cn="变价记录", fields=[
    ("id", "BIGINT", "PK", None, "记录编号"),
    ("room_id", "BIGINT", "", "room.id", "自习室"),
    ("occupied", "INT", "", None, "占用座位数"),
    ("total_seats", "INT", "", None, "座位总数"),
    ("occupancy_rate", "DECIMAL(5,4)", "", None, "上座率"),
    ("old_price", "DECIMAL(10,2)", "", None, "原单价"),
    ("new_price", "DECIMAL(10,2)", "", None, "新单价"),
    ("operator", "VARCHAR(32)", "", None, "操作人"),
    ("created_at", "DATETIME", "", None, "变价时间"),
])

BW = 570
ROW = 27
PAD = 15

for name, spec in T.items():
    x, y = spec["x"], spec["y"]
    h = PAD + 34 + len(spec["fields"]) * ROW + PAD
    d.rounded_rectangle([x, y, x + BW, y + h], radius=12, fill=(248, 250, 252), outline=C_BORDER, width=2)
    d.rounded_rectangle([x, y, x + BW, y + 44], radius=12, fill=C_TITLE)
    d.rectangle([x, y + 32, x + BW, y + 44], fill=C_TITLE)
    d.text((x + 16, y + 8), name, font=f_title, fill=(255, 255, 255))
    cn = spec["cn"]
    cw = d.textlength(cn, font=f_tag)
    d.text((x + BW - 16 - cw, y + 14), cn, font=f_tag, fill=(219, 234, 254))
    yy = y + 44 + PAD
    for (col, typ, tag, fk, memo) in spec["fields"]:
        d.text((x + 16, yy), col, font=f_field, fill=C_TEXT)
        if tag:
            tx = x + 16 + d.textlength(col, font=f_field) + 7
            d.text((tx, yy + 4), tag, font=f_tag, fill=C_PK if tag == "PK" else C_UK)
        if fk:
            label = "-> " + fk
            lw = d.textlength(label, font=f_type)
            tw = d.textlength(typ, font=f_type)
            d.text((x + BW - 16 - tw - 12 - lw, yy + 4), label, font=f_type, fill=C_FK)
        else:
            tw = d.textlength(typ, font=f_type)
            d.text((x + BW - 16 - tw, yy + 4), typ, font=f_type, fill=C_TYPE)
        yy += ROW

d.text((40, 40), "智能共享自习室管理系统 · 数据库 ER 图（项目编号 26）", font=f_head, fill=(15, 23, 42))
d.text((40, 1155), "9 张表：room / seat / app_user / reservation / bill_order / credit_log / complaint / price_change / sim_clock"
       "    PK 主键  UK 唯一键  -> 外键指向  计费与超时由 uk_order_res_kind、uk_credit_idem 保证幂等",
       font=f_legend, fill=C_TYPE)

out = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "ER图.png"))
img.save(out)
print("saved", out)