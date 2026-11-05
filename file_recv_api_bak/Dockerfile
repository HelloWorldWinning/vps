# ---- Builder ----
FROM rust:slim-trixie AS builder
WORKDIR /app

# Copy manifests first (leverages caching for dependencies)
COPY Cargo.toml ./
# COPY Cargo.lock ./        # uncomment if you have a lockfile

# Copy source and build
COPY src ./src
RUN cargo build --release

# ---- Runner ----
FROM debian:trixie-slim AS runner
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Copy the compiled binary
COPY --from=builder /app/target/release/file-recv-api /usr/local/bin/file-recv-api

# Defaults (overridable in compose)
ENV TIMEZONE="Asia/Shanghai" \
    SAVING_PATH="/saving_path" \
    PORT="7778" \
    RUST_LOG="info"
# API_PASSWD is intentionally not given a default for security.

EXPOSE 7778
ENTRYPOINT ["/usr/local/bin/file-recv-api"]

