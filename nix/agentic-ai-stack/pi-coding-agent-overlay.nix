final: prev:

let
  inherit (final) lib stdenv;

  isArm = stdenv.hostPlatform.isAarch64;

  # koffi ships prebuilt binaries per platform; keep only the glibc build for this arch.
  koffiKeep = if isArm then "linux_arm64" else "linux_x64";

  # Directory names of the *foreign* arch in sandbox-runtime's seccomp vendor dir.
  seccompForeign = if isArm then [ "x64" "x86_64" "amd64" ] else [ "arm64" "aarch64" ];
in
{
  pi-coding-agent = prev.pi-coding-agent.overrideAttrs (old: {

    # 1. Never let the full nodejs (-> npm, corepack) back into the runtime closure.
    #    The build still uses full nodejs (it needs npm); references are repointed afterwards.
    disallowedReferences = (old.disallowedReferences or [ ]) ++ [ final.nodejs ];

    postInstall = (old.postInstall or "") + ''
      nm="$out/lib/node_modules/pi-monorepo/node_modules"

      # 2. Drop prebuilt native binaries for other platforms/arches (koffi).
      if [ -d "$nm/koffi/build/koffi" ]; then
        find "$nm/koffi/build/koffi" -mindepth 1 -maxdepth 1 -type d \
          ! -name '${koffiKeep}' -exec rm -rf {} +
      fi

      # 3. Drop foreign-arch seccomp helpers (sandbox-runtime).
      for sec in \
        "$nm/@anthropic-ai/sandbox-runtime/dist/vendor/seccomp" \
        "$nm/@anthropic-ai/sandbox-runtime/vendor/seccomp"; do
        if [ -d "$sec" ]; then
          for foreign in ${lib.concatStringsSep " " seccompForeign}; do
            rm -rf "$sec/$foreign"
          done
        fi
      done

      # 4. Trim the copied workspace packages (tests, source maps, tsbuildinfo).
      #    `src` is intentionally kept: the model catalog may be read from there.
      for ws in "$nm"/@earendil-works/*; do
        [ -d "$ws" ] || continue
        find "$ws" \( -name '*.map' -o -name '*.tsbuildinfo' \) -type f -delete
        find "$ws" -maxdepth 2 -type d \( -name test -o -name tests -o -name __tests__ \) \
          -prune -exec rm -rf {} +
      done

      # 5. General third-party cruft (skip our own @earendil-works packages, which
      #    may read their README/docs at runtime).
      find "$nm" -path "$nm/@earendil-works" -depth -o \
        -type f \( -name '*.map' -o -name '*.md' -o -name '*.markdown' -o -name '*.d.ts' \
                   -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.tsbuildinfo' \) -delete
      find "$nm" -path "$nm/@earendil-works" -prune -o \
        -type d \( -name test -o -name tests -o -name __tests__ -o -name docs -o -name example -o -name examples \) \
        -prune -exec rm -rf {} +
    '';

    postFixup = (old.postFixup or "") + ''
      # Repoint patchShebangs'd references: full nodejs -> nodejs-slim (no npm/corepack).
      grep -rIlZ "${final.nodejs}" "$out" \
        | xargs -0 -r sed -i "s|${final.nodejs}|${final.nodejs-slim}|g"
    '';
  });
}
