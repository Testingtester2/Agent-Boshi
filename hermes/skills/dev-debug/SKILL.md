---
name: dev-debug
description: "Systematic debugging — hunt down and eliminate Shadowcats (bugs)."
version: 1.0.0
author: Agent Boshi
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [debugging, bugs, troubleshooting, root-cause]
    related_skills: [dev-review, self-improving-agent]
---

# Debug Skill

## Description
Methodically hunt down and eliminate Shadowcats (bugs) in the codebase.

## Trigger
When the user reports a bug, error, or unexpected behavior.

## Behavior
1. Gather context: error messages, stack traces, reproduction steps
2. Form hypotheses about the root cause
3. Trace execution path systematically
4. Isolate the bug to the smallest reproducible case
5. Propose a fix with explanation of *why* it works
6. Suggest tests to prevent regression (ward the portal)
