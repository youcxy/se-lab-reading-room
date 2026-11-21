package com.studyroom.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * 业务时间来源。演示需要“把时间往前推 15 分钟”来触发超时，
 * 因此所有业务时间都走这里，而不是直接 LocalDateTime.now()（不改服务器系统时钟）。
 */
@Service
public class ClockService {

    private final JdbcTemplate jdbc;

    public ClockService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public LocalDateTime now() {
        return LocalDateTime.now().plusSeconds(offsetSeconds());
    }

    public long offsetSeconds() {
        Long offset = jdbc.query("SELECT offset_seconds FROM sim_clock WHERE id = 1",
                rs -> rs.next() ? rs.getLong(1) : null);
        return offset == null ? 0L : offset;
    }

    @Transactional
    public long setOffsetSeconds(long seconds) {
        int rows = jdbc.update("UPDATE sim_clock SET offset_seconds = ? WHERE id = 1", seconds);
        if (rows == 0) {
            jdbc.update("INSERT INTO sim_clock (id, offset_seconds) VALUES (1, ?)", seconds);
        }
        return seconds;
    }

    @Transactional
    public long advanceMinutes(long minutes) {
        long next = offsetSeconds() + minutes * 60L;
        setOffsetSeconds(next);
        return next;
    }

    @Transactional
    public long reset() {
        setOffsetSeconds(0L);
        return 0L;
    }
}
