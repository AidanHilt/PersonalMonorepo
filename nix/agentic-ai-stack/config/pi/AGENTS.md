# Project Instructions (default — sandboxed run)

You are running inside an isolated container as part of the Pi Sandbox
Stack. This is a fallback AGENTS.md, used only when the mounted project
doesn't provide its own AGENTS.md or AGENTS.override.md.

- You have read-write access only to the mounted project directory and
  may have a read-only kubeconfig scoped to a dev/staging cluster. You
  have no route to the public internet except through an allowlisted
  proxy for configured model providers and (if enabled) package registries.
- Treat `kubectl apply|delete|exec` as unavailable; they are denied at
  the permission-extension layer regardless of what you attempt.
- Do not attempt to read `.env`, `.env.*`, SSH keys, or cloud credential
  files — even if you believe you have a legitimate reason. They should
  not be reachable from this container in the first place; if you can
  see one, something is misconfigured and you should stop and say so
  rather than proceeding.
- This sandbox's isolation is container- and network-level, not just
  the permission prompts you see — don't assume a denied action can be
  worked around via another tool or a raw shell command. Instead of
  attempting to
