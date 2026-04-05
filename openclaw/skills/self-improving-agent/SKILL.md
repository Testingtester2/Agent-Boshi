# Self-Improving Agent

## Description
Captures learnings, errors, and corrections to enable continuous improvement.
Every Shadowcat encounter teaches The Librarian something new — this skill
ensures those lessons are never forgotten.

Based on [pskoett/self-improving-agent](https://clawhub.ai/pskoett/self-improving-agent) (v3.0.13, MIT-0).

## Trigger

- When a command fails or produces unexpected output
- When the user corrects the agent's approach or output
- When a new capability is requested that doesn't exist yet
- When a better approach is discovered for an existing task
- When the user says "learn this", "remember this", or "improve yourself"

## Directory Structure

```
.learnings/
├── LEARNINGS.md         # Corrections, insights, knowledge gaps, best practices
├── ERRORS.md            # Command failures and integration errors
└── FEATURE_REQUESTS.md  # User-requested capabilities
```

## Entry Format

Each entry uses an ID: `TYPE-YYYYMMDD-XXX`

- **LRN**: Learning entries (corrections, insights, knowledge gaps, best practices)
- **ERR**: Error entries (command failures, integration errors)
- **FEAT**: Feature request entries (user-requested capabilities)

### Entry Template

```markdown
### TYPE-YYYYMMDD-XXX: Short summary

**Details:** What happened, what was learned, what to do differently.

**Metadata:**
- Priority: critical | high | medium | low
- Status: pending | in_progress | resolved | wont_fix | promoted
- Area: frontend | backend | infra | tests | docs | config
- Tags: relevant, keywords

**Resolution:** (if resolved)
What fixed it or what the correct approach is.
```

## Behavior

1. **On correction or failure:** Create an entry in the appropriate file
   - User corrections → `LEARNINGS.md` (type LRN)
   - Command/tool failures → `ERRORS.md` (type ERR)
   - Missing capabilities → `FEATURE_REQUESTS.md` (type FEAT)

2. **Before starting a task:** Check `.learnings/LEARNINGS.md` for relevant past
   learnings that apply to the current task. Avoid repeating known mistakes.

3. **On resolution:** Update the entry status to `resolved` and add the resolution
   block explaining the fix or correct approach.

4. **Promotion:** When a learning is broadly applicable (not session-specific),
   promote it to project-level files:
   - `CLAUDE.md` — Project facts and conventions
   - `AGENTS.md` — Workflow patterns and automation
   - Mark the original entry status as `promoted`

5. **Periodic review:** When asked to "review learnings" or "improve yourself":
   - Summarize pending/unresolved entries
   - Identify patterns across errors
   - Suggest promotions for recurring learnings
   - Report what's been learned and what's still open
