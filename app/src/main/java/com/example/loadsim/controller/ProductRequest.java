package com.example.loadsim.controller;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public record ProductRequest(
        @NotBlank(message = "nome é obrigatório") String name,
        @NotNull @DecimalMin(value = "0.01", message = "preço deve ser maior que zero") BigDecimal price,
        @Min(value = 0, message = "estoque não pode ser negativo") Integer stock
) {}
