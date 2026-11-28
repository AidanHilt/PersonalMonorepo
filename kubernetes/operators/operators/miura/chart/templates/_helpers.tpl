{{/*
This file exists so operators/miura/chart/templates/ is a real,
non-empty directory in git (git does not track empty directories).
mk-operator.nix's chart derivation unconditionally copies
operators/<name>/chart/templates/* when operators/<name>/chart/ exists
at all (it has to, since values.yaml alone doesn't imply a templates/
directory) — see kubernetes/operators/IMPLEMENTERS.md "Chart assembly".
A leading-underscore filename is a Helm partials file: Helm never
renders it directly as a manifest, so this is a no-op beyond satisfying
that copy step.
*/}}
