package com.studyroom.service;

import com.studyroom.common.BizException;
import com.studyroom.config.AppProperties;
import com.studyroom.core.BillingMath;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/** 预约 → 签到 → 暂离 → 签退，以及超时释放（含幂等）。 */
@Service
public class ReservationService {

    private static final Logger log = LoggerFactory.getLogger(ReservationService.class);
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("yyyyMMdd");

    public record Reservation(long id, long userId, String userName, long seatId, String seatCode, String status,
                              LocalDateTime createdAt, LocalDateTime expireAt, LocalDateTime checkinAt,
                              LocalDateTime leaveAt, LocalDateTime checkoutAt, BigDecimal unitPrice) {
    }

    public record BillView(long id, String orderNo, long userId, String kind, int minutes, BigDecimal unitPrice,
                           BigDecimal amount, String cardType, String source, LocalDateTime createdAt) {
    }

    /** 本人费用明细（签退账单），按时间倒序。 */
    public List<BillView> listBills(Long userId) {
        if (userId == null) {
            return jdbc.query("SELECT * FROM bill_order ORDER BY id DESC LIMIT 100", (rs, i) -> mapBill(rs));
        }
        return jdbc.query("SELECT * FROM bill_order WHERE user_id = ? ORDER BY id DESC LIMIT 100",
                (rs, i) -> mapBill(rs), userId);
    }

    private static final RowMapper<Reservation> MAPPER = (rs, i) -> new Reservation(
            rs.getLong("id"),
            rs.getLong("user_id"),
            rs.getString("user_name"),
            rs.getLong("seat_id"),
            rs.getString("seat_code"),
            rs.getString("status"),
            rs.getTimestamp("created_at").toLocalDateTime(),
            rs.getTimestamp("expire_at").toLocalDateTime(),
            rs.getTimestamp("checkin_at") == null ? null : rs.getTimestamp("checkin_at").toLocalDateTime(),
            rs.getTimestamp("leave_at") == null ? null : rs.getTimestamp("leave_at").toLocalDateTime(),
            rs.getTimestamp("checkout_at") == null ? null : rs.getTimestamp("checkout_at").toLocalDateTime(),
            rs.getBigDecimal("unit_price"));

    private static final String SELECT = """
            SELECT r.*, u.display_name AS user_name, s.code AS seat_code
              FROM reservation r
              JOIN app_user u ON u.id = r.user_id
              JOIN seat s ON s.id = r.seat_id
            """;

    private final JdbcTemplate jdbc;
    private final ClockService clock;
    private final SeatService seats;
    private final UserService users;
    private final CloudBillingClient cloud;
    private final AppProperties props;

    public ReservationService(JdbcTemplate jdbc, ClockService clock, SeatService seats,
                              UserService users, CloudBillingClient cloud, AppProperties props) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.seats = seats;
        this.users = users;
        this.cloud = cloud;
        this.props = props;
    }

    public Reservation require(long id) {
        List<Reservation> list = jdbc.query(SELECT + " WHERE r.id = ?", MAPPER, id);
        if (list.isEmpty()) {
            throw new BizException("预约不存在：" + id);
        }
        return list.get(0);
    }

    public List<Reservation> listByUser(long userId) {
        return jdbc.query(SELECT + " WHERE r.user_id = ? ORDER BY r.id DESC", MAPPER, userId);
    }

    public List<Reservation> listRecent(int limit) {
        return jdbc.query(SELECT + " ORDER BY r.id DESC LIMIT ?", MAPPER, limit);
    }

    /** 预约：信用不足 60 拒绝；座位必须空闲；15 分钟未签到按超时处理。 */
    @Transactional
    public Reservation reserve(long userId, long seatId) {
        UserService.User user = users.require(userId);
        if (user.credit() < props.billing().minCredit()) {
            throw new BizException("信用分 " + user.credit() + " 低于 " + props.billing().minCredit() + "，不能预约");
        }
        seats.markReserved(seatId, userId);
        LocalDateTime now = clock.now();
        BigDecimal unitPrice = seats.room().currentPrice();
        jdbc.update("""
                INSERT INTO reservation (user_id, seat_id, status, created_at, expire_at, unit_price)
                VALUES (?, ?, 'RESERVED', ?, ?, ?)
                """, userId, seatId, now, now.plusMinutes(props.billing().overtimeMinutes()), unitPrice);
        Long id = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        return require(id);
    }

    /** 签到：超过 15 分钟直接判超时（先释放再报错，避免占座）。 */
    @Transactional
    public Reservation checkin(long reservationId, long userId) {
        Reservation res = require(reservationId);
        if (res.userId() != userId) {
            throw new BizException("只能操作自己的预约");
        }
        if (!"RESERVED".equals(res.status())) {
            throw new BizException("当前状态（" + res.status() + "）不能签到");
        }
        LocalDateTime now = clock.now();
        if (now.isAfter(res.expireAt())) {
            releaseOverdue(res, now);
            throw new BizException("已超过 15 分钟签到时限，座位已释放，本单按超时处理");
        }
        jdbc.update("UPDATE reservation SET status = 'IN_USE', checkin_at = ? WHERE id = ? AND status = 'RESERVED'", now, res.id());
        seats.markInUse(res.seatId(), userId);
        return require(reservationId);
    }

    @Transactional
    public Reservation tempLeave(long reservationId, long userId) {
        Reservation res = require(reservationId);
        requireOwner(res, userId);
        if (!"IN_USE".equals(res.status())) {
            throw new BizException("只有使用中的座位可以暂离");
        }
        LocalDateTime now = clock.now();
        jdbc.update("UPDATE reservation SET status = 'TEMP_LEAVE', leave_at = ? WHERE id = ?", now, res.id());
        seats.setLeaveFlag(res.seatId(), true);
        return require(reservationId);
    }

    @Transactional
    public Reservation endLeave(long reservationId, long userId) {
        Reservation res = require(reservationId);
        requireOwner(res, userId);
        if (!"TEMP_LEAVE".equals(res.status())) {
            throw new BizException("当前不在暂离状态");
        }
        jdbc.update("UPDATE reservation SET status = 'IN_USE' WHERE id = ?", res.id());
        seats.setLeaveFlag(res.seatId(), false);
        return require(reservationId);
    }

    /**
     * 签退计费。三条互斥分支（不叠加）：月卡有效期内 0 元；当天包天卡当天固定 30 元且再次入座不重复扣；否则按分钟计费。
     * 金额来源优先取云函数，云函数不可用时本地同算法兜底。
     */
    @Transactional
    public BillView checkout(long reservationId, long userId) {
        Reservation res = require(reservationId);
        requireOwner(res, userId);
        if ("CHECKED_OUT".equals(res.status())) {
            List<BillView> bills = jdbc.query("SELECT * FROM bill_order WHERE reservation_id = ? ORDER BY id",
                    (rs, i) -> mapBill(rs), res.id());
            if (!bills.isEmpty()) {
                return bills.get(0);
            }
            throw new BizException("该预约已签退，不会重复计费");
        }
        if (!"IN_USE".equals(res.status()) && !"TEMP_LEAVE".equals(res.status())) {
            throw new BizException("当前状态（" + res.status() + "）不能签退");
        }
        LocalDateTime now = clock.now();
        int minutes = BillingMath.chargeableMinutes(res.checkinAt(), now);
        UserService.User user = users.require(userId);
        LocalDate today = now.toLocalDate();

        String cardType = "NONE";
        String kind = "USAGE";
        BigDecimal unitPrice = res.unitPrice();
        BigDecimal amount;
        String source = "LOCAL";
        String detail;
        if (users.isMonthlyValid(user, today)) {
            cardType = "MONTHLY";
            amount = BillingMath.money(BigDecimal.ZERO, minutes);
            detail = "月卡有效期内，计费 0 元";
        } else if (users.hasDayPass(user, today)) {
            cardType = "DAY";
            if (!hasDayCardCharge(userId, today)) {
                // 当天首次入座：唯一一条 DAY_CARD 账单，固定 30 元，不再额外写 0 元行
                kind = "DAY_CARD";
                unitPrice = props.billing().dayCardPrice();
                amount = BillingMath.money(unitPrice, 60);
                detail = "包天卡当天首次入座，扣 " + props.billing().dayCardPrice() + " 元";
            } else {
                amount = BillingMath.money(BigDecimal.ZERO, minutes);
                detail = "包天卡当天已扣过 " + props.billing().dayCardPrice() + " 元，本次不重复扣费";
            }
        } else {
            CloudBillingClient.Quote quote = cloud.quote(res.unitPrice(), minutes);
            amount = quote.amount();
            source = quote.source();
            detail = quote.detail();
        }

        String orderNo = nextOrderNo(now);
        jdbc.update("""
                INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, orderNo, res.id(), userId, kind, minutes, unitPrice, amount, cardType, source, now);

        if (amount.signum() > 0) {
            jdbc.update("UPDATE app_user SET balance = balance - ? WHERE id = ?", amount, userId);
        }
        jdbc.update("UPDATE reservation SET status = 'CHECKED_OUT', checkout_at = ? WHERE id = ?", now, res.id());
        seats.markFree(res.seatId());
        log.info("签退：预约 {} 用 {} 分钟，{} 元（{}，{}）", res.id(), minutes, amount, source, detail);

        return jdbc.queryForObject("SELECT * FROM bill_order WHERE order_no = ?", (rs, i) -> mapBill(rs), orderNo);
    }

    /** 当天是否已经扣过包天卡（用于“当天再次入座不重复扣费”）。 */
    private boolean hasDayCardCharge(long userId, LocalDate day) {
        Integer exists = jdbc.queryForObject("""
                SELECT COUNT(*) FROM bill_order
                 WHERE user_id = ? AND kind = 'DAY_CARD' AND DATE(created_at) = ?
                """, Integer.class, userId, day);
        return exists != null && exists > 0;
    }

    /** 超时释放：座位释放 + 信用 −10 + 1 小时单价违约金，全部幂等。 */
    @Transactional
    public int releaseOverdueAll() {
        LocalDateTime now = clock.now();
        List<Reservation> overdue = jdbc.query(SELECT + " WHERE r.status = 'RESERVED' AND r.expire_at <= ?", MAPPER, now);
        int handled = 0;
        for (Reservation res : overdue) {
            try {
                if (releaseOverdue(res, now)) {
                    handled++;
                }
            } catch (Exception e) {
                log.warn("预约 {} 超时处理失败：{}", res.id(), e.toString());
            }
        }
        return handled;
    }

    /** 返回 true 表示本次真的处理了（重复调用返回 false，不产生第二条记录）。 */
    @Transactional
    public boolean releaseOverdue(Reservation res, LocalDateTime now) {
        int rows = jdbc.update("UPDATE reservation SET status = 'EXPIRED' WHERE id = ? AND status = 'RESERVED'", res.id());
        if (rows == 0) {
            return false;
        }
        seats.markFree(res.seatId());
        Integer creditExists = jdbc.queryForObject(
                "SELECT COUNT(*) FROM credit_log WHERE idem_key = ?", Integer.class, "TIMEOUT-" + res.id());
        if (creditExists == null || creditExists == 0) {
            int penalty = props.billing().creditPenalty();
            jdbc.update("""
                    INSERT INTO credit_log (user_id, delta, reason, idem_key, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, res.userId(), -penalty, "预约后 15 分钟未签到，系统释放座位", "TIMEOUT-" + res.id(), now);
            jdbc.update("UPDATE app_user SET credit = GREATEST(credit - ?, 0) WHERE id = ?", penalty, res.userId());
        }
        Integer billExists = jdbc.queryForObject(
                "SELECT COUNT(*) FROM bill_order WHERE reservation_id = ? AND kind = 'OVERTIME'", Integer.class, res.id());
        if (billExists == null || billExists == 0) {
            BigDecimal fee = BillingMath.round2(seats.room().currentPrice());
            jdbc.update("""
                    INSERT INTO bill_order (order_no, reservation_id, user_id, kind, minutes, unit_price, amount, card_type, source, created_at)
                    VALUES (?, ?, ?, 'OVERTIME', 0, ?, ?, 'NONE', 'LOCAL', ?)
                    """, nextOrderNo(now), res.id(), res.userId(), fee, fee, now);
            jdbc.update("UPDATE app_user SET balance = balance - ? WHERE id = ?", fee, res.userId());
        }
        log.info("超时释放：预约 {} 座位 {} 已释放并扣信用", res.id(), res.seatCode());
        return true;
    }

    public BillView mapBill(ResultSet rs) throws SQLException {
        return new BillView(
                rs.getLong("id"),
                rs.getString("order_no"),
                rs.getLong("user_id"),
                rs.getString("kind"),
                rs.getInt("minutes"),
                rs.getBigDecimal("unit_price"),
                rs.getBigDecimal("amount"),
                rs.getString("card_type"),
                rs.getString("source"),
                rs.getTimestamp("created_at").toLocalDateTime());
    }

    private void requireOwner(Reservation res, long userId) {
        if (res.userId() != userId) {
            throw new BizException("只能操作自己的预约");
        }
    }

    private String nextOrderNo(LocalDateTime now) {
        Integer today = jdbc.queryForObject(
                "SELECT COUNT(*) FROM bill_order WHERE DATE(created_at) = ?", Integer.class, now.toLocalDate());
        int seq = (today == null ? 0 : today) + 1;
        String orderNo = "D" + now.format(DAY) + "-" + String.format("%04d", seq);
        // 极端并发下重试一次，避免唯一键冲突影响演示
        while (jdbc.queryForObject("SELECT COUNT(*) FROM bill_order WHERE order_no = ?", Integer.class, orderNo) > 0) {
            seq++;
            orderNo = "D" + now.format(DAY) + "-" + String.format("%04d", seq);
        }
        return orderNo;
    }
}
