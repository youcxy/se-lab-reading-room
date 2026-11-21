package com.studyroom.service;

import com.studyroom.common.BizException;
import com.studyroom.config.AppProperties;
import com.studyroom.core.BillingMath;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/** 上座率调价：占用÷总数 超过 80% 时单价 ×1.2，每次变价一条记录，可按日导出。 */
@Service
public class PricingService {

    public record PriceStatus(int occupied, int total, BigDecimal occupancyRate, BigDecimal threshold,
                              BigDecimal basePrice, BigDecimal currentPrice, BigDecimal expectedPrice,
                              boolean shouldChange) {
    }

    public record PriceChange(long id, int occupied, int totalSeats, BigDecimal occupancyRate,
                              BigDecimal oldPrice, BigDecimal newPrice, String operator, LocalDateTime createdAt) {
    }

    private static final DateTimeFormatter FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd");

    private static final RowMapper<PriceChange> MAPPER = (rs, i) -> new PriceChange(
            rs.getLong("id"), rs.getInt("occupied"), rs.getInt("total_seats"),
            rs.getBigDecimal("occupancy_rate"), rs.getBigDecimal("old_price"),
            rs.getBigDecimal("new_price"), rs.getString("operator"),
            rs.getTimestamp("created_at").toLocalDateTime());

    private final JdbcTemplate jdbc;
    private final SeatService seats;
    private final ClockService clock;
    private final AppProperties props;

    public PricingService(JdbcTemplate jdbc, SeatService seats, ClockService clock, AppProperties props) {
        this.jdbc = jdbc;
        this.seats = seats;
        this.clock = clock;
        this.props = props;
    }

    public PriceStatus status() {
        SeatService.Room room = seats.room();
        int occupied = seats.occupiedCount();
        int total = seats.totalCount();
        BigDecimal rate = total == 0 ? BigDecimal.ZERO
                : BigDecimal.valueOf(occupied).divide(BigDecimal.valueOf(total), 4, RoundingMode.HALF_UP);
        BigDecimal base = room.basePrice();
        BigDecimal threshold = props.billing().occupancyThreshold();
        boolean surge = rate.compareTo(threshold) > 0;
        BigDecimal expected = BillingMath.round2(surge
                ? base.multiply(props.billing().surgeFactor())
                : base);
        // 只有“超过阈值需要涨价”才产生变价记录；未超阈值时保持当前价、不写记录。
        boolean shouldChange = surge && expected.compareTo(room.currentPrice()) != 0;
        return new PriceStatus(occupied, total, rate, threshold, base, room.currentPrice(), expected, shouldChange);
    }

    /**
     * 按当前上座率执行调价。未跨过阈值（或价格本来就对）时不产生记录，返回 null。
     * 只有店长可以调价；涨价只影响此后新开始的使用（预约时把单价快照写进 reservation.unit_price）。
     */
    @Transactional
    public PriceChange apply(long operatorId, String operatorName) {
        PriceStatus now = status();
        if (!now.shouldChange()) {
            return null;
        }
        SeatService.Room room = seats.room();
        jdbc.update("UPDATE room SET current_price = ?, updated_at = ? WHERE id = ?",
                now.expectedPrice(), clock.now(), room.id());
        jdbc.update("""
                INSERT INTO price_change (room_id, occupied, total_seats, occupancy_rate, old_price, new_price, operator, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, room.id(), now.occupied(), now.total(), now.occupancyRate(),
                now.currentPrice(), now.expectedPrice(), operatorName, clock.now());
        return latest();
    }

    public PriceChange latest() {
        List<PriceChange> list = jdbc.query(
                "SELECT * FROM price_change ORDER BY id DESC LIMIT 1", MAPPER);
        return list.isEmpty() ? null : list.get(0);
    }

    public List<PriceChange> changes(String date) {
        if (date == null || date.isBlank()) {
            return jdbc.query("SELECT * FROM price_change ORDER BY id DESC", MAPPER);
        }
        return jdbc.query("SELECT * FROM price_change WHERE DATE(created_at) = ? ORDER BY id", MAPPER, date);
    }

    /** 按日导出 CSV（含占用数、总数、上座率、原价、新价、操作人、时间）。 */
    public String exportCsv(String date) {
        String day = date == null || date.isBlank() ? LocalDateTime.now().format(FMT) : date;
        List<PriceChange> list = changes(day);
        if (list.isEmpty()) {
            throw new BizException(day + " 没有变价记录，未超过 80% 不产生调价记录");
        }
        StringBuilder sb = new StringBuilder();
        sb.append("序号,日期时间,占用数,座位总数,上座率,原价,新价,操作人\n");
        int i = 1;
        for (PriceChange c : list) {
            sb.append(i++).append(',')
              .append(c.createdAt().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))).append(',')
              .append(c.occupied()).append(',')
              .append(c.totalSeats()).append(',')
              .append(c.occupancyRate().multiply(BigDecimal.valueOf(100)).setScale(0, RoundingMode.HALF_UP)).append("%,")
              .append(c.oldPrice()).append(',')
              .append(c.newPrice()).append(',')
              .append(c.operator()).append('\n');
        }
        return sb.toString();
    }
}
