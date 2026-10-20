ARG GO_VERSION=1.26.9

FROM python:3.14-slim-trixie AS downloads
ARG OPENCODE_VERSION=1.19.3
ARG DUCKDB_VERSION=1.5.6
ARG MILLER_VERSION=6.22.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /out \
    && curl -fsSL \
        "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
        -o /tmp/opencode.tar.gz \
    && tar -xzf /tmp/opencode.tar.gz -C /out opencode \
    && curl -fsSL \
        "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip" \
        -o /tmp/duckdb-cli.zip \
    && unzip -q /tmp/duckdb-cli.zip duckdb -d /out \
    && chmod +x /out/duckdb \
    && curl -fsSL \
        "https://github.com/johnkerl/miller/archive/refs/tags/v${MILLER_VERSION}.tar.gz" \
        -o /tmp/miller-source.tar.gz

FROM golang:${GO_VERSION}-alpine AS miller-build
ARG GO_VERSION
ENV GOTOOLCHAIN=local
ENV CGO_ENABLED=0
WORKDIR /src
COPY --from=downloads /tmp/miller-source.tar.gz /tmp/miller-source.tar.gz

RUN test "$(go env GOVERSION)" = "go${GO_VERSION}" \
    && tar -xzf /tmp/miller-source.tar.gz --strip-components=1 -C /src \
    && go build -trimpath -o /out/mlr ./cmd/mlr \
    && go version -m /out/mlr \
    && /out/mlr --version \
    && test "$(printf 'a,b\n1,2\n' | /out/mlr --csv put '$sum = $a + $b')" = "$(printf 'a,b,sum\n1,2,3')"

# Python 3.14 on Debian Trixie
FROM python:3.14-slim-trixie

# Install command-line analysis and debugging tools
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    ripgrep \
    jq \
    grep \
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
    procps \
    passwd \
    lsof \
    iproute2 \
    netcat-openbsd \
    musl \
    libstdc++6 \
    libgcc-s1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=downloads /out/opencode /out/duckdb /usr/local/bin/
COPY --from=miller-build /out/mlr /usr/local/bin/mlr

RUN groupadd --gid 1000 opencode \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash opencode \
    && mkdir -p /home/opencode/.cache /workspace \
    && chown -R opencode:opencode /home/opencode /workspace

ENV HOME=/home/opencode

RUN duckdb -c "INSTALL duckdb_mcp FROM community; LOAD duckdb_mcp;"

COPY duckdb-mcp.sql /home/opencode/.config/opencode/duckdb-mcp.sql

RUN opencode plugin --global opencode-betterglob@1.1.0 \
    && opencode plugin --global opencode-bettergrep@1.1.0 \
    && opencode plugin --global opencode-betterread@1.1.0 \
    && rm -rf /home/opencode/.npm/_cacache /home/opencode/.npm/_logs

# Dedicated Python analysis environment
ENV VIRTUAL_ENV=/opt/analysis-venv
ENV PATH="/opt/analysis-venv/bin:${PATH}"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_NO_CACHE_DIR=1

RUN python -m venv "$VIRTUAL_ENV"

# Install Python data-analysis dependencies
COPY analysis-requirements.txt /tmp/analysis-requirements.txt

RUN "$VIRTUAL_ENV/bin/python" -m pip install --only-binary=:all: \
    -r /tmp/analysis-requirements.txt \
    && "$VIRTUAL_ENV/bin/python" -m pip check \
    && rm /tmp/analysis-requirements.txt

RUN chown -R opencode:opencode /home/opencode

# Verify tools at build time
RUN command -v rg \
    && command -v jq \
    && command -v mlr \
    && mlr --version \
    && command -v duckdb \
    && duckdb --version \
    && ! command -v curl \
    && ! command -v git \
    && ! command -v gawk \
    && if dpkg-query -W -f='${binary:Package} ${db:Status-Status}\n' \
        | grep -E '^(curl|git|git-man|gawk|libcurl[^ ]*)(:[^ ]+)? installed$'; then exit 1; fi \
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