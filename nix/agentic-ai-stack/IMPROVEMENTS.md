# Improvement backlog

Ideas for future work on the `agentic-ai-stack`, captured from planning
discussions but not yet implemented. Each item needs its own scoping
conversation before it becomes a `.AGENT-PLAN.md`.

## 2. Dynamic, directory-scoped permissions for subagents

Question to resolve: can a subagent be granted broader `write`/`edit`/
`bash` access scoped specifically to the directory (or directories) it's
actually supposed to touch, rather than either a fixed static policy
(today's `config/agent/extensions/pi-permission-system/config.json` /
`config/agent/agents/*.md` frontmatter) or blanket `yoloMode`? Needs research
into what `@gotgenes/pi-permission-system` actually supports today (path
globs are already a first-class concept in its config — see the `path`,
`path_read`, `path_write` blocks — so this may be more "wire it up
per-dispatch" than "build new capability"), and a decision on whether
scoping happens at dispatch time (the orchestrator computes and injects a
scoped policy per subagent invocation) or some other mechanism.


## 6. Troubleshooter role

Create an agent with the permissions to run debugging commands and test. This
should be a more powerful model with a lot of permissions. Might need to run in
a second container
