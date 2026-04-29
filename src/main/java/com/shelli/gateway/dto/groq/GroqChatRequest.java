package com.shelli.gateway.dto.groq;

import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;
import java.util.Map;

public record GroqChatRequest(
        String model,
        List<Message> messages,
        double temperature,
        @JsonProperty("response_format") ResponseFormat responseFormat
) {

    public record Message(String role, String content) {}

    public record ResponseFormat(String type, @JsonProperty("json_schema") JsonSchema jsonSchema) {}

    public record JsonSchema(String name, boolean strict, Map<String, Object> schema) {}

    private static final ResponseFormat SHELL_RESPONSE_FORMAT = new ResponseFormat(
            "json_schema",
            new JsonSchema(
                    "shell_response",
                    true,
                    Map.of(
                            "type", "object",
                            "properties", Map.of(
                                    "command", Map.of("type", "string"),
                                    "explanation", Map.of("type", "string"),
                                    "isSafe", Map.of("type", "boolean")
                            ),
                            "required", List.of("command", "explanation", "isSafe"),
                            "additionalProperties", false
                    )
            )
    );

    public static GroqChatRequest of(String model, String systemPrompt, String userPrompt) {
        return new GroqChatRequest(
                model,
                List.of(
                        new Message("system", systemPrompt),
                        new Message("user", userPrompt)
                ),
                0.2,
                SHELL_RESPONSE_FORMAT
        );
    }
}