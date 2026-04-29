# Shelli Gateway - Progress Tracker

## Project Overview
CLI tool ("shelli") that converts natural language into shell commands using an LLM, with a Spring Boot proxy server securing the API key and validating command safety.

## Architecture
1. **CLI Layer** (Bash script) — user-facing tool
2. **Proxy Server** (Spring Boot API) — middleware holding LLM key, prompt construction, safety validation
3. **LLM Provider** — free tier to start (Groq/Gemini), swappable via interface

## Completed Steps

### Step 1: Project Setup
- Spring Boot 4.0.5, Java 21, Gradle
- Package: `com.shelli.gateway`
- Starters: restclient, webmvc, spring-cloud-config, spring-shell, lombok

### Step 2: REST Controller + DTOs
- `dto/ShellRequest.java` — record with `prompt` field
- `dto/ShellResponse.java` — record with `command`, `explanation`, `isSafe`
- `controller/ShellController.java` — `POST /api/shell/generate` (returns hardcoded dummy response for now)
- Compiles and ready to test

### Step 3: Prompt Builder
- `service/PromptBuilder.java` — Spring `@Component` that loads the system prompt from a static resource file
- System prompt stored in `resources/static/SystemPrompt.md` — instructs the LLM to return structured JSON with `command`, `explanation`, `isSafe` fields
- Loaded at startup via `@Value("classpath:static/SystemPrompt.md")` and Spring's `Resource` abstraction
- `buildSystemPrompt()` — returns the static system prompt (same for every request)
- `buildUserPrompt(String)` — wraps user's natural language input into the user message sent to the LLM

### Step 4: Response Validator (Command Safety)
- `service/ResponseValidator.java` — server-side safety net that validates LLM responses before returning to the user
- Maintains a blocklist of 16 regex patterns for dangerous commands: `rm`, `rmdir`, `del`, `mkfs`, `dd`, `shred`, `fdisk`, `format`, `kill -9`, `shutdown`, `reboot`, `chmod 777`, fork bombs, `/dev/` writes, `rm -rf`
- `validate(ShellResponse)` — checks the command against all patterns; if matched, replaces with empty command, `isSafe: false`, and a blocked reason
- This is the dual-layer safety design: LLM prompt says "don't generate dangerous commands", but the validator enforces it server-side regardless

### Step 5: Shell Service + Controller Wiring
- `service/ShellService.java` — orchestrator `@Service` that ties the pipeline together
- Constructor-injected with `PromptBuilder` and `ResponseValidator` (Spring IoC)
- `generate(ShellRequest)` flow: build prompts → [LLM call - TODO] → validate response → return
- `controller/ShellController.java` — cleaned up to inject `ShellService` and delegate entirely to `shellService.generate()`
- No more hardcoded response in the controller; all logic lives in the service layer

### Step 6: LLM Client (Groq)
- `service/LlmClient.java` — provider interface with single `chat(systemPrompt, userPrompt)` method; allows swapping providers
- `service/GroqLlmClient.java` — Groq implementation using Spring `RestClient` against `https://api.groq.com/openai/v1/chat/completions`
- `dto/groq/GroqChatRequest.java` — request DTO (model, messages, temperature); factory method `of()` builds system+user message pair
- `dto/groq/GroqChatResponse.java` — response DTO mapping Groq's `choices[0].message.content`
- `ShellService.java` — now injects `LlmClient`, calls `chat()`, parses JSON response into `ShellResponse` (handles markdown code fences)
- Config: `groq.api.key` (from `GROQ_API_KEY` env var), `groq.api.model` (default: `llama-3.3-70b-versatile`)
  - OpenAI-compatible API format — can swap to Gemini/Cerebras/etc by changing base URL and key
- Request format sent to Groq:
  ```json
  {
    "model": "llama-3.3-70b-versatile",
    "messages": [...],
    "temperature": 0.2,
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "shell_response",
        "strict": true,
        "schema": {
          "type": "object",
          "properties": {
            "command": { "type": "string" },
            "explanation": { "type": "string" },
            "isSafe": { "type": "boolean" }
          },
          "required": ["command", "explanation", "isSafe"],
          "additionalProperties": false
        }
      }
    }
  }
  ```



## Next Steps
- [ ] Test end-to-end with Groq API key
- [ ] Add DTOs validation (`@NotBlank`, etc.)
- [ ] Create Bash CLI script (`shelli.sh`)
- [ ] Add configuration via `application.properties` (API keys, provider selection, execution mode)
