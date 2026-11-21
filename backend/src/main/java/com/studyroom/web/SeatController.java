package com.studyroom.web;

import com.studyroom.common.ApiResult;
import com.studyroom.service.ReservationService;
import com.studyroom.service.SeatService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** 座位图与预约。 */
@RestController
@RequestMapping("/api")
public class SeatController {

    public record ReserveRequest(long userId) {
    }

    private final SeatService seats;
    private final ReservationService reservations;

    public SeatController(SeatService seats, ReservationService reservations) {
        this.seats = seats;
        this.reservations = reservations;
    }

    @GetMapping("/room")
    public ApiResult<Map<String, Object>> room() {
        SeatService.Room room = seats.room();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("id", room.id());
        body.put("name", room.name());
        body.put("seatCount", room.seatCount());
        body.put("basePrice", room.basePrice());
        body.put("currentPrice", room.currentPrice());
        body.put("occupied", seats.occupiedCount());
        body.put("total", seats.totalCount());
        return ApiResult.ok(body);
    }

    @GetMapping("/seats")
    public ApiResult<List<SeatService.Seat>> seats() {
        return ApiResult.ok(seats.seats());
    }

    @PostMapping("/seats/{seatId}/reserve")
    public ApiResult<ReservationService.Reservation> reserve(@PathVariable long seatId,
                                                             @RequestBody ReserveRequest request) {
        return ApiResult.ok(reservations.reserve(request.userId(), seatId));
    }
}
