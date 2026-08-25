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


### Step 7: Auth (Auth0 JWT + email allow-list)
- Gateway is an OAuth2 resource server — `spring-boot-starter-oauth2-resource-server`, issuer and audience in `application.properties`
- `config/SecurityConfig.java` — stateless filter chain, CSRF off, `/actuator/health` public, `/api/me` merely authenticated, everything else goes through the allow-list
- `config/AllowListAuthorizationManager.java` — custom `AuthorizationManager`; requires a verified email claim (`https://shelli.local/email` + `_email_verified`, set by an Auth0 action) and membership in the allow-list
- `config/ShelliProperties.java` — `@ConfigurationProperties("shelli")` record; normalizes `shelli.allowed-emails` to a lowercase immutable set
- `controller/MeController.java` — `GET /api/me`, returns sub/email/verified/allowed so a client can check its own standing
- `scripts/get-token.sh` — standalone device-flow helper for curl testing; `scripts/decode-token.sh` — prints a JWT payload
- Secrets stay in `.env` (`GROQ_API_KEY`, `SHELLI_ALLOWED_EMAILS`); `bootRun` loads that file into the process env

### Step 8: Target-environment awareness
- `ShellRequest` carries optional `platform` and `shell` alongside `prompt`, so the LLM targets the caller's actual environment
- `PromptBuilder.buildSystemPrompt(platform, shell)` substitutes `{platform}` / `{shell}` in `SystemPrompt.md`; blank values become `unknown`
- `SystemPrompt.md` gained a **Target Environment** section that spells out BSD vs GNU differences (no `-daystart`/`-printf`, `sed -i ''` on macOS) — this was the fix for the model handing back GNU-only flags on a Mac
- Temperature dropped from 0.2 to 0.0 for repeatable output; model settled on `openai/gpt-oss-20b`

### Step 9: Bash CLI (`scripts/shelli.sh`)
- The user-facing tool: `shelli find all files larger than 100MB under my home directory`
- Joins its arguments into one prompt, adds `platform` (`uname -s` + `sw_vers`) and `shell` (basename of `$SHELL`), POSTs to `/api/shell/generate`
- **Auth**: token cached at `~/.shelli/token` (mode 600, dir 700). Decodes the JWT's `exp` and re-runs the Auth0 device flow automatically when the token is missing or within 60s of expiry — so day-to-day use never needs a manual login. `shelli login` / `logout` / `whoami` are explicit escape hatches
- **Execution modes**: `interactive` (default — prints command + explanation, asks `[y/N]`, reads from `/dev/tty`) and `display` (`-d`, print only). `-y` skips the prompt but refuses anything the gateway flagged unsafe. Non-tty stdin degrades to display mode rather than executing unattended
- **Client-side safety net**: `BLOCKED_PATTERNS` mirrors `Constants.BLOCKED_PATTERNS` as EREs and is checked *after* the gateway's answer arrives. A match aborts with exit 3 regardless of what `isSafe` said — verified against a stub returning `{"command":"dd if=/dev/zero ...","isSafe":true}`. This is the second half of the dual-layer design: the proxy can be stale or bypassed, the command about to run is what matters
- **Config**: `~/.shelli/config` (shell syntax) for `SHELLI_API_URL` and `SHELLI_MODE`; precedence is environment > config file > default. `shelli config` prints what resolved
- **Errors**: 401 → "run shelli login", 403 → "not on the allow-list", connection refused → "is the gateway running?"
- Exit codes: 0 ok / 1 error / 3 refused on safety grounds
- Compatible with stock macOS bash 3.2 (no `mapfile`, no `${var,,}`); requires `curl` and `jq`
- Verified against a stub gateway: safe, unsafe, locally-blocked, empty-command, 401/403/500, config precedence, and both `[y/N]` answers driven through a real pty

### Step 10: End-to-end verification (real gateway, real Groq, real Auth0)
- Device-flow login succeeded; token cached. `shelli whoami` → `allowed: true` for the allow-listed Google identity
- Installed on `PATH` as `~/.local/bin/shelli` (already on `PATH` via `.zshrc`). `/usr/local/bin` is not writable on this machine and there is no sudo, so the home-dir symlink is the supported install
- Generated commands were BSD-correct, confirming the Target Environment prompt works against a real model:
  - "files larger than 100MB in my home dir" → `find ~ -type f -size +100M`
  - "files modified today with timestamps" → `find . -maxdepth 1 -type f -newerct "today" ! -newerct "tomorrow" -exec stat -f "%Sm %N" -t ... {} +` (`-newerct` and `stat -f` are macOS-only; a GNU answer would have used `-printf`/`stat -c`)
  - plan.md's original example → `cp this_folder/myfile.txt that_folder/myfile2.txt`
- "delete all the log files" → LLM returned `rm -f *.log`, client blocklist caught it, exit 3, nothing ran
- Gateway auth verified from curl: no token → 401, malformed token → 401 `invalid_token`

## Next Steps

Ordered by what blocks what. Phase 1 is small and unblocks everything after it.

### Phase 1 — get the build green and commit (blocking)
- [ ] **`./gradlew test` fails right now.** `PlaceholderResolutionException` on `${GROQ_API_KEY}`: the `.env`-loading block in `build.gradle` is attached to `bootRun` only, so `test` starts a context with no value for the placeholder. Fix by giving the property a default (`groq.api.key=${GROQ_API_KEY:dummy}`) or adding `src/test/resources/application.properties` with test values. Until this is fixed, no test can be added and CI is red on the first push
- [ ] **Commit the work.** `scripts/` is entirely untracked — the CLI, the token helper, and the decode helper are all uncommitted, so the project's user-facing half exists only on this laptop. The Java changes for platform/shell are staged but uncommitted
- [ ] `@SpringBootTest` also reaches out to the Auth0 issuer URI to fetch JWKS at context startup, which makes the one existing test network-dependent. Point the test profile at a stub issuer or exclude the security auto-config in that slice

### Phase 2 — the safety layer deserves real tests (highest value per hour)
Safety is the whole premise of the project and it is the only part with zero automated coverage.
- [ ] `ResponseValidator` unit tests — one case per blocked pattern, plus the read/copy/move commands that must survive
- [ ] `@WebMvcTest` on `ShellController` with a mocked `ShellService`, asserting the JSON contract the CLI parses (`command`/`explanation`/`isSafe`)
- [ ] Authorization tests for `AllowListAuthorizationManager`: allow-listed + verified → allow; allow-listed + unverified → deny; unknown email → deny; missing claim → deny
- [ ] A CLI test for the client blocklist. The shell function is pure — feed it a list of commands and assert blocked/allowed, no server needed

### Phase 3 — correctness and robustness defects (found, not yet fixed)
- [ ] `ResponseValidator.java:28` returns the **lowercased** command when it blocks, corrupting paths and filenames in what the user is shown. Lowercase only for matching, return `response.command()` unchanged
- [ ] **No timeouts on the Groq call.** `GroqLlmClient` builds a `RestClient` with no connect or read timeout, so if Groq stalls the request hangs and `shelli` hangs with it. Set both (~5s connect / ~30s read)
- [ ] **Groq failures surface as a raw 500.** `retrieve().body()` throws on 4xx/5xx and nothing catches it, so a rate-limit or outage reaches the CLI as an opaque gateway error. Catch it in `GroqLlmClient`/`ShellService` and return a `ShellResponse` with an empty command and a readable explanation — the CLI already renders that path correctly
- [ ] Blocklist is coarse in **both** directions: `\bdd\b` and `\bformat\b` reject innocuous commands, while `find -delete`, `truncate`, `> file`, and `mv x /dev/null` slip through. Matching the leading verb of each pipeline segment would be tighter than substring regex over the whole string
- [ ] plan.md's stated intent was "allow full access to read/copy/move, block remove/delete". The implementation is blocklist-only, which is the weaker form of that sentence — an allowlist of permitted leading verbs with a blocklist as backstop would actually match the design goal

### Phase 4 — deployment and the plan.md items still open
- [ ] **Provider selection via config is not actually done.** plan.md called for swapping providers by config change; `LlmClient` is the right interface but `GroqLlmClient` is an unconditional `@Component`, so adding a second implementation breaks startup with `NoUniqueBeanDefinitionException`. Add `@ConditionalOnProperty(name = "shelli.llm.provider", havingValue = "groq")` before a second provider exists, not after
- [ ] `SecurityConfig` permits `/actuator/health`, but `spring-boot-starter-actuator` is not on the classpath — the rule is dead and the path 401s. Add the starter (a deployed service needs a health check) or drop the rule
- [ ] Deploy the gateway so the CLI works off-laptop. Needs: real `SHELLI_API_URL` over HTTPS, secrets from the platform's secret store rather than `.env`, and the Auth0 audience/callback settings updated
- [ ] Rate limiting / cost control. Any allow-listed user can currently burn the Groq quota one request at a time; a per-subject limit matters more once this is deployed

### Phase 5 — nice to have
- [ ] `--explain-only` or a shortcut to copy the command to the clipboard (`pbcopy`) rather than run it — useful for the `cd`/`export` cases that can't work in a subshell
- [ ] Shell completion, and a `shelli history` of past generations
- [ ] Swap `spring-shell` out of `build.gradle` if no server-side interactive shell is planned; the CLI is bash and the dependency is currently unused
