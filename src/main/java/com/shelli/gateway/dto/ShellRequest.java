package com.shelli.gateway.dto;

/**
 * ShellRequest represents an incoming request to translate natural language into a shell command.
 * platform and shell are optional context fields the client sends so the LLM can target the
 * caller's environment (e.g. macOS+zsh vs Linux+bash). They are null when unknown.
 */
public record ShellRequest(String prompt, String platform, String shell) {
}
