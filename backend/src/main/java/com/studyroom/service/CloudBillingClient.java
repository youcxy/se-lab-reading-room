package com.studyroom.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.huaweicloud.sdk.core.auth.BasicCredentials;
import com.huaweicloud.sdk.core.exception.ServiceResponseException;
import com.huaweicloud.sdk.core.http.HttpConfig;
import com.huaweicloud.sdk.core.region.Region;
import com.huaweicloud.sdk.functiongraph.v2.FunctionGraphClient;
import com.huaweicloud.sdk.functiongraph.v2.model.InvokeFunctionRequest;
import com.huaweicloud.sdk.functiongraph.v2.model.InvokeFunctionResponse;
import com.huaweicloud.sdk.functiongraph.v2.region.FunctionGraphRegion;
import com.studyroom.config.AppProperties;
import com.studyroom.core.BillingMath;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 金额的云端计算。按优先级支持两条云端通路：
 * <ol>
 *   <li><b>AK/SK 直调 FunctionGraph 同步执行 API</b>（真云端）。用官方 SDK 完成 AK/SK 签名，
 *       不需要 API 网关实例，不产生额外费用；密钥只从环境变量注入。</li>
 *   <li><b>HTTP endpoint</b>（APIG 触发器 URL 或本地模拟器），兼容原有部署方式。</li>
 * </ol>
 * 云端不可用或未配置时回退本地同一算法，并把来源记为 LOCAL，保证页面可用且数值一致。
 * 注意：启用 AK/SK 通路后失败只回退 LOCAL，<b>不会</b>悄悄退回模拟器，避免把假 CLOUD 当成真云端。
 */
@Service
public class CloudBillingClient {

    private static final Logger log = LoggerFactory.getLogger(CloudBillingClient.class);

    public record Quote(BigDecimal amount, String source, String detail) {
    }

    /** 不含任何密钥的配置状态，供 /api/cloud/status 自检使用。 */
    public record Status(String mode, String region, String functionUrn,
                         boolean akConfigured, String httpEndpoint) {
    }

    private final AppProperties props;
    private final ObjectMapper json = new ObjectMapper();
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    /** SDK 客户端线程安全且可复用，懒加载一次即可。 */
    private volatile FunctionGraphClient sdkClient;

    public CloudBillingClient(AppProperties props) {
        this.props = props;
    }

    public Status status() {
        AppProperties.Cloud c = props.cloud();
        if (c == null) {
            return new Status("LOCAL", null, null, false, null);
        }
        String endpoint = (c.endpoint() == null || c.endpoint().isBlank()) ? null : c.endpoint();
        String mode = c.sdkEnabled() ? "FUNCTIONGRAPH_AKSK"
                : endpoint != null ? "HTTP_ENDPOINT" : "LOCAL";
        return new Status(mode, c.resolvedRegion(), c.resolvedUrn(),
                c.ak() != null && !c.ak().isBlank(), endpoint);
    }

    public Quote quote(BigDecimal unitPrice, int minutes) {
        BigDecimal local = BillingMath.money(unitPrice, minutes);
        AppProperties.Cloud c = props.cloud();
        if (c == null) {
            return new Quote(local, "LOCAL", "未配置云端参数，使用本地计算");
        }
        if (c.sdkEnabled()) {
            return viaFunctionGraph(c, unitPrice, minutes, local);
        }
        return viaHttpEndpoint(c, unitPrice, minutes, local);
    }

    /** 通路 1：AK/SK 签名同步执行华为云函数工作流，页面拿到的是 FunctionGraph 的真实返回值。 */
    private Quote viaFunctionGraph(AppProperties.Cloud c, BigDecimal unitPrice,
                                   int minutes, BigDecimal local) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("unitPrice", unitPrice.toPlainString());
            body.put("minutes", minutes);

            InvokeFunctionRequest request = new InvokeFunctionRequest()
                    .withFunctionUrn(c.resolvedUrn())
                    .withXCFFRequestVersion("v1")
                    .withBody(body);

            InvokeFunctionResponse response = sdkClient(c).invokeFunction(request);
            Integer functionStatus = response.getStatus();
            if (functionStatus != null && (functionStatus < 200 || functionStatus >= 300)) {
                return new Quote(local, "LOCAL", "云函数执行状态 " + functionStatus + "，已回退本地计算");
            }
            BigDecimal amount = extractAmount(response.getResult());
            String consistency = local.compareTo(amount) == 0
                    ? "与本地核算一致" : "与本地核算不一致（本地 " + local + "），请检查云函数版本";
            return new Quote(amount, "CLOUD",
                    "华为云 FunctionGraph 同步执行 · " + c.resolvedUrn() + " · " + consistency);
        } catch (Exception e) {
            log.warn("FunctionGraph 直调失败，回退本地计算：{}", e.toString());
            return new Quote(local, "LOCAL", "FunctionGraph 调用失败，已回退本地：" + describe(e));
        }
    }

    private FunctionGraphClient sdkClient(AppProperties.Cloud c) {
        FunctionGraphClient result = sdkClient;
        if (result == null) {
            synchronized (this) {
                result = sdkClient;
                if (result == null) {
                    BasicCredentials credentials = new BasicCredentials()
                            .withAk(c.ak())
                            .withSk(c.sk())
                            .withProjectId(c.projectId());
                    int seconds = Math.max(5, (c.timeoutMs() + 999) / 1000);
                    HttpConfig config = HttpConfig.getDefaultHttpConfig().withTimeout(seconds);
                    String override = c.sdkEndpoint();
                    boolean localOverride = override != null && !override.isBlank();
                    if (localOverride) {
                        config = config.withIgnoreSSLVerification(true);
                    }
                    Region region = localOverride
                            ? new Region(c.resolvedRegion(), override)
                            : FunctionGraphRegion.valueOf(c.resolvedRegion());
                    result = FunctionGraphClient.newBuilder()
                            .withCredential(credentials)
                            .withRegion(region)
                            .withHttpConfig(config)
                            .build();
                    sdkClient = result;
                    log.info("FunctionGraph SDK 就绪：region={}, urn={}, endpointOverride={}",
                            c.resolvedRegion(), c.resolvedUrn(), localOverride);
                }
            }
        }
        return result;
    }

    /** 通路 2：HTTP 触发器 / 本地模拟器（旧部署方式，保留兼容）。 */
    private Quote viaHttpEndpoint(AppProperties.Cloud c, BigDecimal unitPrice,
                                  int minutes, BigDecimal local) {
        String endpoint = c.endpoint();
        if (endpoint == null || endpoint.isBlank()) {
            return new Quote(local, "LOCAL", "未配置 FG_ENDPOINT，使用本地计算");
        }
        try {
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("unitPrice", unitPrice.toPlainString());
            payload.put("minutes", minutes);
            HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
                    .timeout(Duration.ofMillis(c.timeoutMs()))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(payload)))
                    .build();
            // 云函数返回的 Content-Type 通常不带 charset，按 UTF-8 解码避免中文说明变乱码
            HttpResponse<byte[]> response = http.send(request, HttpResponse.BodyHandlers.ofByteArray());
            if (response.statusCode() / 100 != 2) {
                return new Quote(local, "LOCAL", "云函数返回 HTTP " + response.statusCode());
            }
            String body = new String(response.body(), StandardCharsets.UTF_8);
            BigDecimal amount = extractAmount(body);
            return new Quote(amount, "CLOUD", "HTTP 端点计算 · " + endpoint);
        } catch (Exception e) {
            log.warn("调用 HTTP 云函数端点失败，退回本地计算：{}", e.toString());
            return new Quote(local, "LOCAL", "云函数不可用：" + e.getClass().getSimpleName());
        }
    }

    /**
     * 递归解包云端返回，兼容三种形态：
     * 纯金额文本 / {"amount":"2.00"} /
     * {"statusCode":200,"body":"{\"amount\":\"2.00\"}"} /
     * {"result":"{\"statusCode\":200,...}","status":200,...}（SDK v1 包装）。
     */
    static BigDecimal extractAmount(String raw) throws Exception {
        if (raw == null || raw.isBlank()) {
            throw new IllegalStateException("云函数返回为空");
        }
        String text = raw.trim();
        if (!text.startsWith("{")) {
            return new BigDecimal(text).setScale(2, RoundingMode.HALF_UP);
        }
        ObjectMapper mapper = new ObjectMapper();
        BigDecimal found = findAmount(mapper.readTree(text), mapper, 0);
        if (found == null) {
            throw new IllegalStateException("云端返回中找不到 amount 字段");
        }
        return found;
    }

    private static BigDecimal findAmount(JsonNode node, ObjectMapper mapper, int depth) {
        if (node == null || depth > 5) {
            return null;
        }
        if (node.hasNonNull("amount")) {
            return new BigDecimal(node.get("amount").asText()).setScale(2, RoundingMode.HALF_UP);
        }
        for (String key : new String[]{"result", "body"}) {
            JsonNode nested = node.get(key);
            if (nested == null) {
                continue;
            }
            if (nested.isObject()) {
                BigDecimal value = findAmount(nested, mapper, depth + 1);
                if (value != null) {
                    return value;
                }
            } else if (nested.isTextual()) {
                String s = nested.asText().trim();
                if (s.isEmpty()) {
                    continue;
                }
                try {
                    BigDecimal value = findAmount(mapper.readTree(s), mapper, depth + 1);
                    if (value != null) {
                        return value;
                    }
                } catch (Exception ignored) {
                    try {
                        return new BigDecimal(s).setScale(2, RoundingMode.HALF_UP);
                    } catch (NumberFormatException ignoredToo) {
                        // 该层不是金额，继续找下一个字段
                    }
                }
            }
        }
        return null;
    }

    /** 精简错误信息，避免把完整异常（可能含 URL / 请求头）暴露到页面。 */
    private static String describe(Exception e) {
        if (e instanceof ServiceResponseException sre) {
            return "HTTP " + sre.getHttpStatusCode() + " " + sre.getErrorCode() + " " + sre.getErrorMsg();
        }
        String msg = e.getMessage();
        if (msg == null || msg.isBlank()) {
            return e.getClass().getSimpleName();
        }
        return e.getClass().getSimpleName() + ": " + msg.substring(0, Math.min(msg.length(), 160));
    }
}
