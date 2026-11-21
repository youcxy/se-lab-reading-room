package com.studyroom.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.math.BigDecimal;

/** 计费与云函数相关的可配置参数（对应 application.yml 的 app.* 节点）。 */
@ConfigurationProperties(prefix = "app")
public record AppProperties(Billing billing, Cloud cloud) {

    public record Billing(
            BigDecimal hourlyPrice,
            BigDecimal dayCardPrice,
            int overtimeMinutes,
            int creditPenalty,
            int minCredit,
            BigDecimal occupancyThreshold,
            BigDecimal surgeFactor) {
    }

    public record Cloud(String endpoint, int timeoutMs) {
    }
}
