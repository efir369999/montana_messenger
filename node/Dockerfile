# Montana full node, built from this folder alone (the build context is node/).
#
#   docker compose up -d --build
#
# Builder: compiles montana-node from node/Code (the node subset of the Montana
# workspace). The BIP-39 wordlist is compiled in from node/Montana wordlist.txt,
# four directories above crates/mt-mnemonic/src, so both are copied in place.
# Runtime: the binary, tini and the entrypoint; no genesis manifest is baked in.

FROM rust:1.95-bookworm AS builder
WORKDIR /build
COPY Code /build/Code
COPY ["Montana wordlist.txt", "/build/Montana wordlist.txt"]
ENV CARGO_NET_RETRY=10 \
    CARGO_HTTP_MULTIPLEXING=false
WORKDIR /build/Code
RUN cargo build --release -j 1 -p montana-node && \
    strip target/release/montana-node && \
    ls -lh target/release/montana-node

FROM debian:trixie-slim
LABEL org.opencontainers.image.source="https://github.com/efir369999/montana_messenger" \
      quest.montana.source-commit="ae36d1f"
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates tini util-linux coreutils curl && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -r -m -d /var/lib/montana -s /usr/sbin/nologin montana && \
    mkdir -p /etc/montana && \
    chmod 0755 /etc/montana

COPY --from=builder /build/Code/target/release/montana-node /usr/local/bin/montana-node
COPY entrypoint.sh /usr/local/bin/montana-entrypoint
RUN chmod 0755 /usr/local/bin/montana-entrypoint

WORKDIR /var/lib/montana
VOLUME ["/var/lib/montana"]
EXPOSE 8444
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/montana-entrypoint"]
