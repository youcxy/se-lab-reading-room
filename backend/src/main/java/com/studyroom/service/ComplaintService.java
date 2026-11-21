package com.studyroom.service;

import com.studyroom.common.BizException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/** 投诉处理：未填写处理结果不得置为已处理。 */
@Service
public class ComplaintService {

    public record Complaint(long id, long userId, String userName, String content, String status,
                            String handleResult, Long handlerId, String handlerName,
                            LocalDateTime createdAt, LocalDateTime handledAt) {
    }

    private static final RowMapper<Complaint> MAPPER = (rs, i) -> new Complaint(
            rs.getLong("id"), rs.getLong("user_id"), rs.getString("user_name"),
            rs.getString("content"), rs.getString("status"), rs.getString("handle_result"),
            (Long) rs.getObject("handler_id"), rs.getString("handler_name"),
            rs.getTimestamp("created_at").toLocalDateTime(),
            rs.getTimestamp("handled_at") == null ? null : rs.getTimestamp("handled_at").toLocalDateTime());

    private static final String SELECT = """
            SELECT c.*, u.display_name AS user_name, h.display_name AS handler_name
              FROM complaint c
              JOIN app_user u ON u.id = c.user_id
              LEFT JOIN app_user h ON h.id = c.handler_id
            """;

    private final JdbcTemplate jdbc;
    private final ClockService clock;

    public ComplaintService(JdbcTemplate jdbc, ClockService clock) {
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Transactional
    public Complaint create(long userId, String content) {
        if (content == null || content.isBlank()) {
            throw new BizException("投诉内容不能为空");
        }
        jdbc.update("INSERT INTO complaint (user_id, content, status, created_at) VALUES (?, ?, 'PENDING', ?)",
                userId, content.trim(), clock.now());
        Long id = jdbc.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        return require(id);
    }

    public List<Complaint> list(String status) {
        if (status == null || status.isBlank()) {
            return jdbc.query(SELECT + " ORDER BY c.id DESC", MAPPER);
        }
        return jdbc.query(SELECT + " WHERE c.status = ? ORDER BY c.id DESC", MAPPER, status);
    }

    public Complaint require(long id) {
        List<Complaint> list = jdbc.query(SELECT + " WHERE c.id = ?", MAPPER, id);
        if (list.isEmpty()) {
            throw new BizException("投诉不存在：" + id);
        }
        return list.get(0);
    }

    /** 处理投诉：处理结果为空时直接拒绝，接口不会把状态改成 DONE。 */
    @Transactional
    public Complaint handle(long complaintId, long handlerId, String result) {
        Complaint complaint = require(complaintId);
        if (result == null || result.isBlank()) {
            throw new BizException("必须填写处理结果才能置为已处理");
        }
        if ("DONE".equals(complaint.status())) {
            throw new BizException("该投诉已处理，不能重复处理");
        }
        LocalDateTime now = clock.now();
        jdbc.update("UPDATE complaint SET status = 'DONE', handle_result = ?, handler_id = ?, handled_at = ? WHERE id = ? AND status = 'PENDING'",
                result.trim(), handlerId, now, complaintId);
        return require(complaintId);
    }
}
