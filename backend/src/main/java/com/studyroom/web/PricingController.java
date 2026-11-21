package com.studyroom.web;

import com.studyroom.common.ApiResult;
import com.studyroom.service.PricingService;
import com.studyroom.service.UserService;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.util.List;

/** 上座率调价与变价记录导出（仅店长可调价）。 */
@RestController
@RequestMapping("/api")
public class PricingController {

    public record AdjustRequest(long operatorId) {
    }

    private final PricingService pricing;
    private final UserService users;

    public PricingController(PricingService pricing, UserService users) {
        this.pricing = pricing;
        this.users = users;
    }

    @GetMapping("/pricing/status")
    public ApiResult<PricingService.PriceStatus> status() {
        return ApiResult.ok(pricing.status());
    }

    @PostMapping("/pricing/adjust")
    public ApiResult<PricingService.PriceChange> adjust(@RequestBody AdjustRequest request) {
        UserService.User operator = users.requireRole(request.operatorId(), "MANAGER");
        return ApiResult.ok(pricing.apply(operator.id(), operator.displayName()));
    }

    @GetMapping("/pricing/changes")
    public ApiResult<List<PricingService.PriceChange>> changes(@RequestParam(required = false) String date) {
        return ApiResult.ok(pricing.changes(date));
    }

    @GetMapping("/pricing/changes/export")
    public ResponseEntity<byte[]> export(@RequestParam(required = false) String date) {
        String csv = pricing.exportCsv(date);
        byte[] bytes = ("\uFEFF" + csv).getBytes(StandardCharsets.UTF_8);
        String filename = "price-change-" + (date == null || date.isBlank() ? "all" : date) + ".csv";
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        ContentDisposition.attachment().filename(filename).build().toString())
                .contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .body(bytes);
    }
}
