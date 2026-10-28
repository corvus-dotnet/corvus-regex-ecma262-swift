# The Swift benchmark harness as an image: this package's tools (the data-set runner and the harness, over the C
# library from its release archive, installed where pkg-config finds it) and Node 24 for the V8 rows, with
# tools/bench/run.sh as the entry point. Built from the repository's root:
#
#   docker build -t corvus-regex-ecma262-swift .
#   docker run --rm -v <workloads.json>:/workloads.json:ro -v <texts dir>:/texts:ro -v <out dir>:/out <image>
#
# which writes /out/industry.json, the run's data file in the results page's shape. The ECMA-262 test data is cloned
# at depth 1 inside the container unless its data/ directory is mounted at /data. JOB=short, SECONDS_EACH, PASSES,
# CORES, SETTLE and RUN_URL pass through (see tools/bench/run.sh). The central benchmark site runs this image each
# night; .github/workflows/harness-image.yml builds, smoke-runs and publishes it.
FROM node:24.22.1-bookworm-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205 AS node

FROM swift:6.4@sha256:6fbd5978b56a5a9ff05a48f8f678079fc45be496ecda15b4e74e8944fab857be
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config python3 git util-linux ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
# The C library: the release's archive for the architecture being built, checked against its hash.
ARG CRE_VERSION=0.2.3
ARG CRE_SHA256_X86_64=db46cccb38fde30e6c42e170ce414589bed1211b8bd0b14700468c072e155c58
ARG CRE_SHA256_AARCH64=34bc6162d468fa70a449f84a5376ba285d246b2a31f3c07247e31a845290c36b
RUN case "$(uname -m)" in x86_64) arch=x86_64 sum=$CRE_SHA256_X86_64 ;; aarch64) arch=aarch64 sum=$CRE_SHA256_AARCH64 ;; \
        *) echo "no archive of the C library is pinned for $(uname -m)"; exit 1 ;; esac \
    && curl -sSfL -o /tmp/cre.tar.gz "https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/releases/download/v${CRE_VERSION}/corvus-regex-ecma262-${CRE_VERSION}-$arch-unknown-linux-gnu.tar.gz" \
    && echo "$sum  /tmp/cre.tar.gz" | sha256sum -c - \
    && mkdir -p /opt/cre && tar -xzf /tmp/cre.tar.gz -C /opt/cre --strip-components 1 && rm /tmp/cre.tar.gz
ENV PKG_CONFIG_PATH=/opt/cre/lib/pkgconfig LD_LIBRARY_PATH=/opt/cre/lib
# The tools find the package by its path, and Swift names a package by its directory.
WORKDIR /corvus-regex-ecma262-swift
COPY . .
RUN (cd tools/dataset && swift build -c release -j 4) && (cd tools/bench && swift build -c release -j 4)
# The commit the image is built from, for the run's record (the image has no .git).
ARG COMMIT=""
ENV CORVUS_COMMIT=$COMMIT
ENTRYPOINT ["/corvus-regex-ecma262-swift/tools/bench/container-entry.sh"]
