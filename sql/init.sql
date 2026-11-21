-- ============================================================
-- 智能共享自习室管理系统 · 建库建表 + 初始数据（项目编号 26）
-- 库名 reading_room / 字符集 utf8mb4 / 排序规则 utf8mb4_general_ci
-- DBeaver：打开本文件 → Ctrl+A → 右键 Execute SQL Script
-- 命令行：mysql -u root -p < init.sql
-- ============================================================
SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS reading_room
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE reading_room;

-- 智能共享自习室管理系统 建表脚本（项目编号 26）
-- 执行：mysql --default-character-set=utf8mb4 -u study -p reading_room < init.sql
-- 说明：幂等与不重复扣费由唯一键保证，见 bill_order.uk_order_res_kind 与 credit_log.uk_credit_idem
SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS complaint;
DROP TABLE IF EXISTS price_change;
DROP TABLE IF EXISTS bill_order;
DROP TABLE IF EXISTS credit_log;
DROP TABLE IF EXISTS reservation;
DROP TABLE IF EXISTS seat;
DROP TABLE IF EXISTS app_user;
DROP TABLE IF EXISTS room;
DROP TABLE IF EXISTS sim_clock;

CREATE TABLE room (
  id            BIGINT        NOT NULL AUTO_INCREMENT COMMENT '自习室编号',
  name          VARCHAR(64)   NOT NULL COMMENT '自习室名称',
  seat_count    INT           NOT NULL DEFAULT 10 COMMENT '座位总数',
  base_price    DECIMAL(10,2) NOT NULL DEFAULT 4.00 COMMENT '基准单价（元/小时）',
  current_price DECIMAL(10,2) NOT NULL DEFAULT 4.00 COMMENT '当前生效单价（元/小时）',
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='自习室';

CREATE TABLE seat (
  id              BIGINT      NOT NULL AUTO_INCREMENT COMMENT '座位编号',
  room_id         BIGINT      NOT NULL COMMENT '所属自习室',
  code            VARCHAR(16) NOT NULL COMMENT '座位号 A01~A10',
  status          VARCHAR(16) NOT NULL DEFAULT 'FREE' COMMENT '状态 FREE空闲/RESERVED已预约/IN_USE使用中',
  current_user_id BIGINT      NULL COMMENT '当前使用人',
  leave_flag      TINYINT     NOT NULL DEFAULT 0 COMMENT '1=暂离中（仍占座）',
  version         INT         NOT NULL DEFAULT 0 COMMENT '乐观锁版本',
  PRIMARY KEY (id),
  UNIQUE KEY uk_seat_room_code (room_id, code),
  KEY idx_seat_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='座位';

CREATE TABLE app_user (
  id                  BIGINT        NOT NULL AUTO_INCREMENT COMMENT '用户编号',
  login               VARCHAR(32)   NOT NULL COMMENT '登录名',
  password            VARCHAR(64)   NOT NULL DEFAULT '123456' COMMENT '口令（课程演示用明文，生产须改哈希）',
  display_name        VARCHAR(32)   NOT NULL COMMENT '姓名',
  role                VARCHAR(16)   NOT NULL DEFAULT 'MEMBER' COMMENT '角色 MEMBER/MANAGER/ADMIN',
  credit              INT           NOT NULL DEFAULT 100 COMMENT '信用分，初始 100，低于 60 不得预约',
  balance             DECIMAL(10,2) NOT NULL DEFAULT 200.00 COMMENT '余额',
  monthly_expire_date DATE          NULL COMMENT '月卡有效期截止日，有效期内计费为 0',
  day_pass_date       DATE          NULL COMMENT '包天卡所属日期，当天固定 30 元且再次入座不重复扣费',
  created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_user_login (login)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户';

CREATE TABLE reservation (
  id            BIGINT        NOT NULL AUTO_INCREMENT COMMENT '预约编号',
  user_id       BIGINT        NOT NULL COMMENT '预约人',
  seat_id       BIGINT        NOT NULL COMMENT '座位',
  status        VARCHAR(16)   NOT NULL COMMENT 'RESERVED已预约/IN_USE使用中/TEMP_LEAVE暂离/CHECKED_OUT已签退/EXPIRED超时释放/CANCELLED已取消',
  created_at    DATETIME      NOT NULL COMMENT '预约时间',
  expire_at     DATETIME      NOT NULL COMMENT '签到截止时间（预约后 15 分钟）',
  checkin_at    DATETIME      NULL COMMENT '签到时间',
  leave_at      DATETIME      NULL COMMENT '暂离时间',
  checkout_at   DATETIME      NULL COMMENT '签退时间',
  unit_price    DECIMAL(10,2) NOT NULL COMMENT '开始使用时的单价快照，涨价只影响之后开始的',
  PRIMARY KEY (id),
  KEY idx_res_user (user_id),
  KEY idx_res_seat (seat_id),
  KEY idx_res_status (status),
  KEY idx_res_expire (status, expire_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='预约与使用记录';

CREATE TABLE bill_order (
  id             BIGINT        NOT NULL AUTO_INCREMENT COMMENT '账单编号',
  order_no       VARCHAR(32)   NOT NULL COMMENT '账单号',
  reservation_id BIGINT        NULL COMMENT '关联预约；与 kind 组成幂等键，同一次超时/签退只允许一条',
  user_id        BIGINT        NOT NULL COMMENT '用户',
  kind           VARCHAR(16)   NOT NULL COMMENT '类型 USAGE按分钟计费/OVERTIME超时违约金/DAY_CARD包天卡',
  minutes        INT           NOT NULL DEFAULT 0 COMMENT '计费分钟数',
  unit_price     DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '计费单价',
  amount         DECIMAL(10,2) NOT NULL DEFAULT 0.00 COMMENT '金额（元，保留两位小数）',
  card_type      VARCHAR(16)   NOT NULL DEFAULT 'NONE' COMMENT '卡类型 NONE/MONTHLY/DAY',
  source         VARCHAR(8)    NOT NULL DEFAULT 'LOCAL' COMMENT '金额来源 CLOUD=云端函数计算 LOCAL=本地兜底',
  created_at     DATETIME      NOT NULL COMMENT '生成时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_order_no (order_no),
  UNIQUE KEY uk_order_res_kind (reservation_id, kind),
  KEY idx_order_user_time (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='账单';

CREATE TABLE credit_log (
  id         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '流水编号',
  user_id    BIGINT       NOT NULL COMMENT '用户',
  delta      INT          NOT NULL COMMENT '变动值，如 -10',
  reason     VARCHAR(64)  NOT NULL COMMENT '变动原因',
  idem_key   VARCHAR(128) NOT NULL COMMENT '幂等键，超时为 TIMEOUT-预约号',
  created_at DATETIME     NOT NULL COMMENT '发生时间',
  PRIMARY KEY (id),
  UNIQUE KEY uk_credit_idem (idem_key),
  KEY idx_credit_user (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='信用流水';

CREATE TABLE complaint (
  id            BIGINT       NOT NULL AUTO_INCREMENT COMMENT '投诉编号',
  user_id       BIGINT       NOT NULL COMMENT '投诉人',
  content       VARCHAR(500) NOT NULL COMMENT '投诉内容',
  status        VARCHAR(16)  NOT NULL DEFAULT 'PENDING' COMMENT '状态 PENDING待处理/DONE已处理',
  handle_result VARCHAR(500) NULL COMMENT '处理结果；未填写不得置为 DONE',
  handler_id    BIGINT       NULL COMMENT '处理人',
  created_at    DATETIME     NOT NULL COMMENT '提交时间',
  handled_at    DATETIME     NULL COMMENT '处理时间',
  PRIMARY KEY (id),
  KEY idx_complaint_status (status, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='投诉';

CREATE TABLE price_change (
  id             BIGINT        NOT NULL AUTO_INCREMENT COMMENT '记录编号',
  room_id        BIGINT        NOT NULL COMMENT '自习室',
  occupied       INT           NOT NULL COMMENT '占用座位数',
  total_seats    INT           NOT NULL COMMENT '座位总数',
  occupancy_rate DECIMAL(5,4)  NOT NULL COMMENT '上座率＝占用÷总数',
  old_price      DECIMAL(10,2) NOT NULL COMMENT '原单价',
  new_price      DECIMAL(10,2) NOT NULL COMMENT '新单价',
  operator       VARCHAR(32)   NOT NULL COMMENT '操作人',
  created_at     DATETIME      NOT NULL COMMENT '变价时间',
  PRIMARY KEY (id),
  KEY idx_price_change_time (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='变价记录，每次变价一条，可按日导出';

CREATE TABLE sim_clock (
  id             BIGINT NOT NULL PRIMARY KEY COMMENT '固定为 1',
  offset_seconds BIGINT NOT NULL DEFAULT 0 COMMENT '相对真实时间的偏移秒数，用于演示 15 分钟超时'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='模拟时钟';

SET FOREIGN_KEY_CHECKS = 1;

-- 初始化数据：1 间自习室、10 个座位、单价 4.00、若干用户（含月卡与当日包天卡）
SET NAMES utf8mb4;

DELETE FROM sim_clock;
INSERT INTO sim_clock (id, offset_seconds) VALUES (1, 0);

DELETE FROM room;
INSERT INTO room (id, name, seat_count, base_price, current_price)
VALUES (1, '共享自习室 A', 10, 4.00, 4.00);

DELETE FROM seat;
INSERT INTO seat (room_id, code, status, current_user_id, leave_flag) VALUES
 (1,'A01','FREE',NULL,0),(1,'A02','FREE',NULL,0),(1,'A03','FREE',NULL,0),
 (1,'A04','FREE',NULL,0),(1,'A05','FREE',NULL,0),(1,'A06','FREE',NULL,0),
 (1,'A07','FREE',NULL,0),(1,'A08','FREE',NULL,0),(1,'A09','FREE',NULL,0),
 (1,'A10','FREE',NULL,0);

DELETE FROM app_user;
INSERT INTO app_user (login, password, display_name, role, credit, balance, monthly_expire_date, day_pass_date) VALUES
 ('s001','123456','张三','MEMBER',100,200.00,NULL,NULL),
 ('s002','123456','李四','MEMBER',100,200.00,NULL,NULL),
 ('s003','123456','王五','MEMBER',100,200.00,DATE_ADD(CURDATE(), INTERVAL 30 DAY),NULL),
 ('s004','123456','赵六','MEMBER',100,200.00,NULL,CURDATE()),
 ('s005','123456','钱七','MEMBER', 55,200.00,NULL,NULL),
 ('m001','123456','店长','MANAGER',100,0.00,NULL,NULL),
 ('a001','123456','管理员','ADMIN',100,0.00,NULL,NULL);

DELETE FROM reservation;
DELETE FROM bill_order;
DELETE FROM credit_log;
DELETE FROM complaint;
DELETE FROM price_change;

SELECT '初始化完成' AS msg,
       (SELECT COUNT(*) FROM seat) AS seats,
       (SELECT COUNT(*) FROM app_user) AS users,
       (SELECT current_price FROM room WHERE id=1) AS price;
