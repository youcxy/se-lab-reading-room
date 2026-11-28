package com.studyroom.web;

import com.studyroom.common.ApiResult;
import com.studyroom.service.CloudBillingClient;
import com.studyroom.service.ReservationService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.List;

/** 预约生命周期与云端计费。 */
@RestController
@RequestMapping("/api")
public class ReservationController {

    public record UserRequest(long userId) {
    }

    public record QuoteRequest(BigDecimal unitPrice, int minutes) {
    }

    private final ReservationService reservations;
    private final CloudBillingClient cloud;

    public ReservationController(ReservationService reservations, CloudBillingClient cloud) {
        this.reservations = reservations;
        this.cloud = cloud;
    }

    @GetMapping("/reservations")
    public ApiResult<List<ReservationService.Reservation>> list(@RequestParam(required = false) Long userId) {
        return ApiResult.ok(userId == null ? reservations.listRecent(20) : reservations.listByUser(userId));
    }

    @GetMapping("/bills")
    public ApiResult<List<ReservationService.BillView>> bills(@RequestParam(required = false) Long userId) {
        return ApiResult.ok(reservations.listBills(userId));
    }

    @GetMapping("/reservations/{id}")
    public ApiResult<ReservationService.Reservation> one(@PathVariable long id) {
        return ApiResult.ok(reservations.require(id));
    }

    @PostMapping("/reservations/{id}/checkin")
    public ApiResult<ReservationService.Reservation> checkin(@PathVariable long id, @RequestBody UserRequest req) {
        return ApiResult.ok(reservations.checkin(id, req.userId()));
    }

    @PostMapping("/reservations/{id}/leave")
    public ApiResult<ReservationService.Reservation> leave(@PathVariable long id, @RequestBody UserRequest req) {
        return ApiResult.ok(reservations.tempLeave(id, req.userId()));
    }

    @PostMapping("/reservations/{id}/end-leave")
    public ApiResult<ReservationService.Reservation> endLeave(@PathVariable long id, @RequestBody UserRequest req) {
        return ApiResult.ok(reservations.endLeave(id, req.userId()));
    }

    @PostMapping("/reservations/{id}/checkout")
    public ApiResult<ReservationService.BillView> checkout(@PathVariable long id, @RequestBody UserRequest req) {
        return ApiResult.ok(reservations.checkout(id, req.userId()));
    }

    /** 手工触发超时释放：与定时触发器调用同一段逻辑，重复触发不产生第二条记录。 */
    @PostMapping("/timeout/run")
    public ApiResult<Integer> runTimeout() {
        return ApiResult.ok(reservations.releaseOverdueAll());
    }

    /** 页面上的“云端计算”按钮也走这里，便于演示云函数可用与不可用两种情况。 */
    @PostMapping("/cloud/quote")
    public ApiResult<CloudBillingClient.Quote> quote(@RequestBody QuoteRequest req) {
        return ApiResult.ok(cloud.quote(req.unitPrice(), req.minutes()));
    }

    /** 部署自检：返回当前云端计费通路（不含任何密钥）。 */
    @GetMapping("/cloud/status")
    public ApiResult<CloudBillingClient.Status> cloudStatus() {
        return ApiResult.ok(cloud.status());
    }
}
