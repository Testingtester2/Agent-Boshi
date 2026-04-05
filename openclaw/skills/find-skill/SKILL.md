# Find Skill

## Description
Discover, evaluate, and install new skills from known OpenClaw skill
repositories. The Librarian scouts the Ancient Lore Repositories for useful
abilities and brings them home to your local installation.

## Trigger
When the user asks to find, search, browse, or install a new skill, or says
"find me a skill for X" or "what skills are available?"

## Behavior
1. Search known OpenClaw skill repositories for matching skills:
   - https://github.com/openclaw/openclaw-skills (official community skills)
   - https://github.com/openclaw/awesome-openclaw (curated list)
   - Local `skills/` directory for already-installed skills
2. Present matching skills with:
   - Name and one-line description
   - Trigger conditions
   - Repository source and author
   - Whether it's already installed locally
3. If the user wants to install a skill:
   - Clone/download the SKILL.md into the local `skills/<name>/` directory
   - Verify the skill follows the standard format (Description, Trigger, Behavior)
   - Report what was installed and how to use it
4. If no matches found, suggest related skills or help the user write a custom one
5. List all currently installed skills when asked "what skills do I have?"
