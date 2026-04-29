Hi claude,
You are a technical project architect experienced in Java, Springboot, HTTPS, shell scripting and LLM APIs

I came up with a project idea that was inspired by a problem I face daily at work -  remembering shell commands. I work with shell a lot and i keep forgetting commands for some operations now and then, I either have to save it in notes or google the exact command to finally do what I was supposed to do. For example, If I need to grep a file from a directory and then list its last modified timestamp, I have to search that up and execute the command

I want to simplify this process. I am creating a cli application (shelli) which will do just this - take simple commands that the user wants to execute, pass those commands to an llm with a prompt to give user the exact command that he ants to execute and give back the response to the user to review and execute in their shell. For example, if user says - shelli copy myfile.txt from this_folder to that_folder and rename it as myfile2.txt , my application should be able to give back the command - cp myfile.txt this_folder /tmp/that_folder/myfile2.txt
I also want to make sure to Allow only full access to read/copy/move commands, and. Block cli app from executing remove and delete commands and other sensisitve commands
As a starter, I am planning to Make a springboot application which will work as an api(Proxy Server) which will be called by by the CLI. This API will store my API token for my LLM application which will call the llm chat client and get the resonse and send it cli app

I want you to suggest me the architecture for it and give me a starter to work on it
Ask questions if you want to know more details



Claude Response : 
Show less
01:13
This is a solid, practical idea. I've got a clear picture of what you're after, but let me ask a few things before laying out the architecture.

Q: Which LLM provider are you planning to use?
A: Free LLM at first, will change when scaling

Q: For the CLI client, what are you building it in?
A: Shell script (bash)

Q: How do you want to handle the 'review before execute' flow?
A: Both options, configurable

01:14
Great choices. Using a free LLM to start is smart for prototyping. Let me lay out the full architecture and give you a working starter.

Architecture Overview
The system has three layers:

1. CLI Layer (Bash script: shelli) — the user-facing tool. It captures the natural language input, sends it to your proxy server via curl, displays the generated command, and optionally executes it based on user confirmation. It also does a client-side safety check before execution.

2. Proxy Server (Spring Boot API) — the middleware. It receives requests from the CLI, holds your LLM API key securely, constructs the prompt with safety constraints, calls the LLM, validates the response for dangerous commands server-side, and returns the shell command to the CLI.

3. LLM Provider — the brain. For the free tier, you could use Groq (free Llama 3 API), Google Gemini (free tier), or HuggingFace Inference API. The proxy abstracts this away, so swapping providers later is just a config change.

Request Flow
User types: shelli copy myfile.txt from src/ to dest/ and rename as backup.txt
|
v
[CLI: shelli.sh]
- Joins args into plain English string
- POSTs to Spring Boot API
  |
  v
  [Spring Boot Proxy]
- Receives natural language request
- Builds system prompt with safety rules
- Calls LLM API with the prompt
- Validates response (rejects rm, del, etc.)
- Returns { command, explanation, isSafe }
  |
  v
  [CLI: shelli.sh]
- Displays: "cp src/myfile.txt dest/backup.txt"
- Displays explanation
- If mode=interactive: asks Y/N to execute
- If mode=display: just shows the command
- Final client-side safety check before exec
  Key Design Decisions
  Dual-layer safety: The proxy validates LLM output server-side AND the CLI validates again client-side. The LLM can hallucinate or be prompt-injected, so you never trust its output blindly. Both layers maintain a blocklist of dangerous patterns like rm, rmdir, mkfs, dd, chmod 777, > /dev/, :(){ :|:& };:, and so on.

Prompt engineering: The system prompt explicitly tells the LLM to only return the command, no explanations in the command field, and to never generate destructive operations. You also instruct it to return a structured JSON response so parsing is deterministic.

Stateless proxy: No database needed initially. The proxy is a pure pass-through that adds the API key and prompt structure. This keeps it simple to deploy and scale.

Provider abstraction: You define a LlmClient interface in Spring Boot. You start with a GroqLlmClient or GeminiLlmClient implementation. When you want Claude or GPT later, you just add another implementation and switch via config.