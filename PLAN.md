# Repository Layout and Runtime Architecture Refactor Plan

## Summary

This plan reorganizes the repository so source files, shipped resources, docs
assets, generated build output, and research output have clear ownership.

The goal is to reduce accidental root-directory artifacts, make future native
bridge work easier, and prepare for a safe `bridge.cpp` split without changing
paint behavior.

The implementation should proceed phase by phase, with a build verification
after each phase. The phases are ordered so that path moves and script changes
happen before the risky native source split.

## Guiding Rules

- Keep behavior unchanged until the bridge split phase.
- Do not mix source files and generated files.
- Do not write generated DLLs, EXEs, temp directories, or tool outputs to the
  repository root.
- Keep `.build/` disposable. It should be safe to delete at any time.
- Keep `artifacts/` for human-readable reports and research outputs.
- Keep docs images separate from app-shipped resources.
- Keep shipped resources under one top-level directory with a name that implies
  they are packaged into the app.
- Keep release build output as a single EXE under `.build/package/`.
- Avoid compatibility shims for old repository paths unless needed for one
  transitional commit.

## Target Layout

```text
.
  src/
    csharp/
      MecchaCamouflage.Core/
      MecchaCamouflage.Controller/
      MecchaCamouflage.WebHost/
      MecchaCamouflage.Tests/
    native/
      bridge/
        bridge.cpp
      injector/
        injector.cpp
      include/
        sdk.hpp

  resources/
    mesh-profiles/
      paintman.mesh-profile-v2.json
      paintman_cube.mesh-profile-v2.json
    app-icons/
      icon.ico
      icon.png

  docs/
    assets/
      meccha-camouflage-readme-banner-v151-1600w.jpg
      social-preview.png
    runtime-bridge-map.md
    runtime-dead-code-candidates.md
    runtime-paint-replication-research.md
    research-tools.md
    release-precheck-v1.6.0-beta.3.md

  scripts/
    build.ps1
    release.ps1
    dev.ps1
    mesh.ps1
    review/
    research/

  third_party/
    CUE4Parse/
    UnrealMappingsDumper/

  .build/
    bin/
    obj/
    cache/
    tmp/
    tools/
    package/

  artifacts/
    review/
    research/
```

## Directory Ownership

### `src/`

Owns all project source code.

- `src/csharp/` contains all .NET projects.
- `src/native/bridge/` contains injected bridge source.
- `src/native/injector/` contains native injector source.
- `src/native/include/` contains shared native headers.

No generated `bin/`, `obj/`, native object files, DLLs, or EXEs should be
committed here.

### `resources/`

Owns assets that are part of the shipped application.

Examples:

- mesh profile JSON files
- app icon assets
- future app-local web assets if they are not colocated with WebHost

These files are reviewed and committed. Build scripts embed or copy them into
the single-file app package.

### `docs/assets/`

Owns images used by README, GitHub social preview, documentation, or release
notes.

These files are not app runtime resources.

### `.build/`

Owns disposable build output and local build caches.

Expected subdirectories:

- `.build/bin/`: built runnable EXE from `make build`
- `.build/obj/`: native object files and packaged native runtime inputs
- `.build/cache/`: downloaded caches such as WebView2 Fixed Runtime
- `.build/tmp/`: temporary generated projects and scratch directories
- `.build/tools/`: local helper tool build outputs
- `.build/package/`: release-ready single EXE artifacts

No tracked files should live here.

### `artifacts/`

Owns generated reports that humans inspect.

Expected subdirectories:

- `artifacts/review/`
- `artifacts/research/`

This is different from `.build/`: reports can survive between builds for review,
but they are still generated and ignored by git.

### `third_party/`

Owns third-party source checkouts or submodules.

Build output for third-party tools should go to `.build/tools/` when possible,
not inside `third_party/`.

## Phase 0 - Preflight and Inventory

Purpose: lock down current behavior and identify all path references before
moving files.

Tasks:

1. Confirm a clean working tree before starting.
   - `git status --short`
2. Record current tracked paths.
   - `git ls-files > artifacts/review/layout-before-files.txt`
3. Record current ignored root artifacts.
   - root DLLs and EXEs
   - `tmpmeccha-camouflage.builddebugapply1/`
   - `.build/`
   - `artifacts/`
   - `tools/`
4. Identify all hardcoded old layout references.
   - `runtime/csharp`
   - `runtime/src`
   - `runtime/include`
   - `resources/mesh-profiles`
   - `assets/icon`
   - `assets/*.jpg`
   - `.build/mesh-profile-tool`
   - root `runtime-bridge.dll`
   - root `runtime-injector.exe`
5. Confirm canonical commands before changes.
   - `make build`
   - `make review-dead-code`
   - `git diff --check`

Verification:

- `make build` passes before refactor.
- Inventory files are written only under `artifacts/review/`.
- No code or source layout changes in this phase.

## Phase 1 - Root Artifact Cleanup Policy

Purpose: stop root directory clutter and make accidental generated files easy to
detect.

Tasks:

1. Remove ignored root generated files from the local workspace.
   - `runtime-bridge.dll`
   - `runtime-injector.exe`
   - `tmpmeccha-camouflage.builddebugapply1/`
2. Confirm these files are not tracked.
   - `git ls-files runtime-bridge.dll runtime-injector.exe`
3. Add or update cleanup scripts so future cleanup is explicit.
   - `make clean` should remove `.build/`.
   - Add a separate target for generated reports if needed, for example
     `make clean-artifacts`.
   - Add a root-artifact cleanup target only if it is useful during migration.
4. Strengthen `.gitignore` comments so root generated DLL/EXE files are clearly
   build artifacts, not project files.
5. Consider a lightweight guard script that fails if ignored root DLL/EXE/temp
   artifacts exist after a build.
   - This can be report-only at first.
   - Do not block release until the script is stable.

Verification:

- `git status --short` remains clean after local artifact cleanup.
- `make build` does not recreate root DLLs or root EXEs.
- Native build outputs still appear under `.build/obj/package-native/`.
- App EXE still appears under `.build/bin/`.

## Phase 2 - Split Docs Assets from App Resources

Purpose: separate README/GitHub images from resources embedded in the app.

Current state:

- `assets/social-preview.png` is a docs/GitHub asset.
- `assets/meccha-camouflage-readme-banner-v151-1600w.jpg` is a README asset.
- `assets/icon.png` and `assets/icon.ico` are app icon resources.
- `resources/mesh-profiles/*.json` are app runtime resources.

Target moves:

```text
assets/social-preview.png
  -> docs/assets/social-preview.png

assets/meccha-camouflage-readme-banner-v151-1600w.jpg
  -> docs/assets/meccha-camouflage-readme-banner-v151-1600w.jpg

assets/icon.png
  -> resources/app-icons/icon.png

assets/icon.ico
  -> resources/app-icons/icon.ico

resources/mesh-profiles/*.json
  -> resources/mesh-profiles/*.json
```

Tasks:

1. Create `docs/assets/`.
2. Create `resources/app-icons/`.
3. Create `resources/mesh-profiles/`.
4. Move README and social images to `docs/assets/`.
5. Move app icons to `resources/app-icons/`.
6. Move mesh profile JSON files to `resources/mesh-profiles/`.
7. Update `README.md` image paths.
8. Update docs that refer to `resources/mesh-profiles/`.
   - `docs/research-tools.md`
   - `docs/runtime-paint-replication-research.md`
   - `docs/release-precheck-v1.6.0-beta.3.md`
9. Update `scripts/build.ps1`.
   - `$MeshProfilesSourceDir` should point to `resources\mesh-profiles`.
10. Update `scripts/mesh.ps1`.
    - default output should point to `resources\mesh-profiles`.
11. Update C# project resource includes if any direct icon paths exist.
12. Remove empty `assets/` directory if nothing remains.

Verification:

- `rg "assets/" README.md docs scripts src runtime` has no stale app resource
  references.
- `make build` embeds mesh profiles from `resources/mesh-profiles`.
- README image links still resolve.
- Release package remains a single EXE.

## Phase 3 - Normalize Build, Tool, and Report Output

Purpose: make every generated file land in `.build/` or `artifacts/`.

Tasks:

1. Confirm `scripts/build.ps1` uses:
   - `.build\bin`
   - `.build\obj`
   - `.build\cache`
2. Confirm native output uses:
   - `.build\obj\bridge.obj`
   - `.build\obj\injector.obj`
   - `.build\obj\package-native\runtime-bridge.dll`
   - `.build\obj\package-native\runtime-injector.exe`
3. Change `scripts/mesh.ps1` helper project output.
   - From `.build\mesh-profile-tool`
   - To `.build\tools\mesh-profile-tool`
4. Confirm `scripts/release.ps1` writes to `.build\package`.
5. Confirm `scripts/dev.ps1` reads from `.build\bin`.
6. Confirm review script output remains under `artifacts/review/`.
7. Confirm research script output remains under `artifacts/research/`.
8. Add or update docs describing generated output policy.
   - Recommended location: `docs/repository-layout.md`
   - Or keep this in `PLAN.md` until the refactor is complete.
9. Keep `artifacts/` ignored by git.
10. Keep `.build/` ignored by git.
11. Keep root `tools/asset_probe` intact.
    - Do not delete it during layout cleanup.
    - New generated helper tool output should still go under `.build/tools/`.

Verification:

- `make clean && make build`
- root directory does not gain generated DLL/EXE/temp output.
- `find . -maxdepth 1` shows no generated clutter except ignored `.build/` and
  `artifacts/`.
- `git status --ignored --short` shows generated output only under approved
  directories.

## Phase 4 - Move Repository Source from `runtime/` to `src/`

Purpose: remove the overloaded top-level `runtime/` name from source layout.

Important distinction:

- Repository source should move from `runtime/` to `src/`.
- LocalAppData runtime cache names inside the application can stay as runtime
  terminology, because those paths describe extracted runtime state.

Target moves:

```text
runtime/csharp/
  -> src/csharp/

runtime/src/bridge.cpp
  -> src/native/bridge/bridge.cpp

runtime/src/injector.cpp
  -> src/native/injector/injector.cpp

runtime/include/sdk.hpp
  -> src/native/include/sdk.hpp
```

Tasks:

1. Create target directories.
2. Move C# projects with `git mv`.
3. Move native source with `git mv`.
4. Move native include files with `git mv`.
5. Update project references in C# `.csproj` files.
   - `MecchaCamouflage.Tests`
   - `MecchaCamouflage.Controller`
   - `MecchaCamouflage.WebHost`
6. Delete legacy WPF and WinUI projects if any source remains.
   - They are no longer supported app surfaces.
   - The supported controller is WebHost.
7. Update `scripts/build.ps1` paths.
   - `$BridgeSource`
   - `$InjectorSource`
   - `$WebHostProject`
   - `$TestsProject`
   - `$MeshProfilesSourceDir`
8. Update `scripts/dev.ps1` if it references old paths.
9. Update `scripts/review/runtime-dead-code-inventory.ps1`.
   - Inventory `src`, `resources`, `scripts`, `docs`, `Makefile`.
   - Rename output labels from runtime-files to source-files if helpful.
10. Update docs references.
   - `docs/runtime-bridge-map.md`
   - `docs/runtime-dead-code-candidates.md`
   - `docs/research-tools.md`
   - `docs/release-precheck-v1.6.0-beta.3.md`
11. Update `README.md` if it mentions old paths.
12. Update `.gitignore`.
    - Replace `/runtime/csharp/**/bin/` with `/src/csharp/**/bin/`.
    - Replace `/runtime/csharp/**/obj/` with `/src/csharp/**/obj/`.
13. Remove empty `runtime/` directory after move.

Verification:

- `rg "runtime/csharp|runtime/src|runtime/include" .` only finds historical
  references that are intentionally retained.
- `make build` passes.
- `make review-dead-code` passes.
- `make start` can launch the built EXE.
- Runtime extraction in LocalAppData still uses versioned runtime cache as
  before.

## Phase 5 - Project Hygiene After Source Move

Purpose: clean stale generated files and ensure the move did not carry old
`bin/` or `obj/` output into the new source tree.

Tasks:

1. Remove generated `bin/` and `obj/` directories from source tree.
   - `src/csharp/**/bin/`
   - `src/csharp/**/obj/`
2. Confirm these directories are ignored.
3. Confirm no generated files are accidentally staged.
4. Check for old absolute paths in generated files.
   - These should not remain in tracked files.
5. Keep root `tools/asset_probe`.
   - This directory is intentionally preserved.
   - Do not delete it as part of cleanup.
   - Do not use it for new generated helper tool output.

Verification:

- `git status --short`
- `git diff --check`
- `git ls-files | rg "/bin/|/obj/"` returns no generated build output.
- `make build` passes from a clean `.build/`.

## Phase 6 - Update Documentation and Contributor Mental Model

Purpose: make the new layout self-explanatory.

Tasks:

1. Add `docs/repository-layout.md`.
2. Document:
   - source layout
   - shipped resources
   - docs assets
   - generated build output
   - review and research artifacts
   - local app runtime cache under LocalAppData
3. Update `docs/research-tools.md`.
   - Mesh profile output now goes to `resources/mesh-profiles`.
   - Research output stays under `artifacts/research`.
4. Update `docs/runtime-bridge-map.md`.
   - Source paths now use `src/native`.
   - C# paths now use `src/csharp`.
5. Update `docs/runtime-dead-code-candidates.md`.
   - Keep classifications.
   - Update paths only.
6. Update release precheck doc.
   - Build output path remains `.build/package`.
   - Resource source path becomes `resources/`.
7. Update README paths.

Verification:

- `rg "resources/mesh-profiles|runtime/csharp|runtime/src|runtime/include" docs README.md`
  has no stale references except explicit migration notes.
- `make build` remains green after documentation changes.

## Phase 7 - Native Bridge Split Preparation

Purpose: prepare `bridge.cpp` for file splitting without behavior changes.

Do not start by deleting code. Do not start by changing paint behavior.

Tasks:

1. Re-run dead-code inventory after path move.
   - `make review-dead-code`
2. Refresh `docs/runtime-bridge-map.md`.
3. Define native bridge module boundaries:
   - IPC listener and command dispatch
   - progress writing and progress metadata
   - JSON helpers and response formatting
   - UE reflection and object lookup
   - SDK layout helpers
   - mesh profile loading
   - mesh capture and planning
   - preview and unpreview
   - packed paint replication
   - research probes
4. Add a native bridge split map to docs before moving code.
5. Identify the lowest-risk extraction candidates.
   - Pure helpers first.
   - No Unreal object lifetime assumptions first.
   - No ProcessEvent or packed paint call paths first.
6. Decide naming convention.
   - `bridge_ipc.cpp`
   - `bridge_progress.cpp`
   - `bridge_json.cpp`
   - `ue_reflection.cpp`
   - `mesh_profiles.cpp`
   - `mesh_planner.cpp`
   - `paint_packed_replication.cpp`
   - `research_probes.cpp`
7. Add shared headers only when needed.
   - Avoid dumping everything into one large global header.
   - Prefer small internal headers by responsibility.

Verification:

- No code movement yet in this phase unless the map is complete.
- `make build`
- `make review-dead-code`

## Phase 8 - Native Bridge Mechanical Split

Purpose: split `bridge.cpp` mechanically with no behavior changes.

Rules:

- One extraction commit at a time.
- Compile after each extraction.
- Do not rename functions while moving them.
- Do not change control flow while moving functions.
- Do not delete research probes during split.
- Do not change packed paint behavior during split.

Suggested order:

1. Extract JSON and response helpers.
   - Lowest risk.
   - Should not depend on Unreal memory.
2. Extract progress snapshot writing.
   - Keep output format unchanged.
   - Keep C# parser compatibility unchanged.
3. Extract IPC listener and command dispatch.
   - Keep command names unchanged.
   - Keep response JSON unchanged.
4. Extract mesh profile loading.
   - Keep profile schema unchanged.
   - Keep profile file search unchanged.
5. Extract research probe helpers.
   - Keep disabled-by-default behavior unchanged.
6. Extract UE reflection helpers.
   - Higher risk.
   - Requires careful compile and live smoke testing.
7. Extract mesh planning.
   - Higher risk.
   - Requires preview and paint smoke testing.
8. Extract packed paint replication.
   - Highest risk.
   - Requires multiplayer verification later.

Verification after each extraction:

- `make build`
- Native bridge compiles with the same dependency allowlist.
- App starts.
- Bridge connects.
- Preview applies.
- UnPreview restores.
- Paint runs.
- Packed paint still uses `ServerPackedPaintBatch`.

Manual game verification can be grouped after several low-risk extractions, but
packed paint extraction needs explicit live verification.

## Phase 9 - Dead-Code Cleanup After Split

Purpose: remove actual dead code only after the code has clear module
boundaries.

Tasks:

1. Re-run `make review-dead-code`.
2. Classify candidates again:
   - keep dynamic entry
   - keep SDK layout
   - keep reflection entry
   - keep research only
   - delete candidate
3. Remove only code that is:
   - unreachable by command dispatch
   - not referenced by research probes
   - not required by dynamic reflection
   - not part of SDK layout assumptions
4. Prefer small deletion commits.
5. Update `docs/runtime-dead-code-candidates.md`.

Verification:

- `make build`
- `make review-dead-code`
- live preview/unpreview smoke
- live paint smoke
- multiplayer verification when possible

## Phase 10 - Release Precheck

Purpose: ensure layout refactor did not affect beta release readiness.

Tasks:

1. Run canonical build.
   - `make clean`
   - `make build`
2. Run packaging.
   - `make package`
3. Confirm release artifact.
   - `.build/package/meccha-camouflage-<version>.exe`
4. Confirm no loose WebView2 runtime is required.
5. Confirm no loose native DLL or injector EXE is required for users.
6. Confirm app startup diagnostics still work.
7. Confirm runtime asset cache repair still works.
8. Confirm bridge state directory still works.
   - LocalAppData `MecchaCamouflage/bridge-state/progress`
9. Confirm root directory is clean after build.
10. Confirm ignored generated files only appear in approved places.

Verification:

- `git status --short`
- `git diff --check`
- `make build`
- `make package`
- manual smoke with game

## Recommended Commit Boundaries

1. `chore(build): keep generated files out of root`
2. `chore(resources): split docs assets from app resources`
3. `chore(build): normalize generated output paths`
4. `refactor(repo): move source tree under src`
5. `docs: document repository layout`
6. `refactor(native): prepare bridge split map`
7. `refactor(native): split bridge json helpers`
8. `refactor(native): split bridge progress helpers`
9. `refactor(native): split bridge ipc`
10. Additional native split commits by module.
11. `refactor(native): remove confirmed dead code`

Each commit should be buildable on its own unless the move is too large. If a
single source tree move must happen in one commit, keep it purely mechanical.

## Risks

### Path churn

Moving `runtime/` to `src/` will touch many paths. The risk is missing one
hardcoded path in scripts, docs, or project references.

Mitigation:

- Use `rg` before and after.
- Keep the move mechanical.
- Run `make build` immediately after the move.

### Generated files accidentally staged

Existing `bin/` and `obj/` directories may appear under moved source paths if
not cleaned.

Mitigation:

- Clean before moving.
- Re-check `git status --short`.
- Re-check `git ls-files | rg "/bin/|/obj/"`.

### Native bridge split behavior changes

`bridge.cpp` contains dynamic UE reflection, ProcessEvent calls, packed paint
replication, and research probes. These are fragile.

Mitigation:

- Split after layout cleanup.
- Move one responsibility at a time.
- Compile after each extraction.
- Avoid semantic edits during split.
- Keep packed paint route untouched until after mechanical split.

### Old docs confusing contributors

Docs may continue to mention `runtime/` or `resources/mesh-profiles`.

Mitigation:

- Update docs in the same phase as path moves.
- Add `docs/repository-layout.md`.
- Use `rg` to verify stale references.

## Open Questions

1. Should `resources/` be the final name for shipped app resources?
   - Recommendation: yes.
   - Alternative: `app-assets/`.
   - Avoid `public/` because this is not only a web frontend.

2. Should WPF and WinUI projects remain under `src/csharp/`?
   - Decision: no.
   - Delete them because they are legacy and no longer needed.

3. Should root `tools/asset_probe` be kept?
   - Decision: yes.
   - Keep it in place.

4. Should `artifacts/` be kept at root?
   - Recommendation: yes.
   - It is useful for review and research output, and it is clearly different
     from disposable `.build/` output.

5. Should the native bridge split happen before beta.3 release?
   - Recommendation: only do mechanical low-risk split before beta.3 if there
     is enough time for live smoke testing.
   - Packed paint replication extraction should wait unless we can test the
     game after the split.
