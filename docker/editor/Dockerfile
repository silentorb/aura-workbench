# Derives from the workbench engine image (Rust + ALSA).
# Compose declares this via build.additional_contexts so `docker compose build` can
# build both services safely (Dev Containers builds engine+editor together).
ARG BASE_IMAGE=aura-workbench-engine:local
FROM ${BASE_IMAGE}

# System deps for Iced / winit / wgpu on Linux (WSLg X11 + Wayland).
RUN apt-get update -qq \
 && apt-get install -y -qq \
      libxkbcommon-dev \
      libxkbcommon-x11-0 \
      libwayland-dev \
      libx11-dev \
      libxcb1-dev \
      libxcb-render0-dev \
      libxcb-shape0-dev \
      libxcb-xfixes0-dev \
      libfontconfig1-dev \
      libfreetype6-dev \
      libexpat1-dev \
      libvulkan-dev \
      mesa-vulkan-drivers \
 && rm -rf /var/lib/apt/lists/*
