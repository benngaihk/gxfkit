# Bioconda Recipe Notes

This directory holds a starter recipe for the future Bioconda submission.

Bioconda recipes live in the separate `bioconda-recipes` repository. After a
public GitHub release exists:

1. Copy `meta.yaml.template` into a new `recipes/gxfkit/meta.yaml`.
2. Replace `{{ version }}` and `{{ sha256 }}`.
3. Run Bioconda's local lint/build flow.
4. Open the recipe PR.

Use the GitHub source archive or a release archive with a fixed sha256. Do not
point the recipe at a moving branch.
