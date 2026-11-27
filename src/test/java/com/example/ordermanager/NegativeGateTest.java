package com.example.ordermanager;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.fail;

class NegativeGateTest {
    @Test
    void blocksDeploymentWhenMavenFails() {
        fail("EP3 IE6: fallo Maven intencional");
    }
}
