# FunctionRepository

> This is a basics-only stub. The full spec is not yet designed;
> detailed design is deferred until `FunctionSpecification` is
> implemented (see [funcspec.md](funcspec.md)).

## Purpose

`FunctionRepository` points miura at a git repository with a specified
directory layout, and generates one `FunctionSpecification` per function
found in that layout.

## GVK and scope

- Group: `miura.io`
- Version: `v1alpha1`
- Kind: `FunctionRepository`
- Short name: `funcrepo`
- Scope: Namespaced

## Relationship to FunctionSpecification

A `FunctionRepository` owns (via owner references) the
`FunctionSpecification` objects it generates. Generated specs are
managed by their owning `FunctionRepository` — their fields are expected
to be reconciled from the repo layout, not edited directly by users.
This is distinct from user-authored `FunctionSpecification` objects,
which have no owning `FunctionRepository` and are fully user-managed.

## Status

Not yet designed. No spec fields, status fields, or generated children
are defined here; they will be specified once `FunctionSpecification` is
implemented and the directory-to-funcspec mapping is worked out.

## Open questions

- Directory-to-funcspec mapping: what directory/manifest format
  describes a function within the repository (one function per
  directory? an explicit manifest file per function? convention-based
  discovery?).
- Where shared defaults (e.g. common `build.env`, `runtime.resources`)
  live when multiple generated functions share them.
- Polling and commit-pinning behavior: does `FunctionRepository` poll
  independently of each generated `FunctionSpecification`'s own
  `source.pollInterval`, and how are they kept consistent?
- Pruning behavior when a directory (and therefore its function)
  disappears from the repository — does the generated
  `FunctionSpecification` get deleted immediately, deleted after a
  grace period, or left in place with a stale/error condition?
- How user-authored and generated `FunctionSpecification` objects are
  distinguished in practice (label, annotation, owner-reference check)
  so tooling and users can tell which is which.
