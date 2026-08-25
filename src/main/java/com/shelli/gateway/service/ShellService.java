package com.shelli.gateway.service;

import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import com.shelli.gateway.dto.ShellRequest;
import com.shelli.gateway.dto.ShellResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

@Slf4j
@Service
public class ShellService {

    private final PromptBuilder promptBuilder;
    private final ResponseValidator responseValidator;
    private final LlmClient llmClient;
    private final ObjectMapper objectMapper;

    public ShellService(PromptBuilder promptBuilder, ResponseValidator responseValidator,
                        LlmClient llmClient, ObjectMapper objectMapper) {
        this.promptBuilder = promptBuilder;
        this.responseValidator = responseValidator;
        this.llmClient = llmClient;
        this.objectMapper = objectMapper;
    }

    public ShellResponse generate(ShellRequest request) {
        String systemPrompt = promptBuilder.buildSystemPrompt(request.platform(), request.shell());
        String userPrompt = promptBuilder.buildUserPrompt(request.prompt());

        log.info("Calling LLM with user prompt: {}", userPrompt);
        String llmRaw = llmClient.chat(systemPrompt, userPrompt);
        log.debug("LLM raw response: {}", llmRaw);

        ShellResponse llmResponse = parseResponse(llmRaw);
        return responseValidator.validate(llmResponse);
    }

    private ShellResponse parseResponse(String raw) {
        try {
            String json = raw.strip();
            // Strip markdown code fences if the LLM wraps the JSON
            if (json.startsWith("```")) {
                json = json.replaceAll("^```[a-zA-Z]*\\n?", "").replaceAll("```$", "").strip();
            }
            return objectMapper.readValue(json, ShellResponse.class);
        } catch (JacksonException e) {
            log.error("Failed to parse LLM response: {}", raw, e);
            return new ShellResponse("", "Failed to parse LLM response: " + e.getMessage(), false);
        }
    }
}