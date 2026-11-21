"""
华为云 FunctionGraph 函数一：按小时计费金额计算（HTTP 触发器）。
事件入参（event 兼容 FunctionGraph 代理格式与直接 JSON）：
    {"unitPrice": 4.00, "minutes": 30}
返回：
    {"statusCode": 200, "body": "{\"amount\": \"2.00\", \"unitPrice\": 4.00, \"minutes\": 30}"}

金额口径与本地 BillingMath.money 完全一致：单价 × 分钟 ÷ 60，四舍五入保留两位小数。
部署：FunctionGraph 控制台新建函数（Python 3.9）→ 上传本文件 → 入口 billing.handler
     → 触发器选「HTTP API」→ 记下访问地址，填进后端 FG_ENDPOINT。
"""
import json
from decimal import Decimal, ROUND_HALF_UP


def _load(event):
    if event is None:
        return {}
    if isinstance(event, (dict, list)):
        payload = event
    else:
        payload = json.loads(event)
    if isinstance(payload, dict) and "body" in payload and payload["body"] is not None:
        body = payload["body"]
        if isinstance(body, str):
            return json.loads(body) if body.strip() else {}
        return body
    return payload


def _money(unit_price, minutes):
    amount = (Decimal(str(unit_price)) * Decimal(int(minutes)) / Decimal(60)).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP
    )
    return amount


def handler(event, context):
    try:
        data = _load(event)
        unit_price = Decimal(str(data.get("unitPrice", data.get("unit_price", 4.00))))
        minutes = int(data.get("minutes", 0))
        if minutes < 0:
            raise ValueError("minutes must be >= 0")
        amount = _money(unit_price, minutes)
        body = {
            "amount": str(amount),
            "unitPrice": str(unit_price),
            "minutes": minutes,
            "formula": "%s x %d / 60" % (unit_price, minutes),
        }
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps(body, ensure_ascii=False),
        }
    except Exception as exc:  # 让调用方能拿到明确的失败原因
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps({"error": str(exc)}, ensure_ascii=False),
        }
