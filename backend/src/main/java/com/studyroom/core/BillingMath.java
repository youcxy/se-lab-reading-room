package com.studyroom.core;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.LocalDateTime;

/**
 * 计费纯函数。与华为云函数工作流中的实现保持同一套规则：
 * 金额 = 单价 × 分钟 ÷ 60，分钟按向上取整，金额四舍五入到分。
 */
public final class BillingMath {

    private BillingMath() {
    }

    /** 计费分钟数：不足 1 分钟按 1 分钟计，向上取整。 */
    public static int chargeableMinutes(LocalDateTime start, LocalDateTime end) {
        if (start == null || end == null) {
            return 0;
        }
        long seconds = Duration.between(start, end).getSeconds();
        if (seconds <= 0) {
            return 0;
        }
        return (int) ((seconds + 59) / 60);
    }

    /** 金额 = 单价 × 分钟 ÷ 60，保留两位小数，四舍五入。 */
    public static BigDecimal money(BigDecimal unitPrice, int minutes) {
        if (unitPrice == null || minutes <= 0) {
            return BigDecimal.ZERO.setScale(2, RoundingMode.HALF_UP);
        }
        return unitPrice.multiply(BigDecimal.valueOf(minutes))
                .divide(BigDecimal.valueOf(60), 2, RoundingMode.HALF_UP);
    }

    public static BigDecimal round2(BigDecimal value) {
        return value == null ? null : value.setScale(2, RoundingMode.HALF_UP);
    }

    public static BigDecimal round4(BigDecimal value) {
        return value == null ? null : value.setScale(4, RoundingMode.HALF_UP);
    }
}
