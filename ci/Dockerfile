# CI image: the pinned headless toolchain (toolchain.toml) plus its runtime
# libraries, so CI jobs skip apt and AppImage downloads entirely.
#
# Built by the `image` job in .github/workflows/ci.yml, tagged with a hash of
# this file + toolchain.toml (`scad-tools toolchain image-ref`), and only
# rebuilt when either changes. The build context is a directory holding the
# `scad-tools toolchain install --prefix <context>/toolchain` output.
ARG BASE=ubuntu:24.04
FROM ${BASE}

ENV DEBIAN_FRONTEND=noninteractive
# git/ca-certificates: checkout + profile fetch. python3: scad-tools.
# gcc/libc6-dev/python3-dev: uv builds the tree-sitter-openscad git dep.
# libegl1/libgl1/libopengl0 (+ libsm6/libice6 for its Qt): OpenSCAD offscreen previews.
# libwebkit2gtk-4.1-0: OrcaSlicer links its GTK/WebKit GUI stack even for
# CLI slicing; this pulls in GTK, GStreamer, etc. as dependencies.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates git python3 gcc libc6-dev python3-dev \
      libegl1 libgl1 libopengl0 libsm6 libice6 \
      libwebkit2gtk-4.1-0 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/
COPY toolchain/ /opt/toolchain/

ENV PATH=/opt/toolchain/bin:$PATH \
    UV_PYTHON_PREFERENCE=only-system \
    UV_LINK_MODE=copy
