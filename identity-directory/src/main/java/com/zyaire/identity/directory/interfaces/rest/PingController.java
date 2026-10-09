package com.zyaire.identity.directory.interfaces.rest;

import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@Profile("local")
@RestController
public class PingController {
    public record PingResponse(String message) {}

    @GetMapping("/api/dev/ping")
    public PingResponse ping() {
        return new PingResponse("identity is running");
    }

//    @GetMapping("/api/dev/ping/{name}")
//    // 临时增加 GET /api/dev/ping/{name}，参数显式 @PathVariable("name")，返回 Map.of("message", "hello " + name)
//    public Map<String, String> pingWithName(@PathVariable("name") String name) {
//        return Map.of("message1", "hello " + name);
//    }

//    @GetMapping("/api/dev/repeat")
//    public Integer repeat(@RequestParam(name = "count", defaultValue = "1") int count) {
//        return count;
//    }

//    @GetMapping("/api/dev/fail")
//    public void fail() {
//        throw new IllegalStateException("tutorial failure");
//    }
}