package com.example.ordermanager.controller;

import com.example.ordermanager.dto.CreateOrderRequest;
import com.example.ordermanager.exception.InvalidOrderStateException;
import com.example.ordermanager.exception.OrderNotFoundException;
import com.example.ordermanager.model.Order;
import com.example.ordermanager.model.OrderItem;
import com.example.ordermanager.model.OrderStatus;
import com.example.ordermanager.service.OrderService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private OrderService orderService;

    @Test
    void shouldPreserveOrderJsonOnCreation() throws Exception {
        when(orderService.createOrder(any())).thenAnswer(invocation -> {
            CreateOrderRequest request = invocation.getArgument(0);
            var item = request.getItems().get(0);
            Order order = new Order(request.getCustomerName());
            order.setId(7L);
            order.setCreatedAt(LocalDateTime.of(2026, 11, 26, 10, 15, 30));
            order.addItem(new OrderItem(item.getProductName(), item.getQuantity(), item.getUnitPrice()));
            return order;
        });

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customerName":"Cliente","items":[
                                  {"productName":"Monitor","quantity":2,"unitPrice":19.95}
                                ]}
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(7))
                .andExpect(jsonPath("$.customerName").value("Cliente"))
                .andExpect(jsonPath("$.status").value("PENDING"))
                .andExpect(jsonPath("$.createdAt").value("2026-11-26T10:15:30"))
                .andExpect(jsonPath("$.totalAmount").value(39.9))
                .andExpect(jsonPath("$.items[0].productName").value("Monitor"))
                .andExpect(jsonPath("$.items[0].quantity").value(2))
                .andExpect(jsonPath("$.items[0].unitPrice").value(19.95))
                .andExpect(jsonPath("$.items[0].subtotal").value(39.9));
    }

    @Test
    void shouldReturnConflictWhenShippingPendingOrder() throws Exception {
        when(orderService.shipOrder(1L)).thenThrow(new InvalidOrderStateException("PENDING", "SHIPPED"));

        mockMvc.perform(put("/api/orders/1/ship"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value(409));
    }

    @Test
    void shouldRejectOrderTotalOverflowReportedByService() throws Exception {
        when(orderService.createOrder(any())).thenThrow(new IllegalArgumentException("Monto máximo excedido"));

        mockMvc.perform(post("/api/orders")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customerName\":\"Cliente de prueba\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Monto máximo excedido"));
    }

    @Test
    void shouldGetAllOrders() throws Exception {
        Order order = new Order();
        order.setId(1L);
        order.setCustomerName("Juan Perez");
        order.setStatus(OrderStatus.PENDING);

        when(orderService.getAllOrders()).thenReturn(List.of(order));

        mockMvc.perform(get("/api/orders"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].customerName").value("Juan Perez"));
    }

    @Test
    void shouldLogNotFoundWithoutOrderId(CapturedOutput output) throws Exception {
        long orderId = 984657321L;
        when(orderService.getOrderById(orderId)).thenThrow(new OrderNotFoundException(orderId));

        mockMvc.perform(get("/api/orders/{id}", orderId))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.message").value(new OrderNotFoundException(orderId).getMessage()));

        assertThat(output.getAll()).containsPattern("WARN .*event=http_error status=404 category=order_not_found")
                .doesNotContain(Long.toString(orderId));
    }

    @Test
    void shouldLogInternalErrorWithoutExceptionMessage(CapturedOutput output) throws Exception {
        when(orderService.getAllOrders()).thenThrow(new IllegalStateException("private-test-value"));

        mockMvc.perform(get("/api/orders"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.message").value("Error interno del servidor. Contacte al administrador."));

        assertThat(output.getAll()).containsPattern("ERROR .*event=http_error status=500 category=internal_error")
                .doesNotContain("private-test-value");
    }

    @Test
    void shouldRejectMalformedJsonWithoutLoggingInput(CapturedOutput output) throws Exception {
        mockMvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"customerName\":\"private-malformed-value\""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Solicitud inválida"));

        assertThat(output.getAll()).doesNotContain("private-malformed-value", "category=internal_error");
        verifyNoInteractions(orderService);
    }

    @Test
    void shouldRejectInvalidOrderStatus() throws Exception {
        mockMvc.perform(get("/api/orders/status/{status}", "NO_SUCH_STATUS"))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(orderService);
    }

    @Test
    void shouldPreserveMethodNotAllowedAndAllowHeader() throws Exception {
        mockMvc.perform(patch("/api/orders"))
                .andExpect(status().isMethodNotAllowed())
                .andExpect(header().exists("Allow"));
        verifyNoInteractions(orderService);
    }

    @Test
    void shouldRejectPriceExceedingPostgresPrecision() throws Exception {
        mockMvc.perform(post("/api/orders/1/items").contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"productName":"Test","quantity":1,"unitPrice":100000000.00}
                                """))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.fields.unitPrice").exists());
        verifyNoInteractions(orderService);
    }

    @Test
    void shouldRejectNullOrderItem() throws Exception {
        mockMvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"customerName":"Test","items":[null]}
                                """))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(orderService);
    }
}
