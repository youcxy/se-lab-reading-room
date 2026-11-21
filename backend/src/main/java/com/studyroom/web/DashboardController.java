package com.studyroom.web;

import com.studyroom.common.ApiResult;
import com.studyroom.service.DashboardService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/** 店长看板。 */
@RestController
@RequestMapping("/api")
public class DashboardController {

    private final DashboardService dashboard;

    public DashboardController(DashboardService dashboard) {
        this.dashboard = dashboard;
    }

    @GetMapping("/dashboard")
    public ApiResult<DashboardService.Summary> summary(@RequestParam(required = false) String from,
                                                      @RequestParam(required = false) String to) {
        return ApiResult.ok(dashboard.summary(from, to));
    }

    @GetMapping("/dashboard/orders")
    public ApiResult<List<Map<String, Object>>> orders(@RequestParam(required = false) String from,
                                                       @RequestParam(required = false) String to) {
        return ApiResult.ok(dashboard.orders(from, to));
    }
}
