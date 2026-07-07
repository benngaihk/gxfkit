#!/usr/bin/env bash
# Local preflight before cutting a gxfkit release tag.
#
# This intentionally checks the cheap, deterministic pieces locally. The
# cross-platform archives are still validated by .github/workflows/release.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CARGO_BIN="${CARGO:-cargo}"
if ! command -v "$CARGO_BIN" >/dev/null 2>&1; then
  if [ -x "$HOME/.cargo/bin/cargo" ]; then
    CARGO_BIN="$HOME/.cargo/bin/cargo"
  else
    echo "cargo not found on PATH and $HOME/.cargo/bin/cargo is missing" >&2
    exit 127
  fi
fi
VERSION_SCOPE="${RELEASE_CHECK_VERSION_SCOPE:-all}"
PACKAGE_NETWORK="${RELEASE_CHECK_PACKAGE_NETWORK:-0}"
if [ "$PACKAGE_NETWORK" != 0 ] && [ "$PACKAGE_NETWORK" != 1 ]; then
  echo "RELEASE_CHECK_PACKAGE_NETWORK must be 0 or 1, got: $PACKAGE_NETWORK" >&2
  exit 2
fi
package_args=(--locked --allow-dirty --registry crates-io)
if [ "$PACKAGE_NETWORK" = 0 ]; then
  package_args+=(--offline)
fi

if [ -f "$HOME/.cargo/config.toml" ] && grep -q "replace-with" "$HOME/.cargo/config.toml"; then
  cat >&2 <<'MSG'
warning: ~/.cargo/config.toml contains a source replacement.
Local cargo package/publish checks may use that mirror even with --registry
crates-io. For the real Crates.io publish, prefer the GitHub workflow or run
from an environment without source.crates-io.replace-with.
MSG
fi

echo ">> formatting"
"$CARGO_BIN" fmt --all -- --check

echo ">> linting"
"$CARGO_BIN" clippy --locked --all-targets -- -D warnings

echo ">> tests"
"$CARGO_BIN" test --all --locked

echo ">> release build"
"$CARGO_BIN" build --release --locked --bin gxfkit

echo ">> local cargo install"
bash scripts/test-local-cargo-install-verifier.sh
VERIFY_LOCAL_CARGO_INSTALL_NETWORK=0 CARGO="$CARGO_BIN" bash scripts/verify-local-cargo-install.sh

echo ">> Crates.io install verifier"
bash scripts/test-crates-install-verifier.sh

echo ">> Crates.io metadata"
bash scripts/test-crate-metadata.sh
python3 scripts/check-crate-metadata.py

echo ">> release archive verifier"
bash scripts/test-release-archive-verifier.sh
bash scripts/test-release-artifacts.sh
python3 scripts/check-release-artifacts.py

echo ">> GitHub release verifier"
bash scripts/test-github-release-verifier.sh
bash scripts/test-github-release-parity.sh

echo ">> Bioconda recipe"
python3 scripts/check-bioconda-recipe.py
bash scripts/test-bioconda-recipe.sh
bash scripts/test-github-source-sha256.sh

echo ">> Bioconda install verifier"
bash scripts/test-bioconda-install-verifier.sh

echo ">> public install audit verifier"
bash scripts/test-public-installs-verifier.sh
bash scripts/test-public-audit-log.sh
bash scripts/test-shell-syntax.sh
python3 scripts/test-python-syntax.py
bash scripts/test-release-check.sh
python3 scripts/check-release-check.py
bash scripts/test-release-check-log.sh
bash scripts/test-repo-hygiene.sh
bash scripts/test-executable-scripts.sh
bash scripts/test-public-install-audit-workflow.sh
bash scripts/test-ci-workflow.sh
bash scripts/test-release-workflow.sh
bash scripts/test-publish-crates-workflow.sh
bash scripts/test-workflow-policy.sh
python3 scripts/check-workflow-policy.py

echo ">> publish ref verifier"
bash scripts/test-publish-ref.sh
bash scripts/test-trigger-crates-publish.sh

echo ">> benchmark summarizer"
bash scripts/test-benchmark-summarize.sh
bash scripts/test-benchmark-summary.sh
python3 scripts/check-benchmark-summary.py

echo ">> parity doc"
bash scripts/test-parity-doc.sh
python3 scripts/check-parity-doc.py

echo ">> residual writer"
bash scripts/test-write-residuals.sh

echo ">> version consistency self-test"
bash scripts/test-version-consistency.sh
bash scripts/test-prepare-next-version.sh

echo ">> version consistency"
python3 scripts/check-version-consistency.py --scope "$VERSION_SCOPE"

echo ">> release status doc"
bash scripts/test-release-status-doc.sh
python3 scripts/check-release-status-doc.py
bash scripts/test-install-docs.sh
python3 scripts/check-install-docs.py
bash scripts/test-release-doc.sh
python3 scripts/check-release-doc.py
bash scripts/test-release-notes.sh
python3 scripts/check-release-notes.py

echo ">> release readiness verifier"
bash scripts/test-release-readiness.sh
bash scripts/test-release-evidence.sh

echo ">> maintainer surfaces"
bash scripts/test-maintainer-surfaces.sh
python3 scripts/check-maintainer-surfaces.py

echo ">> publish ref"
bash scripts/check-publish-ref.sh

echo ">> package file lists"
bash scripts/test-package-files.sh
CARGO="$CARGO_BIN" bash scripts/check-package-files.sh

echo ">> package gxfkit-core"
"$CARGO_BIN" package -p gxfkit-core "${package_args[@]}"

echo ">> package gxfkit"
package_log="$(mktemp)"
if "$CARGO_BIN" package -p gxfkit "${package_args[@]}" >"$package_log" 2>&1; then
  cat "$package_log"
  echo "gxfkit package verification passed"
elif grep -q "no matching package named \`gxfkit-core\` found" "$package_log"; then
  cat "$package_log" >&2
  rm -f "$package_log"
  cat >&2 <<'MSG'
gxfkit package verification did not complete.

This is expected before gxfkit-core has been published to the registry, because
the binary crate depends on gxfkit-core by version. Publish order is:
  1. cargo publish -p gxfkit-core
  2. wait for the registry index to update
  3. cargo publish -p gxfkit
MSG
else
  cat "$package_log" >&2
  rm -f "$package_log"
  exit 1
fi
rm -f "$package_log"

echo ">> release preflight complete"
