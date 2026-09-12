# Derives from the workbench engine image (Rust + ALSA).
# Compose declares this via build.additional_contexts so `docker compose build` can
# build engine + this service safely (same pattern as the Linux editor image).
ARG BASE_IMAGE=aura-workbench-engine:local
FROM ${BASE_IMAGE}

# clang/llvm for cargo-xwin (clang-cl + lld-link); ninja for cmake-rs crates.
USER root
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      clang \
      llvm \
      lld \
      ninja-build \
 && rm -rf /var/lib/apt/lists/*

USER vscode
RUN rustup target add x86_64-pc-windows-msvc \
 && rustup component add llvm-tools-preview \
 && cargo install --locked cargo-xwin \
 && cargo xwin cache xwin
