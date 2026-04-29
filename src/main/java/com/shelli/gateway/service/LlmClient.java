package com.shelli.gateway.service;

public interface LlmClient {

    String chat(String systemPrompt, String userPrompt);
}
