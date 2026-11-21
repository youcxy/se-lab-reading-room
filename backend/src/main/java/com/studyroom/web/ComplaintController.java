package com.studyroom.web;

import com.studyroom.common.ApiResult;
import com.studyroom.service.ComplaintService;
import com.studyroom.service.UserService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 投诉：提交（自习人员）、处理（店长）。 */
@RestController
@RequestMapping("/api")
public class ComplaintController {

    public record CreateRequest(long userId, String content) {
    }

    public record HandleRequest(long handlerId, String result) {
    }

    private final ComplaintService complaints;
    private final UserService users;

    public ComplaintController(ComplaintService complaints, UserService users) {
        this.complaints = complaints;
        this.users = users;
    }

    @GetMapping("/complaints")
    public ApiResult<List<ComplaintService.Complaint>> list(@RequestParam(required = false) String status) {
        return ApiResult.ok(complaints.list(status));
    }

    @PostMapping("/complaints")
    public ApiResult<ComplaintService.Complaint> create(@RequestBody CreateRequest request) {
        return ApiResult.ok(complaints.create(request.userId(), request.content()));
    }

    @PostMapping("/complaints/{id}/handle")
    public ApiResult<ComplaintService.Complaint> handle(@PathVariable long id, @RequestBody HandleRequest request) {
        users.requireRole(request.handlerId(), "MANAGER", "ADMIN");
        return ApiResult.ok(complaints.handle(id, request.handlerId(), request.result()));
    }
}
