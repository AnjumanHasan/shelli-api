package com.shelli.gateway.service;

import com.shelli.gateway.constants.Constants;
import com.shelli.gateway.dto.ShellResponse;
import org.springframework.stereotype.Component;
import lombok.extern.slf4j.Slf4j;

import java.util.List;
import java.util.regex.Pattern;

@Slf4j
@Component
public class ResponseValidator {

    private static final List<Pattern> BLOCKED_PATTERNS = Constants.BLOCKED_PATTERNS;

    public ShellResponse validate(ShellResponse response) {
        if (response.command() == null || response.command().isBlank()) {
            return response;
        }

        String command = response.command().toLowerCase();
        log.info("Validating command: '{}'", command);
        for (Pattern pattern : BLOCKED_PATTERNS) {
            if (pattern.matcher(command).find()) {
                log.info("Blocked command: '{}' matched pattern '{}'", command, pattern.pattern());
                return new ShellResponse(
                        command, response.explanation(),
                        false
                );
            }
        }

        return response;
    }
}