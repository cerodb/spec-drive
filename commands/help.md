---
description: Show Spec-Drive commands and workflow overview
argument-hint: ""
allowed-tools: []
---

# /spec-drive:help

Output the following help text exactly:

```
Spec-Drive — Spec-driven development for Claude Code

COMMANDS

  /spec-drive:new [name]           Create a new project from an idea
  /spec-drive:research             Run research phase on idea.md
  /spec-drive:requirements         Generate requirements from research
  /spec-drive:design               Create architecture from requirements
  /spec-drive:tasks                Generate task plan from design
  /spec-drive:implement            Execute tasks (autonomous loop)
  /spec-drive:status               Show project status and progress
  /spec-drive:cancel [--delete]    Cancel execution, optionally delete project
  /spec-drive:help                 Show this help message

WORKFLOW

  idea.md → research → requirements → design → tasks → implement

  Each phase produces a Markdown document that feeds the next.
  In normal mode, you approve each phase before continuing.
  In auto mode (--auto flag on /spec-drive:new), phases chain automatically.

PROJECT STRUCTURE

  ~/spec-drive-projects/
    my-project/
      spec/
        idea.md              Your project vision and constraints
        research.md          Technical research and feasibility
        requirements.md      User stories and acceptance criteria
        design.md            Architecture and component design
        tasks.md             Phased implementation plan
        .progress.md         Execution progress and learnings
        .spec-drive-state.json   Execution state (auto-managed)

QUICK START

  1. /spec-drive:new my-feature     Create project with idea template
  2. Edit spec/idea.md              Describe your vision and constraints
  3. /spec-drive:research           Gather context and feasibility data
  4. /spec-drive:requirements       Generate user stories and ACs
  5. /spec-drive:design             Produce architecture document
  6. /spec-drive:tasks              Create phased task plan
  7. /spec-drive:implement          Execute tasks autonomously

  Or use --auto: /spec-drive:new my-feature --auto
  This runs the full pipeline automatically, bypassing approval gates between phases.
```
