# Bioconda Recipe Notes

This directory mirrors the upstream Bioconda recipe inputs for `gxfkit`.
Bioconda `gxfkit 0.0.1` is already public; keep this copy in sync when preparing
future version bumps.

Bioconda recipes live in the separate `bioconda-recipes` repository. After a new
public GitHub release exists:

1. Update `recipe/` in this repository with the new version and source sha256.
2. Copy the changed recipe into `recipes/gxfkit/` in `bioconda-recipes`.
3. Confirm the version and sha256 still match the public GitHub tag.
4. Run Bioconda's local lint/build flow.
5. Open the version-bump PR.

Use the GitHub source archive or a release archive with a fixed sha256. Do not
point the recipe at a moving branch.
