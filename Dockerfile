
# Official OpenCode release
FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim
ARG OPENCODE_VERSION=1.19.3
ARG DUCKDB_VERSION=1.5.6
ARG MILLER_VERSION=6.22.0

# Install command-line analysis and debugging tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
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
    tar \
    gzip \
    xz-utils \
    zip \
    unzip \
    curl \
    procps \
    passwd \
    lsof \
    iproute2 \
    netcat-openbsd \
    git \
    musl \
    libstdc++6 \
    libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
    "https://github.com/johnkerl/miller/releases/download/v${MILLER_VERSION}/miller-${MILLER_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/miller.tar.gz \
    && tar -xzf /tmp/miller.tar.gz -C /tmp \
    && install -m 0755 "/tmp/miller-${MILLER_VERSION}-linux-amd64/mlr" /usr/local/bin/mlr \
    && rm -rf /tmp/miller.tar.gz "/tmp/miller-${MILLER_VERSION}-linux-amd64" \
    && mlr --version

RUN groupadd --gid 1000 opencode \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash opencode \
    && mkdir -p /home/opencode/.cache /workspace \
    && chown -R opencode:opencode /home/opencode /workspace

ENV HOME=/home/opencode

RUN curl -fsSL \
    "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
    | tar -xz -C /usr/local/bin opencode

RUN curl -fsSL \
    "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip" \
    -o /tmp/duckdb-cli.zip \
    && unzip -q /tmp/duckdb-cli.zip duckdb -d /usr/local/bin \
    && chmod +x /usr/local/bin/duckdb \
    && rm /tmp/duckdb-cli.zip \
    && duckdb --version

RUN duckdb -c "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;"

COPY duckdb-mcp.sql /home/opencode/.config/opencode/duckdb-mcp.sql

RUN opencode plugin --global opencode-betterglob@1.1.0 \
    && opencode plugin --global opencode-bettergrep@1.1.0 \
    && opencode plugin --global opencode-betterread@1.1.0

# Dedicated Python analysis environment
ENV VIRTUAL_ENV=/opt/analysis-venv
ENV PATH="/opt/analysis-venv/bin:${PATH}"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN uv venv "$VIRTUAL_ENV"

# Install Python data-analysis dependencies
COPY analysis-requirements.txt /tmp/analysis-requirements.txt

RUN uv pip install --python "$VIRTUAL_ENV/bin/python" --only-binary=:all: \
    -r /tmp/analysis-requirements.txt \
    && uv pip check --python "$VIRTUAL_ENV/bin/python" \
    && rm /tmp/analysis-requirements.txt

RUN chown -R opencode:opencode /home/opencode

# Verify tools at build time
RUN command -v rg \
    && command -v jq \
    && command -v mlr \
    && mlr --version \
    && command -v duckdb \
    && command -v git \
    && command -v python \
    && "$VIRTUAL_ENV/bin/python" -c \
            "import pandas, numpy, pyarrow, scipy, tabulate"

WORKDIR /workspace
USER opencode

RUN test "$(id -u)" -ne 0 \
    && opencode --version \
    && duckdb -c "SELECT 42 AS answer" \
    && opencode mcp list

ENTRYPOINT ["opencode"]
CMD []
