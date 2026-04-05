# Self-Improving Agent

## Description
Analyze conversation history, tool call patterns, and outcomes to identify
weaknesses and improve The Librarian's performance over time. A Shiba that
learns from every Shadowcat encounter becomes a better guardian.

## Trigger
When the user asks to "improve yourself", "learn from mistakes", "analyze
your performance", or after a session where multiple retries or errors occurred.

## Behavior
1. Review recent conversation history and tool call results for:
   - Tasks that required multiple attempts or retries
   - Errors or unexpected outcomes
   - Cases where the user corrected the agent
   - Patterns of inefficiency (e.g., reading files that weren't needed)
2. Identify root causes:
   - Missing context or assumptions that were wrong
   - Tools that were used incorrectly
   - Knowledge gaps (e.g., unfamiliar framework or API)
3. Generate improvement actions:
   - Write notes to `~/.openclaw/learnings.md` capturing what was learned
   - Suggest SOUL.md amendments for recurring patterns
   - Propose new skill definitions if a repeated task has no skill
   - Recommend model tier changes if tasks consistently exceed model capability
4. Present a summary report:
   - What went well (Bark Power preserved)
   - What needs improvement (Shadowcats that escaped)
   - Concrete next steps
5. Apply approved changes (with user confirmation before modifying any files)
