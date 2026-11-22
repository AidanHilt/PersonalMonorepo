# HANGUPS

A running log of friction points for this work item -- permission gaps,
unclear/inaccurate instructions that needed redirection, and ways the
sandbox/environment structure got in the way. Meant as input for the next
work item on this stack, not as user-facing documentation.

## Planning agent

- `sed` is denied by pi-permission-system policy; had to use `Read` with
  offsets instead for everything that would normally be a quick `sed -n`.
- `ffgrep` path filters written repo-relative (e.g.
  `nix/agentic-ai-stack/...`) silently returned nothing or unfiltered
  results, because the index root is the cwd (the stack dir itself), not
  the repo root.
- The planning agent has no write tool, no `git`, no `nix`, and cannot
  test anything -- every finding and the whole plan is unverified until
  the implementer runs `agent-validate`; everything had to be handed over
  via the dispatch prompt rather than left for the implementer to
  discover.
- `AGENTS.md` describes `agent-plan-create` in depth but does not say
  whether `--paths` are cwd-relative or repo-relative; running it with
  repo-relative paths warned `No checks generated ... (not found on
  disk)` for README.md/IMPLEMENTERS.md/SKILL.md/HANGUPS.md (the
  HANGUPS.md one was expected, since it didn't exist yet at plan time;
  the others were unexplained).
- `start-agent.sh` hardcodes `/nix/store/<hash>-...` paths (`etc-profile`,
  `set-environment`) in its profile `--add` grants, which will break
  silently after a `nixpkgs` update. Out of scope for this work item, but
  worth a future one.
- `ask_user_question`'s option-label length limit (16 chars) is only
  discovered by a failing validation, not documented up front.
- The planning agent had to ask the user about nono state under `/tmp`
  overlapping nono's own protected state root, because the interaction
  between the existing `--add /tmp` grant and nono's state-root rules
  isn't documented anywhere in this checkout.

## Implementer agent

- **`pi`'s own source isn't vendored in this checkout**, so "where does
  the web-search extension read `web-search.json` from" (plan step 1)
  couldn't be answered by reading code -- only inferred. The inference:
  `config/agent/README.md` already describes `config/web-search.json` as
  mirroring `~/.pi/web-search.json` (a SIBLING of `~/.pi/agent/`, i.e.
  `PI_CODING_AGENT_DIR`'s parent), and `config/agent/AGENTS.md` documents
  `agent-plan-create`'s own fallback as
  `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/agents` (confirming pi's
  default `PI_CODING_AGENT_DIR` really is `$HOME/.pi/agent`). Since the
  `pi` user's actual `$HOME` is `/var/lib/pi`, I placed the fixed agent
  dir at `/var/lib/pi/.pi/agent` (so it's the literal path pi's own code
  would resolve to if it ever read `$HOME`) and the web-search file at
  the sibling `/var/lib/pi/.pi/web-search.json`. This is consistent with
  every existing doc reference, but still an inference, not something
  confirmed against pi's actual source -- flag for a future pass if pi
  turns out to read web-search.json from somewhere else entirely (e.g.
  `$XDG_CONFIG_HOME/pi/`).
- **`nono ps`'s exact output schema is undocumented** in this checkout
  (no vendored nono source, no man page, no existing parsing logic beyond
  `grep -q <name>` substring checks). This affects THREE new pieces of
  logic this work item added:
  1. `nono_any_session_running` (wipe-before-launch/wipe-after-stop
     gating): treats ANY non-empty `nono ps` output as "something is
     live". If `nono ps` prints a fixed "no sessions" placeholder line
     instead of truly empty output when nothing is running, this will
     never wipe (safe failure mode -- a skipped wipe just leaves stale
     scratch state around, it never destroys a live session's state).
  2. `nono_list_live_sessions`/`nono_list_live_main_sessions`
     (auto-select for `attach`/`shell`/`stop`): takes the first
     whitespace-delimited field of each line and keeps only tokens
     matching the session-name charset, which silently (and, I believe,
     harmlessly) drops anything that looks like a column header instead
     of an actual session row. If `nono ps`'s real format doesn't put the
     session name first on each line, or uses a non-whitespace delimiter,
     this will mis-parse -- auto-select would then report "no live
     session" even when one exists, which is also a safe failure (the
     user just has to pass `<name>` explicitly, exactly like before this
     change), never a wrong auto-selection landing on the wrong session
     (the parse is conservative: it only ever narrows the candidate list,
     never fabricates a name that wasn't actually a `nono ps` output
     token).
  3. `stop.sh`'s post-stop wipe check re-runs `nono ps` against the SAME
     state dir immediately after `nono stop <name>` succeeded. If `nono
     ps` continues to list a just-stopped session (e.g. in a "stopped"
     state rather than omitting it entirely), the shared state dir would
     never get wiped even when it's actually safe to. Not verifiable
     without a real nono binary and a real session to stop.
  All three are logged here per the plan's own instruction ("pick the
  safest option... and log it") rather than guessed silently.
- **Pre-existing doc/code mismatch in `start-agent.sh`**: `IMPLEMENTERS.md`
  stated the session name defaults to `"pi"` and is "deliberately NOT
  timestamp-suffixed" (for `--resume` purposes), but the actual code
  (`SESSION_NAME="${SESSION_NAME_ROOT}-${DATE}"`) always appends a Unix
  timestamp, and has done so independent of this work item. I left the
  CODE unchanged (not in scope) but corrected the --help text/
  IMPLEMENTERS.md wording to describe actual behavior, since this work
  item was already rewriting those exact paragraphs and leaving a known
  lie in freshly-edited docs seemed worse than fixing it. This also
  turned out to dovetail with the new fixed-agent-dir design: `--resume`
  no longer depends on reusing the SAME timestamped nono session name at
  all, only on the one fixed, shared `PI_CODING_AGENT_DIR` -- so the
  pre-existing timestamp-suffix behavior stopped being a correctness
  problem for `--resume`, it just made the old docs inaccurate.
- **Detached-mode agent-dir grant gap (fixed as a side effect)**: the OLD
  code granted the whole `/var/lib/pi/runs` tree (and so, transitively,
  each run's nested `pi/agent/`) via a hardcoded `--add` flag that only
  existed in `start-agent.sh`'s FOREGROUND branch of the
  `gen-profile.sh` invocation -- the `--detached` branch's own
  `GEN_ARGS_QUOTED` never included it. This looks like a pre-existing bug
  where a `--detached` session's sandboxed `pi` process never actually
  had read-write access to its own `PI_CODING_AGENT_DIR`. This work item
  moves the equivalent grant (`--add "$FIXED_PI_HOME"`) into the shared
  `EXTRA_GEN_ARGS` array used by BOTH branches, which incidentally fixes
  this gap. Flagging it explicitly since it wasn't something this plan
  asked to fix, but leaving it broken while restructuring the exact grant
  it depended on didn't seem defensible either.
- **`login.sh` was left deliberately untouched in spirit** (its own
  `/var/lib/pi/login/` layout, including its own separate, non-shared
  nono state dir) per the plan's explicit out-of-scope note, but its
  Darwin nono-state-dir branch previously called the shared helper
  `nono_state_dir_for(name)`, which no longer exists (renamed to the
  argument-less `nono_state_dir()`, since every OTHER session now shares
  one dir). I inlined the equivalent path construction directly in
  `login.sh` instead of reusing the renamed shared helper, to avoid
  accidentally merging login's state into the new shared `ps.sh`/
  `nono_any_session_running` accounting. This is a judgment call the
  plan didn't fully spell out (it says login's layout is unchanged, but
  doesn't say whether login should join the new single-state-dir scheme)
  -- flag if a future pass wants login sessions visible in `nix run .#ps`
  too.
- **`agent-validate`'s BUILD_TEST phase (`nix flake check`) is blocked by
  my own dispatch sandbox's command policy**, deterministically:
  `nono: command policy denied nix: Command 'nix' is blocked:
  invocation_policy.default deny`. I am only granted the single exact
  bash command `agent-validate --path ...`; when agent-validate
  internally shells out to `nix flake check nix/agentic-ai-stack` for the
  BUILD_TEST phase, that subprocess is denied by the same nono policy
  wrapping my whole process tree, not by anything content-related. This
  reproduced identically across 2 separate runs (same denial, same exit
  126 wrapped to agent-validate exit 10) with no code changes in
  between, so it is not a flake failure from my edits -- FORMAT
  (shfmt/nixfmt) and LINT (shellcheck on every `scripts/*.sh`, `bash -n`
  on every script, `statix check` on `flake.nix`) all pass cleanly.
  IMPLEMENTERS.md documents `work.base.json`'s `nix` command policy as
  allowing `build`/`eval`/`develop`/`flake check`/`flake show` for `pi`'s
  OWN sandboxed sessions -- that policy is irrelevant here, since I (the
  IMPLEMENT-1 dispatch agent) am a different, more restrictive sandbox
  layer with no `nix` access granted at all. I cannot request more
  permissions (bash is locked to the one exact command, no approval
  fallback), so I stopped after confirming this is deterministic rather
  than spending the rest of the failure budget on identical retries. See
  the final report's "Final agent-validate result" for the exact
  numbers.
- **`stop.sh`'s "leftover directory" candidate detection** (plan step 4)
  does a linear scan of `$SESSIONS_ROOT/*` calling `nono_session_running`
  twice per entry (main + shell) via `sudo -u pi nono ps`, which is one
  `sudo` subprocess per leftover directory -- fine at the expected scale
  (a handful of crashed launches at most) but worth noting as not
  optimized for a large `$SESSIONS_ROOT`.

Also, the sandbox currently blocks nix, but our checks require it