package com.studyroom.web;

import com.studyroom.common.ApiResult;
import com.studyroom.service.ClockService;
import com.studyroom.service.UserService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 登录、用户列表、模拟时钟（演示 15 分钟超时用，只影响业务时间）。 */
@RestController
@RequestMapping("/api")
public class AuthController {

    public record LoginRequest(String login, String password) {
    }

    public record ClockRequest(Long offsetSeconds, Long advanceMinutes) {
    }

    private final UserService users;
    private final ClockService clock;

    public AuthController(UserService users, ClockService clock) {
        this.users = users;
        this.clock = clock;
    }

    @GetMapping("/health")
    public ApiResult<Map<String, Object>> health() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", "UP");
        body.put("time", LocalDateTime.now().toString());
        body.put("businessTime", clock.now().toString());
        return ApiResult.ok(body);
    }

    @PostMapping("/auth/login")
    public ApiResult<UserService.User> login(@RequestBody LoginRequest request) {
        return ApiResult.ok(users.login(request.login(), request.password()));
    }

    @GetMapping("/users")
    public ApiResult<List<UserService.User>> users() {
        return ApiResult.ok(users.listAll());
    }

    @GetMapping("/clock")
    public ApiResult<Map<String, Object>> clock() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("offsetSeconds", clock.offsetSeconds());
        body.put("businessTime", clock.now().toString());
        return ApiResult.ok(body);
    }

    @PutMapping("/clock")
    public ApiResult<Map<String, Object>> setClock(@RequestBody ClockRequest request) {
        if (request.advanceMinutes() != null) {
            clock.advanceMinutes(request.advanceMinutes());
        }
        if (request.offsetSeconds() != null) {
            clock.setOffsetSeconds(request.offsetSeconds());
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("offsetSeconds", clock.offsetSeconds());
        body.put("businessTime", clock.now().toString());
        return ApiResult.ok(body);
    }

    @PostMapping("/clock/reset")
    public ApiResult<Map<String, Object>> resetClock() {
        clock.reset();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("offsetSeconds", 0);
        body.put("businessTime", clock.now().toString());
        return ApiResult.ok(body);
    }
}
