-- ============================================================
-- 智能共享自习室管理系统 · 演示数据（项目编号 26）
-- 前置：先执行 init.sql；本脚本会把一天的业务数据插入 reading_room
-- 清空重来：重新执行 init.sql 即可
-- ============================================================
USE reading_room;

-- 演示数据：一次完整的"预约→签到→暂离→签退→超时→投诉→调价"场景（日期均为当天）
-- 执行后可用 DBeaver 直接浏览；要清空重来，重新执行 init.sql 即可。
SET NAMES utf8mb4;

DELETE FROM complaint;
DELETE FROM price_change;
DELETE FROM bill_order;
DELETE FROM credit_log;
DELETE FROM reservation;

-- ① 张三：预约 A01 09:00 → 09:05 签到 → 09:35 签退，30 分钟按云端计算 2.00
INSERT INTO reservation (id, user_id, seat_id, status, created_at, expire_at, checkin_at, leave_at, checkout_at, unit_price)
VALUES (1, 1, 1, 'CHECKED_OUT',
        TIMESTAMP(CURDATE(), '09:00:00'), TIMESTAMP(CURDATE(), '09:15:00'),
        TIMESTAMP(CURDATE(), '09:05:00'), NULL, TIMESTAMP(CURDATE(), '09:35:00'), 4.00);
INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
VALUES ('D20261120-0001', 1, 1, 'USAGE', 30, 4.00, 2.00, 'NONE', 'CLOUD', TIMESTAMP(CURDATE(), '09:35:00'));

-- ② 李四：预约 A02 10:00 未签到 → 10:20 超时释放，信用 -10，违约金 4.00（幂等键 TIMEOUT-2）
INSERT INTO reservation (id, user_id, seat_id, status, created_at, expire_at, checkin_at, leave_at, checkout_at, unit_price)
VALUES (2, 2, 2, 'EXPIRED',
        TIMESTAMP(CURDATE(), '10:00:00'), TIMESTAMP(CURDATE(), '10:15:00'),
        NULL, NULL, NULL, 4.00);
UPDATE app_user SET credit = 90 WHERE id = 2;
INSERT INTO credit_log (user_id, delta, reason, idem_key, created_at)
VALUES (2, -10, '预约后15分钟未签到，系统释放座位', 'TIMEOUT-2', TIMESTAMP(CURDATE(), '10:20:00'));
INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
VALUES ('D20261120-0002', 2, 2, 'OVERTIME', 0, 4.00, 4.00, 'NONE', 'LOCAL', TIMESTAMP(CURDATE(), '10:20:00'));

-- ③ 王五（月卡）：A03 11:00→12:00 共 60 分钟，月卡期间 0 元，且不叠加分钟计费
INSERT INTO reservation (id, user_id, seat_id, status, created_at, expire_at, checkin_at, leave_at, checkout_at, unit_price)
VALUES (3, 3, 3, 'CHECKED_OUT',
        TIMESTAMP(CURDATE(), '11:00:00'), TIMESTAMP(CURDATE(), '11:15:00'),
        TIMESTAMP(CURDATE(), '11:02:00'), NULL, TIMESTAMP(CURDATE(), '12:00:00'), 4.00);
INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
VALUES ('D20261120-0003', 3, 3, 'USAGE', 60, 4.00, 0.00, 'MONTHLY', 'CLOUD', TIMESTAMP(CURDATE(), '12:00:00'));

-- ④ 赵六（包天卡）：A04 12:00 首次入座固定 30 元；14:00 当天第二次入座 0 元不重复扣
INSERT INTO reservation (id, user_id, seat_id, status, created_at, expire_at, checkin_at, leave_at, checkout_at, unit_price)
VALUES (4, 4, 4, 'CHECKED_OUT',
        TIMESTAMP(CURDATE(), '12:00:00'), TIMESTAMP(CURDATE(), '12:15:00'),
        TIMESTAMP(CURDATE(), '12:01:00'), NULL, TIMESTAMP(CURDATE(), '13:00:00'), 4.00);
INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
VALUES ('D20261120-0004', 4, 4, 'DAY_CARD', 60, 30.00, 30.00, 'DAY', 'LOCAL', TIMESTAMP(CURDATE(), '12:01:00'));

INSERT INTO reservation (id, user_id, seat_id, status, created_at, expire_at, checkin_at, leave_at, checkout_at, unit_price)
VALUES (5, 4, 4, 'CHECKED_OUT',
        TIMESTAMP(CURDATE(), '14:00:00'), TIMESTAMP(CURDATE(), '14:15:00'),
        TIMESTAMP(CURDATE(), '14:01:00'), NULL, TIMESTAMP(CURDATE(), '15:00:00'), 4.00);
INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
VALUES ('D20261120-0005', 5, 4, 'USAGE', 60, 4.00, 0.00, 'DAY', 'LOCAL', TIMESTAMP(CURDATE(), '15:00:00'));

-- ⑤ 投诉：张三一条已处理、一条待处理（未填处理结果不得置为已处理）
INSERT INTO complaint (user_id, content, status, handle_result, handler_id, created_at, handled_at) VALUES
 (1, 'A01 座位椅背损坏，已自行换座', 'DONE', '已更换座椅并补偿 10 分钟', 6,
  TIMESTAMP(CURDATE(), '09:40:00'), TIMESTAMP(CURDATE(), '10:10:00')),
 (2, '空调温度过低，希望调高', 'PENDING', NULL, NULL, TIMESTAMP(CURDATE(), '11:30:00'), NULL);

-- ⑥ 变价：09:00 上座 9/10 = 90% > 80%，单价 4.00→4.80；12:30 回落到 4.00（未超 80% 不涨价）
INSERT INTO price_change (room_id, occupied, total_seats, occupancy_rate, old_price, new_price, operator, created_at) VALUES
 (1, 9, 10, 0.9000, 4.00, 4.80, '店长', TIMESTAMP(CURDATE(), '09:00:00')),
 (1, 7, 10, 0.7000, 4.80, 4.00, '店长', TIMESTAMP(CURDATE(), '12:30:00'));

SELECT '演示数据已写入' AS msg;
