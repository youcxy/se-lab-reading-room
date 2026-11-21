package com.studyroom.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.studyroom.config.AppProperties;
import com.studyroom.core.BillingMath;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 金额的云端计算：调用华为云函数工作流（FunctionGraph）的 HTTP 触发器。
 * 未配置 endpoint 或调用失败时退回本地同一算法，并把来源记为 LOCAL，保证页面可用且数值一致。
 */
@Service
public class CloudBillingClient {

    private static final Logger log = LoggerFactory.getLogger(CloudBillingClient.class);

    public record Quote(BigDecimal amount, String source, String detail) {
    }

    private final AppProperties props;
    private final ObjectMapper json = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    public CloudBillingClient(AppProperties props) {
        this.props = props;
    }

    public Quote quote(BigDecimal unitPrice, int minutes) {
        BillingMath.money(unitPrice, minutes); // 本地算法作为兜底基准
        String endpoint = props.cloud() == null ? null : props.cloud().endpoint();
        if (endpoint == null || endpoint.isBlank()) {
            return new Quote(BillingMath.money(unitPrice, minutes), "LOCAL", "未配置 FG_ENDPOINT，使用本地计算");
        }
        try {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("unitPrice", unitPrice.toPlainString());
            payload.put("minutes", minutes);
            HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
                    .timeout(Duration.ofMillis(props.cloud().timeoutMs()))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)))
                    .build();
            // 云函数返回的 Content-Type 通常不带 charset，按 UTF-8 解码避免中文说明变乱码
            HttpResponse<byte[]> response = http.send(request, HttpResponse.BodyHandlers.ofByteArray());
            if (response.statusCode() / 100 != 2) {
                return new Quote(BillingMath.money(unitPrice, minutes), "LOCAL", "云函数返回 HTTP " + response.statusCode());
            }
            String body = new String(response.body(), java.nio.charset.StandardCharsets.UTF_8);
            JsonNode node = json.readTree(body);
            JsonNode amountNode = node.has("amount") ? node.get("amount") : node.get("body");
            BigDecimal amount = new BigDecimal(amountNode.asText()).setScale(2, java.math.RoundingMode.HALF_UP);
            return new Quote(amount, "CLOUD", "华为云函数工作流计算");
        } catch (Exception e) {
            log.warn("调用云函数失败，退回本地计算：{}", e.toString());
            return new Quote(BillingMath.money(unitPrice, minutes), "LOCAL", "云函数不可用：" + e.getClass().getSimpleName());
        }
    }
}
