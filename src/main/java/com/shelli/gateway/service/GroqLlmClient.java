package com.shelli.gateway.service;

import com.shelli.gateway.dto.groq.GroqChatRequest;
import com.shelli.gateway.dto.groq.GroqChatResponse;
import org.springframework.beans.factory.annotation.Value;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Slf4j
@Component
public class GroqLlmClient implements LlmClient {

    private final RestClient restClient;
    private final String model;

    public GroqLlmClient(
            @Value("${groq.api.key}") String apiKey,
            @Value("${groq.api.model:openai/gpt-oss-20b}") String model) {
        this.model = model;
        this.restClient = RestClient.builder()
                .baseUrl("https://api.groq.com/openai/v1")
                .defaultHeader("Authorization", "Bearer " + apiKey)
                .defaultHeader("Content-Type", "application/json")
                .build();
    }

    @Override
    public String chat(String systemPrompt, String userPrompt) {
        GroqChatRequest request = GroqChatRequest.of(model, systemPrompt, userPrompt);

        GroqChatResponse response = restClient.post()
                .uri("/chat/completions")
                .body(request)
                .retrieve()
                .body(GroqChatResponse.class);
        log.info("Received response from Groq: {}", response);
        return response.content();
    }
}