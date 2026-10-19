
# Official OpenCode release
ARG OPENCODE_VERSION=1.19.3
FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}

# Install command-line analysis and debugging tools
RUN apk add --no-cache \
    bash \
    ca-certificates \
    ripgrep \
    jq \
    grep \
    gawk \
    sed \
    findutils \
    coreutils \
    diffutils \
    file \
    less \
    miller \
    python3 \
    py3-pip \
    tar \
    gzip \
    xz \
    zip \
    unzip \
    curl \
    procps-ng \
    lsof \
    iproute2 \
    netcat-openbsd \
    git

# Dedicated Python analysis environment
ENV VIRTUAL_ENV=/opt/analysis-venv
ENV PATH="/opt/analysis-venv/bin:${PATH}"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN python3 -m venv "$VIRTUAL_ENV"

# Install Python data-analysis dependencies
COPY analysis-requirements.txt /tmp/analysis-requirements.txt

RUN python3 -m pip install --only-binary=:all: \
    -r /tmp/analysis-requirements.txt \
    && python3 -m pip check \
    && rm /tmp/analysis-requirements.txt

# Verify tools at build time
RUN command -v rg \
    && command -v jq \
    && command -v mlr \
    && command -v git \
    && command -v python3 \
    && python3 -c \
      "import pandas, numpy, duckdb, pyarrow, scipy, tabulate"

WORKDIR /workspace

# Keep the official OpenCode ENTRYPOINT
