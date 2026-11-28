package com.studyroom.service;

import com.studyroom.config.AppProperties;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/** 云端返回解包与通路选择的单元测试（不需要真实华为云账号）。 */
class CloudBillingClientTest {

    private static AppProperties.Cloud cloud(String endpoint, String ak, String sk,
                                             String projectId, String urn) {
        return new AppProperties.Cloud(endpoint, 3000, ak, sk, projectId, urn, null, "cn-north-4", null);
    }

    @Test
    @DisplayName("解包：直接返回 amount 字段")
    void plainAmount() throws Exception {
        assertEquals("2.00", CloudBillingClient.extractAmount("{\"amount\": \"2.00\", \"source\": \"CLOUD\"}")
                .toPlainString());
    }

    @Test
    @DisplayName("解包：事件函数外层 statusCode + body 字符串")
    void handlerEnvelope() throws Exception {
        String raw = "{\"statusCode\": 200, \"body\": \"{\\\"amount\\\": \\\"2.40\\\"}\"}";
        assertEquals("2.40", CloudBillingClient.extractAmount(raw).toPlainString());
    }

    @Test
    @DisplayName("解包：SDK v1 的 result 字符串再包一层 handler 返回")
    void sdkV1Envelope() throws Exception {
        String handler = "{\"statusCode\":200,\"body\":\"{\\\"amount\\\":\\\"2.00\\\"}\"}";
        String raw = "{\"result\":" + quote(handler) + ",\"log\":\"...\",\"status\":200}";
        assertEquals("2.00", CloudBillingClient.extractAmount(raw).toPlainString());
    }

    @Test
    @DisplayName("解包：body 是 JSON 对象而非字符串")
    void bodyAsObject() throws Exception {
        assertEquals("2.40", CloudBillingClient.extractAmount(
                "{\"statusCode\":200,\"body\":{\"amount\":\"2.40\"}}").toPlainString());
    }

    @Test
    @DisplayName("解包：v0 纯文本金额")
    void plainText() throws Exception {
        assertEquals("2.00", CloudBillingClient.extractAmount("2.00").toPlainString());
    }

    @Test
    @DisplayName("通路：未配置任何云端参数时为 LOCAL")
    void statusLocal() {
        CloudBillingClient client = new CloudBillingClient(new AppProperties(null, cloud("", "", "", "", null)));
        CloudBillingClient.Status status = client.status();
        assertEquals("LOCAL", status.mode());
        CloudBillingClient.Quote quote = client.quote(new BigDecimal("4.00"), 30);
        assertEquals("LOCAL", quote.source());
        assertEquals("2.00", quote.amount().toPlainString());
    }

    @Test
    @DisplayName("通路：只给函数名时自动拼 URN，AK/SK 齐全即切到真云端")
    void statusSdkWithFunctionName() {
        AppProperties.Cloud c = new AppProperties.Cloud(
                "", 3000, "AK_TEST", "SK_TEST", "project-123", null, "billing-func", "cn-north-4", null);
        assertEquals("urn:fss:cn-north-4:project-123:function:default:billing-func:latest", c.resolvedUrn());
        assertTrue(c.sdkEnabled());
        CloudBillingClient client = new CloudBillingClient(new AppProperties(null, c));
        assertEquals("FUNCTIONGRAPH_AKSK", client.status().mode());
        assertTrue(client.status().akConfigured());
        assertNull(client.status().httpEndpoint());
    }

    @Test
    @DisplayName("通路：只有 HTTP endpoint 时保持旧行为")
    void statusHttpEndpoint() {
        CloudBillingClient client = new CloudBillingClient(
                new AppProperties(null, cloud("http://127.0.0.1:9100/billing", "", "", "", null)));
        assertEquals("HTTP_ENDPOINT", client.status().mode());
    }

    private static String quote(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
}
