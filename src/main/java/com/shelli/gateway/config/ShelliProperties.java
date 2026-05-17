package com.shelli.gateway.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.Set;
import java.util.stream.Collectors;

@ConfigurationProperties("shelli")
public record ShelliProperties(Set<String> allowedEmails) {

    public ShelliProperties {
        allowedEmails = allowedEmails == null
                ? Set.of()
                : allowedEmails.stream()
                        .map(String::trim)
                        .filter(s -> !s.isEmpty())
                        .map(String::toLowerCase)
                        .collect(Collectors.toUnmodifiableSet());
    }
}
