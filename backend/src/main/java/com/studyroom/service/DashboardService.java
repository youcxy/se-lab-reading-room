package com.studyroom.service;

import com.studyroom.common.BizException;
import com.studyroom.core.BillingMath;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 店长看板：订单数、客单价、复购人数，全部直接由账单明细聚合，不另存一套数。 */
@Service
public class DashboardService {

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    public record Summary(String from, String to, int orders, BigDecimal revenue, BigDecimal avgTicket,
                          int repeatUsers, int pendingComplaints, BigDecimal occupancyRate,
                          int occupied, int total, BigDecimal currentPrice) {
    }

    private final JdbcTemplate jdbc;
    private final SeatService seats;

    public DashboardService(JdbcTemplate jdbc, SeatService seats) {
        this.jdbc = jdbc;
        this.seats = seats;
    }

    public Summary summary(String fromText, String toText) {
        String from = fromText == null || fromText.isBlank() ? LocalDateTime.now().format(FMT) : fromText;
        String to = toText == null || toText.isBlank() ? from : toText;
        if (to.compareTo(from) < 0) {
            throw new BizException("结束日期不能早于开始日期");
        }
        Map<String, Object> params = new LinkedHashMap<>();
        String range = "created_at >= ? AND created_at < DATE_ADD(?, INTERVAL 1 DAY)";

        Integer orders = jdbc.queryForObject(
                "SELECT COUNT(*) FROM bill_order WHERE " + range, Integer.class, from, to);
        BigDecimal revenue = jdbc.queryForObject(
                "SELECT IFNULL(SUM(amount), 0) FROM bill_order WHERE " + range, BigDecimal.class, from, to);
        BigDecimal avgTicket = jdbc.queryForObject(
                "SELECT ROUND(IFNULL(SUM(amount) / NULLIF(COUNT(*), 0), 0), 2) FROM bill_order WHERE " + range,
                BigDecimal.class, from, to);
        Integer repeat = jdbc.queryForObject("""
                SELECT COUNT(*) FROM (
                  SELECT user_id FROM bill_order WHERE %s
                   GROUP BY user_id HAVING COUNT(*) >= 2) t
                """.formatted(range), Integer.class, from, to);
        Integer pending = jdbc.queryForObject(
                "SELECT COUNT(*) FROM complaint WHERE status = 'PENDING'", Integer.class);

        int occupied = seats.occupiedCount();
        int total = seats.totalCount();
        BigDecimal rate = total == 0 ? BigDecimal.ZERO
                : BigDecimal.valueOf(occupied).divide(BigDecimal.valueOf(total), 4, java.math.RoundingMode.HALF_UP);
        return new Summary(from, to,
                orders == null ? 0 : orders,
                BillingMath.round2(revenue),
                BillingMath.round2(avgTicket),
                repeat == null ? 0 : repeat,
                pending == null ? 0 : pending,
                rate, occupied, total, seats.room().currentPrice());
    }

    /** 订单明细，用于看板“可展开核对”。 */
    public List<Map<String, Object>> orders(String from, String to) {
        String f = from == null || from.isBlank() ? LocalDateTime.now().format(FMT) : from;
        String t = to == null || to.isBlank() ? f : to;
        return jdbc.query("""
                SELECT o.order_no AS orderNo, u.display_name AS user, o.kind AS kind,
                       o.minutes AS minutes, o.unit_price AS unitPrice, o.amount AS amount,
                       o.card_type AS cardType, o.source AS source,
                       DATE_FORMAT(o.created_at, '%Y-%m-%d %H:%i:%s') AS createdAt
                  FROM bill_order o JOIN app_user u ON u.id = o.user_id
                 WHERE o.created_at >= ? AND o.created_at < DATE_ADD(?, INTERVAL 1 DAY)
                 ORDER BY o.id DESC
                """, (rs, i) -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("orderNo", rs.getString("orderNo"));
            row.put("user", rs.getString("user"));
            row.put("kind", rs.getString("kind"));
            row.put("minutes", rs.getInt("minutes"));
            row.put("unitPrice", rs.getBigDecimal("unitPrice"));
            row.put("amount", rs.getBigDecimal("amount"));
            row.put("cardType", rs.getString("cardType"));
            row.put("source", rs.getString("source"));
            row.put("createdAt", rs.getString("createdAt"));
            return row;
        }, f, t);
    }
}
