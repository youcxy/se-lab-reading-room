"""
华为云 FunctionGraph 函数二：释放「预约后 15 分钟未签到」的座位（定时触发器，每天一次）。

设计与需求文档第六节一致：
- 座位释放、信用 −10、1 小时单价违约金全部由后端同一段逻辑（ReservationService.releaseOverdueAll）完成，
  云函数只负责「按时触发」，因此手工触发（POST /api/timeout/run）与定时触发结果完全一致。
- 幂等由后端保证（reservation 状态抢占 + credit_log.idem_key 唯一键），重复触发不会产生第二条记录。

环境变量（在 FunctionGraph 函数配置里填）：
    BACKEND_BASE  后端地址，例如 https://studyroom.example.com
    TRIGGER_TOKEN 可选，与后端约定的一次性口令，防止公开地址被随意调用

部署：函数（Python 3.9）→ 入口 timeout_release.handler → 触发器选「定时触发器」
      cron 表达式：0 5 0 * * *（每天 00:05 执行，对应需求“每日一次”）
"""
import json
import os
import urllib.request

BACKEND_BASE = os.environ.get("BACKEND_BASE", "http://127.0.0.1:8080").rstrip("/")
TRIGGER_TOKEN = os.environ.get("TRIGGER_TOKEN", "")


def handler(event, context):
    url = BACKEND_BASE + "/api/timeout/run"
    request = urllib.request.Request(url, data=b"{}", method="POST")
    request.add_header("Content-Type", "application/json")
    if TRIGGER_TOKEN:
        request.add_header("X-Trigger-Token", TRIGGER_TOKEN)
    try:
        with urllib.request.urlopen(request, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            data = json.loads(raw)
        handled = data.get("data") if isinstance(data, dict) else None
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps(
                {
                    "handled": handled,
                    "message": "released %s reservation(s) that missed the 15-minute check-in" % handled,
                    "triggeredAt": str(event.get("time")) if isinstance(event, dict) else None,
                },
                ensure_ascii=False,
            ),
        }
    except Exception as exc:
        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps({"error": str(exc)}, ensure_ascii=False),
        }
