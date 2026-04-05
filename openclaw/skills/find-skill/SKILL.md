# Find Skills

## Description
Discover OpenClaw skills across multiple platforms and registries.
Scout the Ancient Lore Repositories for new abilities to add to The Librarian's arsenal.

Based on [lq-productor/find-skills-skill-1-0-0](https://clawhub.ai/lq-productor/find-skills-skill-1-0-0) (v1.0.0, MIT-0).

## Trigger

When the user wants to find, search, browse, or discover skills for a specific task.
Examples: "find a skill for testing", "what skills exist for web scraping",
"search for deployment skills", "browse available skills".

## When NOT to Use

- Direct installation — use `npx clawhub install <skill>` instead
- Managing existing skills — use `openclaw skills list`
- Creating new skills — use a skill-creator tool

## Knowledge Sources

Search these sources in order of priority:

1. **ClawHub (Primary Registry)**
   ```bash
   npx clawhub search "keyword"
   npx clawhub browse
   ```
   Browse at: https://clawhub.ai

2. **OpenClaw Skills Directory**
   https://www.openclawdirectory.dev/skills

3. **GitHub Repositories**
   Search for repos containing `SKILL.md` files:
   ```
   github search: "SKILL.md" + keyword
   ```

4. **Community Sources**
   - OpenClaw Discord #skills channel
   - SitePoint OpenClaw forums

## Behavior

1. **Parse the request:** Identify what capability the user needs
   (e.g., "testing", "deployment", "code generation", "web search")

2. **Search ClawHub first:**
   - Run `npx clawhub search "<keyword>"` for direct matches
   - Check category listings with `npx clawhub browse`
   - Note download counts and install numbers as popularity signals

3. **Expand search if needed:**
   - Check the OpenClaw Directory for curated listings
   - Search GitHub for SKILL.md files matching the topic
   - Try alternate keywords (e.g., "test" → "testing", "unit test", "jest")

4. **Present results:** For each matching skill, show:
   - Name and version
   - One-line description
   - Author / publisher
   - Install count (if available)
   - Install command: `npx clawhub install <package>`

5. **If no results:** Suggest:
   - Broader or alternate search terms
   - Creating a custom skill for the need
   - Checking community forums for recommendations
