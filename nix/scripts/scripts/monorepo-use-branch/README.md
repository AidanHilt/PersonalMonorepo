# monorepo-use-branch

Rewrites every reference to the monorepo's branch -- flake-style
`github:aidanhilt/PersonalMonorepo/<ref>` inputs, the
`personalMonorepoBranch` Nix global in `nix/mono-flake/flake.nix`, and the
Helm `master-stack` chart's default `gitRevision` -- so they all point at
your CURRENT git branch (read from `PERSONAL_MONOREPO_LOCATION`).

This is **roll-forward only**: there is no restore mode. To go back, check
out `main` (or whatever branch you want) and run this again.

## What it touches

- **Flake-style URLs** (`github:aidanhilt/PersonalMonorepo/<ref>...`) in
  every tracked file except `*.md`, `flake.lock`, `windows-setup/`,
  `custom-images/`, and `kubernetes/argocd/configuration-data/`. Only URLs
  that already have a ref segment are rewritten; URLs without one (e.g.
  `github:AidanHilt/PersonalMonorepo?dir=...`) are left alone and reported
  as skipped, since adding a ref would change their meaning.
- `personalMonorepoBranch = "...";` in `nix/mono-flake/flake.nix`.
- The top-level `gitRevision: ...` key in
  `kubernetes/helm-charts/k8s-resources/master-stack/values.yaml`.

It **never** touches per-cluster pins under
`kubernetes/argocd/configuration-data/**`, Dockerfiles, raw
`raw.githubusercontent.com` URLs, markdown docs, or `windows-setup/`.

After rewriting flake inputs, it runs `nix flake update <inputs>` in every
affected flake directory, updating only the PersonalMonorepo input(s) in
that directory's `flake.lock` so unrelated inputs don't drift.

## Usage

```sh
monorepo-use-branch              # show a plan, then prompt per category
monorepo-use-branch --dry-run    # show the plan only; change nothing
monorepo-use-branch --yes        # apply every category with pending changes, no prompts
monorepo-use-branch --no-lock    # skip the flake.lock update step
monorepo-use-branch --allow-unpushed  # allow targeting a branch not yet pushed to origin
```

By default, it refuses to run against a branch that hasn't been pushed to
`origin` yet (every rewritten reference would point at something that
doesn't exist remotely) -- pass `--allow-unpushed` to override, after
reading the warning it prints.

Requires `PERSONAL_MONOREPO_LOCATION` to be set and pointed at a git
checkout of the monorepo on a non-detached branch.
