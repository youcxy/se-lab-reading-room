package com.studyroom.service;

import com.studyroom.common.BizException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.List;

/** 座位与自习室：座位三态与当前单价。 */
@Service
public class SeatService {

    public record Seat(long id, String code, String status, boolean leaveFlag, Long currentUserId, String currentUserName) {
    }

    public record Room(long id, String name, int seatCount, BigDecimal basePrice, BigDecimal currentPrice) {
    }

    private static final RowMapper<Seat> SEAT_MAPPER = (rs, i) -> new Seat(
            rs.getLong("id"),
            rs.getString("code"),
            rs.getString("status"),
            rs.getInt("leave_flag") == 1,
            (Long) rs.getObject("current_user_id"),
            rs.getString("current_user_name"));

    private static final String SEAT_SELECT = """
            SELECT s.*, u.display_name AS current_user_name
              FROM seat s LEFT JOIN app_user u ON u.id = s.current_user_id
            """;

    private final JdbcTemplate jdbc;

    public SeatService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Room room() {
        return jdbc.queryForObject("SELECT * FROM room ORDER BY id LIMIT 1", (rs, i) -> new Room(
                rs.getLong("id"), rs.getString("name"), rs.getInt("seat_count"),
                rs.getBigDecimal("base_price"), rs.getBigDecimal("current_price")));
    }

    public List<Seat> seats() {
        return jdbc.query(SEAT_SELECT + " ORDER BY s.code", SEAT_MAPPER);
    }

    public Seat require(long seatId) {
        List<Seat> list = jdbc.query(SEAT_SELECT + " WHERE s.id = ?", SEAT_MAPPER, seatId);
        if (list.isEmpty()) {
            throw new BizException("座位不存在：" + seatId);
        }
        return list.get(0);
    }

    public int occupiedCount() {
        Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM seat WHERE status <> 'FREE'", Integer.class);
        return n == null ? 0 : n;
    }

    public int totalCount() {
        Integer n = jdbc.queryForObject("SELECT COUNT(*) FROM seat", Integer.class);
        return n == null ? 0 : n;
    }

    /** 只有空闲座位能置为已预约；乐观并发由 WHERE status='FREE' 保证。 */
    public void markReserved(long seatId, long userId) {
        int rows = jdbc.update("UPDATE seat SET status = 'RESERVED', current_user_id = ?, leave_flag = 0 WHERE id = ? AND status = 'FREE'",
                userId, seatId);
        if (rows == 0) {
            throw new BizException("该座位刚被他人占用，请刷新后重试");
        }
    }

    public void markInUse(long seatId, long userId) {
        jdbc.update("UPDATE seat SET status = 'IN_USE', current_user_id = ?, leave_flag = 0 WHERE id = ?", userId, seatId);
    }

    public void markFree(long seatId) {
        jdbc.update("UPDATE seat SET status = 'FREE', current_user_id = NULL, leave_flag = 0 WHERE id = ?", seatId);
    }

    public void setLeaveFlag(long seatId, boolean leaving) {
        jdbc.update("UPDATE seat SET leave_flag = ? WHERE id = ?", leaving ? 1 : 0, seatId);
    }
}
