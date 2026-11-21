package com.studyroom.core;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** 计费规则的单元测试：金额 = 单价 × 分钟 ÷ 60，分钟向上取整，金额四舍五入到分。 */
class BillingMathTest {

    private static final LocalDateTime T0 = LocalDateTime.of(2026, 11, 20, 9, 0, 0);

    @Test
    @DisplayName("需求算例：4.00 元/小时，使用 30 分钟为 2.00 元")
    void thirtyMinutesIsTwoYuan() {
        int minutes = BillingMath.chargeableMinutes(T0, T0.plusMinutes(30));
        assertEquals(30, minutes);
        assertEquals(new BigDecimal("2.00"), BillingMath.money(new BigDecimal("4.00"), minutes));
    }

    @Test
    @DisplayName("1 小时为 4.00 元；45 分钟为 3.00 元")
    void hourAndThreeQuarters() {
        assertEquals(new BigDecimal("4.00"), BillingMath.money(new BigDecimal("4.00"),
                BillingMath.chargeableMinutes(T0, T0.plusHours(1))));
        assertEquals(new BigDecimal("3.00"), BillingMath.money(new BigDecimal("4.00"),
                BillingMath.chargeableMinutes(T0, T0.plusMinutes(45))));
    }

    @Test
    @DisplayName("不足 1 分钟按 1 分钟计，金额四舍五入到分")
    void lessThanOneMinuteRoundsUp() {
        int minutes = BillingMath.chargeableMinutes(T0, T0.plusSeconds(1));
        assertEquals(1, minutes);
        assertEquals(new BigDecimal("0.07"), BillingMath.money(new BigDecimal("4.00"), minutes));
    }

    @Test
    @DisplayName("31 分钟 4.00 元/小时 → 2.07 元（2.0666… 四舍五入）")
    void roundsHalfUp() {
        assertEquals(new BigDecimal("2.07"), BillingMath.money(new BigDecimal("4.00"), 31));
    }

    @Test
    @DisplayName("涨价后按新单价计算：4.80 元/小时 30 分钟为 2.40 元；已开始的单仍按快照 4.00 算 2.00 元")
    void surgePriceOnlyAppliesToNewSessions() {
        assertEquals(new BigDecimal("2.40"), BillingMath.money(new BigDecimal("4.80"), 30));
        assertEquals(new BigDecimal("2.00"), BillingMath.money(new BigDecimal("4.00"), 30));
    }

    @Test
    @DisplayName("包天卡 30 元与月卡 0 元都由分支决定，不经过分钟算法")
    void cardBranches() {
        assertEquals(new BigDecimal("0.00"), BillingMath.money(BigDecimal.ZERO, 60));
        assertEquals(new BigDecimal("30.00"), BillingMath.round2(new BigDecimal("30.004")));
    }
}
