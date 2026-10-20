# syntax=docker/dockerfile:1

FROM buildpack-deps:noble-curl AS build

ARG GIT_VERSION=2.55.0

RUN set -eux; \
    apt-get update; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" -o /etc/apt/keyrings/git-core-ppa.asc; \
    echo "deb-src [signed-by=/etc/apt/keyrings/git-core-ppa.asc] http://ppa.launchpad.net/git-core/ppa/ubuntu noble main" > /etc/apt/sources.list.d/git-core-ppa.list; \
    apt-get update; \
    apt-get build-dep -y git; \
    mkdir /build; \
    cd /build; \
    apt-get source git; \
    srcdir=$(ls -d */); \
    if [ "${srcdir}" != "git-${GIT_VERSION}/" ]; then \
        curl -fsSLO "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"; \
        tar xzf "git-${GIT_VERSION}.tar.gz"; \
        cp -a "${srcdir}debian" "git-${GIT_VERSION}"; \
        ver=$(cd "${srcdir}" && dpkg-parsechangelog -S Version); \
        suffix=${ver#*:}; \
        suffix=${suffix#*-}; \
        printf 'git (1:%s-%s) noble; urgency=medium\n\n  * New upstream release.\n\n -- Felipe Santos <felipecassiors@gmail.com>  %s\n\n' \
            "${GIT_VERSION}" "${suffix}" "$(date -R)" \
            | cat - "git-${GIT_VERSION}/debian/changelog" > "git-${GIT_VERSION}/debian/changelog.new"; \
        mv "git-${GIT_VERSION}/debian/changelog.new" "git-${GIT_VERSION}/debian/changelog"; \
    fi; \
    cd "git-${GIT_VERSION}"; \
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us

FROM buildpack-deps:noble-curl

ARG GIT_VERSION=2.55.0

RUN --mount=type=bind,from=build,source=/build,target=/tmp/debs \
    apt-get update; \
    apt-get install -y /tmp/debs/git_*.deb /tmp/debs/git-man_*.deb; \
    rm -rf /var/lib/apt/lists/*; \
    git --version | tee /dev/stderr | grep -q "git version ${GIT_VERSION}"