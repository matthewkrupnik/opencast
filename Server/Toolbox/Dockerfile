# Everything needed to provision and deploy the Server/ Workers without
# installing Node, Yarn or Rust on the host. Run it through
# scripts/server-toolbox.sh, which mounts the repository at /work.
FROM node:26-trixie

ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    PATH=/root/.cargo/bin:$PATH

# Yarn comes from the root package.json's packageManager pin.
RUN npm install -g corepack \
    && corepack enable \
    && corepack prepare yarn@4.18.1 --activate

# The Workers need Rust 1.91+ and the wasm target. The wrangler build command
# runs "$HOME/.cargo/bin/worker-build", so Cargo lives in /root/.cargo.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain stable --target wasm32-unknown-unknown \
    && cargo install --locked worker-build@0.8.7 \
    && rm -rf /root/.cargo/registry

WORKDIR /work
CMD ["bash"]
