package com.shelli.gateway.dto.groq;

import java.util.List;

public record GroqChatResponse(List<Choice> choices) {

    public record Choice(Message message) {}

    public record Message(String role, String content) {}

    public String content() {
        return choices.getFirst().message().content();
    }
}