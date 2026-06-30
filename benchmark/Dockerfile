# Reproducible benchmark image: AGAT (gold standard) + gxfkit, all
# in one Linux container so wall-clock comparisons are strictly apples-to-apples
# (no cross-OS / cross-filesystem confounders).
#
# Build from the REPO ROOT so the build stage can see the crates:
#   docker build -f benchmark/Dockerfile -t gxfkit-bench .

# --- Stage 1: build the Linux gxfkit release binary ---------------------------
FROM rust:1-slim AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY crates ./crates
RUN cargo build --release --bin gxfkit && strip target/release/gxfkit

# --- Stage 2: AGAT image + gxfkit ---------------------------------------
FROM quay.io/biocontainers/agat:1.7.0--pl5321hdfd78af_0
LABEL org.opencontainers.image.description="gxfkit vs AGAT benchmark harness"

COPY --from=build /src/target/release/gxfkit /usr/local/bin/gxfkit
COPY benchmark/bench.sh /usr/local/bin/bench.sh

# biocontainers images run as a non-root user by default; our scripts only read
# mounted data and write to /work, so that's fine.
WORKDIR /work
ENTRYPOINT ["bash", "/usr/local/bin/bench.sh"]
