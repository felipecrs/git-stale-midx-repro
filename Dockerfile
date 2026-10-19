FROM buildpack-deps:noble-scm AS build

ARG GIT_VERSION=2.55.0

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        libcurl4-openssl-dev \
        libssl-dev \
        zlib1g-dev; \
    cd /tmp; \
    curl -fsSLO "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"; \
    tar xzf "git-${GIT_VERSION}.tar.gz"; \
    cd "git-${GIT_VERSION}"; \
    make -j"$(nproc)" NO_GETTEXT=1 NO_TCLTK=1 NO_EXPAT=1 NO_RUST=1 all; \
    make NO_GETTEXT=1 NO_TCLTK=1 NO_EXPAT=1 NO_RUST=1 prefix=/opt/git install

FROM buildpack-deps:noble-scm

COPY --from=build /opt/git /opt/git
ENV PATH="/opt/git/bin:${PATH}"

RUN git --version