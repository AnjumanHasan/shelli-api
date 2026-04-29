package com.shelli.gateway.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * This class is responsible for building the prompts that will be sent to the llm. It reads the system prompt from a file and provides methods to build both system and user prompts.
 * SystemPrompt here is nothing but a static prompt that has been saved in resources which tells the llm client what it is supposed to do
 * It is loaded everytime and used as a base prompt for setting context for the llm client.
 * {@code buildUserPrompt} is a method that dynamically builds the user prompt based on the natural language request received from the user.
 **/
@Component
public class PromptBuilder {

    private final String systemPrompt;
    public PromptBuilder(@Value("classpath:static/SystemPrompt.md") Resource promptResource) throws IOException {
        this.systemPrompt = promptResource.getContentAsString(StandardCharsets.UTF_8);
    }

    public String buildSystemPrompt() {
        return systemPrompt;
    }

    public String buildUserPrompt(String naturalLanguageRequest) {
        return "Convert this to a shell command: " + naturalLanguageRequest;
    }
}