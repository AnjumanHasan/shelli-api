package com.shelli.gateway.controller;

import com.shelli.gateway.dto.ShellRequest;
import com.shelli.gateway.dto.ShellResponse;
import com.shelli.gateway.service.ShellService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import lombok.extern.slf4j.Slf4j;

@Slf4j
@RestController
@RequestMapping("/api/shell")
public class ShellController {

    private final ShellService shellService;

    public ShellController(ShellService shellService) {
        this.shellService = shellService;
    }

    @PostMapping("/generate")
    public ResponseEntity<ShellResponse> generateCommand(@RequestBody ShellRequest request) {
        log.info("Received request: {}", request.prompt());
        ShellResponse response = shellService.generate(request);
        log.info("Returning response: command='{}', explanation='{}', isSafe={}", response.command(), response.explanation(), response.isSafe());
        return ResponseEntity.ok(response);
    }
}
