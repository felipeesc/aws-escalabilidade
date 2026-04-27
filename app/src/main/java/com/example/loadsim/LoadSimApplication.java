package com.example.loadsim;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cache.annotation.EnableCaching;

@SpringBootApplication
@EnableCaching
public class LoadSimApplication {
    public static void main(String[] args) {
        SpringApplication.run(LoadSimApplication.class, args);
    }
}
