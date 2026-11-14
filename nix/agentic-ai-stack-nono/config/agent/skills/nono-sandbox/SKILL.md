---
name: nono-sandbox
description: Diagnose confirmed nono sandbox denials for Pi Coding Agent running under this stack's launcher (start-agent.sh). Generic permission failures require a clear sandbox-specific marker before remediation.
version: 1.0.0
platforms: [macos, linux]
---

# Working inside this stack's nono sandbox

The user has launched Pi with `start-agent.sh` (`nix run .#start-agent`),
which runs `pi` under `nono run --profile ... -- pi` as the untrusted `pi`
user. nono enforces filesystem and network limits at the OS level before
Pi starts -- Landlock on Linux, Seatbelt on macOS -- outside Pi's own
approval and extension systems entirely.

**Pi cannot expand nono access from inside the session, and must not try
to.** Retries, approval prompts, chmod, chown, sudo, and macOS privacy
settings do not grant new nono capabilities. Unlike the upstream nolabs-ai
`pi` nono package, this stack's `pi` user has no business running `nono
run --allow` itself or drafting its own profile -- the flake, not the
agent, owns the profile (see `profiles/work.base.json`,
`scripts/gen-profile.sh`).

## When to use this skill

Use this skill to investigate a suspected nono denial. Only output that
names nono (or a clear OS-sandbox marker) as the denying layer is
conclusive. These markers signal sandbox enforcement but do not identify
its provenance by themselves:

- `landlock`
- `sandbox: deny` or `sandbox denied`
- Generic `Operation not permitted`, `Permission denied`, `EACCES`,
  `EPERM` -- ambiguous on their own; look for a concrete blocked path or
  host alongside one of these before concluding it's a nono denial.

If `NONO_CAP_FILE` is set (`echo "$NONO_CAP_FILE"`), inspect the current
sandbox's capability summary: `cat "$NONO_CAP_FILE"`. Otherwise report:
"Nono sandbox unconfirmed; this permission failure needs a non-sandbox
diagnosis."

## Remediation: one path only

There is exactly one remediation path here -- present it to the user, do
not offer alternatives:

1. Identify the concrete blocked path (or host, for a network denial)
   from the failed tool call's stderr/output.
2. Tell the user the exact path/host, and ask them to relaunch the SAME
   session with it added, then resume:

   ```bash
   start-agent.sh --add /path/to/needed --name <same-session-name>
   # once relaunched, inside (or via) the new session:
   pi --resume
   ```

   For a network host, the only remediation is the nono approval-helper
   dialog itself (a host-level approve/deny prompt the host-side approval
   helper shows when an unlisted host is reached) -- this skill's guidance
   above is for FILESYSTEM denials specifically; there is no `--add`
   equivalent for a one-off network host.

That's it -- there is no Option B. Never suggest any of the following,
all of which conflict with this stack's model (the flake owns the
profile, not the agent or the sandboxed `pi` user):

- Running `nono run --allow ...` from inside the session.
- Drafting, editing, or promoting a profile under
  `~/.config/nono/profile-drafts/` or `~/.config/nono/profiles/`.
- Reading or editing anything under `~/.config/nono/packages`.
- `sudo`, `chmod`, `chown`, or macOS Full Disk Access -- none of these can
  grant what nono itself has not allowed.
- Retrying the same blocked operation through a different path.
- Telling the user Pi's own approval-prompt system can fix this -- it
  cannot; the nono boundary sits below it entirely.

## Notes specific to this stack

- The active profile is always `profiles/work.base.json` (composed by
  `scripts/gen-profile.sh` into a per-run `profile.json`) -- never assume
  or reference the upstream nolabs-ai `pi` nono package's profile/package
  names (`nolabs-ai/pi`, `nono pull`, `nono profile init`); none of that
  applies here.
- `PI_CODING_AGENT_DIR` and the per-run OAuth state live under
  `/var/lib/pi/runs/<name>/` (see `IMPLEMENTERS.md`'s "Per-run state
  layout"), not `~/.pi`.
