# syntax=docker/dockerfile:1.7
# Reproducible release build environment for Montana node.
# Pin everything: base image digest, system dependency versions,
# Rust toolchain via rust-toolchain.toml.
#
# Two independent builds from the same source tree must produce
# byte-identical SHA-256 hashes for release binaries (m1_mnemonic,
# m1_crypto). This is enforced by the reproducible_release CI job
# which runs the build twice (--no-cache for the second run) and
# compares release_hashes.txt byte-for-byte.
#
# spec, [C-6] requirement #4 (Reproducible builds)

FROM debian:bookworm-slim@sha256:40b107342c492725bc7aacbe93a49945445191ae364184a6d24fedb28172f6f7

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        perl \
        pkg-config \
        git \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl -sSf https://sh.rustup.rs \
        -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y --default-toolchain none --no-modify-path \
    && rm /tmp/rustup-init.sh

WORKDIR /build

COPY . /build/

RUN rustup toolchain install "$(grep '^channel' rust-toolchain.toml | cut -d'"' -f2)" \
    && rustup component add rustfmt clippy

RUN cargo build --all --release

RUN cargo build --release -p mt-examples

RUN cargo test --all --release

RUN sha256sum target/release/examples/m1_mnemonic > /build/release_hashes.txt \
    && sha256sum target/release/examples/m1_crypto >> /build/release_hashes.txt \
    && cat /build/release_hashes.txt
