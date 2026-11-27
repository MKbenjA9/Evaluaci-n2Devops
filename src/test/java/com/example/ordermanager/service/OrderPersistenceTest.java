package com.example.ordermanager.service;

import com.example.ordermanager.dto.AddItemRequest;
import com.example.ordermanager.dto.CreateOrderRequest;
import com.example.ordermanager.model.Order;
import com.example.ordermanager.model.OrderStatus;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.context.annotation.Import;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
@Import(OrderService.class)
class OrderPersistenceTest {

    @Autowired
    private OrderService orders;

    @Autowired
    private EntityManager entityManager;

    @Test
    void persistsItemsAndStatusAndFiltersOrdersAfterReload() {
        AddItemRequest item = new AddItemRequest();
        item.setProductName("  Monitor  ");
        item.setQuantity(2);
        item.setUnitPrice(new BigDecimal("19.95"));
        CreateOrderRequest request = new CreateOrderRequest();
        request.setCustomerName("  Cliente de prueba  ");
        request.setItems(List.of(item));

        Long id = orders.createOrder(request).getId();
        orders.confirmOrder(id);
        entityManager.flush();
        entityManager.clear();

        assertThat(orders.getOrdersByStatus(OrderStatus.PENDING)).isEmpty();
        assertThat(orders.getOrdersByStatus(OrderStatus.CONFIRMED)).singleElement().satisfies(order -> {
            assertThat(order.getId()).isEqualTo(id);
            assertThat(order.getCustomerName()).isEqualTo("Cliente de prueba");
            assertThat(order.getCreatedAt()).isNotNull();
            assertThat(order.getTotalAmount()).isEqualByComparingTo("39.90");
            assertThat(order.getItems()).singleElement().satisfies(savedItem -> {
                assertThat(savedItem.getProductName()).isEqualTo("Monitor");
                assertThat(savedItem.getQuantity()).isEqualTo(2);
                assertThat(savedItem.getUnitPrice()).isEqualByComparingTo("19.95");
            });
        });
    }

    @Test
    void setsDefaultsWhenPersistingAnOrderWithOnlyItsCustomer() {
        Order order = new Order();
        order.setCustomerName("Cliente de prueba");
        entityManager.persist(order);
        entityManager.flush();
        entityManager.clear();

        Order reloaded = orders.getOrderById(order.getId());
        assertThat(reloaded.getStatus()).isEqualTo(OrderStatus.PENDING);
        assertThat(reloaded.getCreatedAt()).isNotNull();
        assertThat(reloaded.getTotalAmount()).isEqualByComparingTo("0.00");
        assertThat(reloaded.getItems()).isEmpty();
    }
}
