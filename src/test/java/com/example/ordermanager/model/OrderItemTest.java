package com.example.ordermanager.model;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatIllegalArgumentException;

class OrderItemTest {

    @Test
    void rejectsMissingProductName() {
        assertThatIllegalArgumentException().isThrownBy(() -> new OrderItem(null, 1, BigDecimal.ONE));
        assertThatIllegalArgumentException().isThrownBy(() -> new OrderItem(" ", 1, BigDecimal.ONE));
    }

    @Test
    void rejectsNonPositiveQuantity() {
        assertThatIllegalArgumentException().isThrownBy(() -> new OrderItem("Monitor", 0, BigDecimal.ONE));
    }

    @Test
    void rejectsMissingOrNegativePriceAndAcceptsFreeItems() {
        assertThatIllegalArgumentException().isThrownBy(() -> new OrderItem("Monitor", 1, null));
        assertThatIllegalArgumentException().isThrownBy(() -> new OrderItem("Monitor", 1, new BigDecimal("-0.01")));
        assertThat(new OrderItem("Monitor", 2, BigDecimal.ZERO).getSubtotal()).isEqualByComparingTo("0");
    }
}
