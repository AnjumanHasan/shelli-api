package com.shelli.gateway.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authorization.AuthorizationDecision;
import org.springframework.security.authorization.AuthorizationManager;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.web.access.intercept.RequestAuthorizationContext;
import org.springframework.stereotype.Component;

import java.util.function.Supplier;

@Slf4j
@Component
public class AllowListAuthorizationManager implements AuthorizationManager<RequestAuthorizationContext> {

    public static final String EMAIL_CLAIM = "https://shelli.local/email";
    public static final String EMAIL_VERIFIED_CLAIM = "https://shelli.local/email_verified";

    private final ShelliProperties props;

    public AllowListAuthorizationManager(ShelliProperties props) {
        this.props = props;
    }

    @Override
    public AuthorizationDecision authorize(Supplier<? extends Authentication> authentication, RequestAuthorizationContext ctx) {
        Authentication auth = authentication.get();
        if (!(auth instanceof JwtAuthenticationToken jwtAuth)) {
            log.warn("Non-JWT authentication reached allow-list check: {}", auth);
            return new AuthorizationDecision(false);
        }

        Jwt jwt = jwtAuth.getToken();
        String sub = jwt.getSubject();
        String email = jwt.getClaimAsString(EMAIL_CLAIM);
        Boolean verified = jwt.getClaimAsBoolean(EMAIL_VERIFIED_CLAIM);

        if (email == null || !Boolean.TRUE.equals(verified)) {
            log.info("Denying request from sub={} — email missing or unverified (email={}, verified={})",
                    sub, email, verified);
            return new AuthorizationDecision(false);
        }

        boolean allowed = props.allowedEmails().contains(email.toLowerCase());
        if (!allowed) {
            log.info("Denying non-allowlisted user: email={}, sub={}", email, sub);
        }
        return new AuthorizationDecision(allowed);
    }
}
