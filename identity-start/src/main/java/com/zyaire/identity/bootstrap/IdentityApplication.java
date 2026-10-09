package com.zyaire.identity.bootstrap;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = {"com.zyaire.identity"})
// scanBasePackages = {"com.zyaire.identity"} 把扫描起点提升到了共同的上级包，覆盖 bootstrap、directory 及它们的所有子包。
public class IdentityApplication {
    public static void main(String[] args) {
        SpringApplication.run(IdentityApplication.class, args);
    }
}
