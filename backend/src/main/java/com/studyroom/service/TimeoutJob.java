package com.studyroom.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 每日一次的超时释放任务（对应需求“每日一次定时触发器释放预约后 15 分钟未签到的座位”）。
 * 与手工接口 POST /api/timeout/run 调用的是同一段逻辑，重复执行不会产生第二条记录。
 */
@Component
public class TimeoutJob {

    private static final Logger log = LoggerFactory.getLogger(TimeoutJob.class);

    private final ReservationService reservations;

    public TimeoutJob(ReservationService reservations) {
        this.reservations = reservations;
    }

    @Scheduled(cron = "0 5 0 * * *")
    public void runDaily() {
        int handled = reservations.releaseOverdueAll();
        log.info("每日超时释放任务完成，处理 {} 条", handled);
    }
}
