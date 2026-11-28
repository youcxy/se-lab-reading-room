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

    /**
     * 云端计费的三条通路，按优先级择一：
     * 1) AK/SK 直调 FunctionGraph 同步执行 API（真云端，无需 APIG，推荐）；
     * 2) HTTP 触发器 / 本地模拟器的 endpoint（兼容旧部署）；
     * 3) 都没有时纯本地计算。
     */
    public record Cloud(
            String endpoint,
            int timeoutMs,
            String ak,
            String sk,
            String projectId,
            String functionUrn,
            String functionName,
            String region,
            String sdkEndpoint) {

        private static boolean has(String v) {
            return v != null && !v.isBlank();
        }

        /** 是否启用「AK/SK 直调 FunctionGraph」。密钥只来自环境变量，不进仓库。 */
        public boolean sdkEnabled() {
            return has(ak) && has(sk) && has(projectId) && has(resolvedUrn());
        }

        public String resolvedRegion() {
            return has(region) ? region : "cn-north-4";
        }

        /**
         * 函数 URN。控制台可直接复制完整 URN；只填函数名时按官方格式拼接：
         * urn:fss:{region}:{projectId}:function:default:{name}:latest
         */
        public String resolvedUrn() {
            if (has(functionUrn)) {
                return functionUrn;
            }
            if (has(functionName) && has(projectId)) {
                return "urn:fss:" + resolvedRegion() + ":" + projectId
                        + ":function:default:" + functionName + ":latest";
            }
            return null;
        }
    }
}
