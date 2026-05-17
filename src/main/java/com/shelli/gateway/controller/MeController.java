package com.shelli.gateway.controller;

import com.shelli.gateway.config.AllowListAuthorizationManager;
import com.shelli.gateway.config.ShelliProperties;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/me")
public class MeController {

    private final ShelliProperties props;

    public MeController(ShelliProperties props) {
        this.props = props;
    }

    @GetMapping
    public Map<String, Object> me(@AuthenticationPrincipal Jwt jwt) {
        String email = jwt.getClaimAsString(AllowListAuthorizationManager.EMAIL_CLAIM);
        Boolean verified = jwt.getClaimAsBoolean(AllowListAuthorizationManager.EMAIL_VERIFIED_CLAIM);
        boolean allowed = email != null
                && Boolean.TRUE.equals(verified)
                && props.allowedEmails().contains(email.toLowerCase());

        return Map.of(
                "sub", jwt.getSubject(),
                "email", email == null ? "" : email,
                "email_verified", Boolean.TRUE.equals(verified),
                "allowed", allowed
        );
    }
}
