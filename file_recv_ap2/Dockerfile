# ---- Builder ----
FROM rust:slim-trixie AS builder
WORKDIR /app

# Copy only what's needed to compile
COPY Cargo.toml ./
# COPY Cargo.lock ./
COPY src ./src

# Build the real release binary
RUN cargo build --release

# ---- Runner ----
FROM debian:trixie-slim AS runner
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates tzdata curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Copy the compiled binary from the builder stage
COPY --from=builder /app/target/release/file-recv-api /usr/local/bin/file-recv-api

# Ensure the default saving path exists (root will own it)
RUN mkdir -p /saving_path

# Healthcheck helps catch regressions at runtime
HEALTHCHECK --interval=15s --timeout=3s --retries=5 \
  CMD curl -fsS http://127.0.0.1:7778/healthz || exit 1

ENV TIMEZONE="Asia/Shanghai" \
    SAVING_PATH="/saving_path" \
    PORT="7778" \
    RUST_LOG="info"
# API_PASSWD has no default for security.

EXPOSE 7778

# Run as root (default); no USER directive
ENTRYPOINT ["/usr/local/bin/file-recv-api"]

