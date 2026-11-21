package com.studyroom.service;

import com.studyroom.common.BizException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

/** 用户与角色：三类角色的越权限制在这里统一挡掉（不得改单价、不得改信用分等）。 */
@Service
public class UserService {

    public record User(long id, String login, String displayName, String role, int credit,
                       BigDecimal balance, LocalDate monthlyExpireDate, LocalDate dayPassDate) {
    }

    private static final RowMapper<User> MAPPER = (rs, i) -> new User(
            rs.getLong("id"),
            rs.getString("login"),
            rs.getString("display_name"),
            rs.getString("role"),
            rs.getInt("credit"),
            rs.getBigDecimal("balance"),
            rs.getDate("monthly_expire_date") == null ? null : rs.getDate("monthly_expire_date").toLocalDate(),
            rs.getDate("day_pass_date") == null ? null : rs.getDate("day_pass_date").toLocalDate());

    private final JdbcTemplate jdbc;

    public UserService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<User> listAll() {
        return jdbc.query("SELECT * FROM app_user ORDER BY id", MAPPER);
    }

    public User require(long id) {
        List<User> list = jdbc.query("SELECT * FROM app_user WHERE id = ?", MAPPER, id);
        if (list.isEmpty()) {
            throw new BizException("用户不存在：" + id);
        }
        return list.get(0);
    }

    public User login(String login, String password) {
        List<User> list = jdbc.query("SELECT * FROM app_user WHERE login = ?", MAPPER, login);
        if (list.isEmpty()) {
            throw new BizException("登录名或口令不正确");
        }
        String stored = jdbc.queryForObject("SELECT password FROM app_user WHERE login = ?", String.class, login);
        if (stored == null || !stored.equals(password)) {
            throw new BizException("登录名或口令不正确");
        }
        return list.get(0);
    }

    /** 只有指定角色可以继续，否则 400。 */
    public User requireRole(long id, String... roles) {
        User user = require(id);
        for (String role : roles) {
            if (role.equals(user.role())) {
                return user;
            }
        }
        throw new BizException("当前角色（" + user.role() + "）无权执行该操作");
    }

    public boolean isMonthlyValid(User user, LocalDate today) {
        return user.monthlyExpireDate() != null && !today.isAfter(user.monthlyExpireDate());
    }

    public boolean hasDayPass(User user, LocalDate today) {
        return user.dayPassDate() != null && user.dayPassDate().isEqual(today);
    }
}
