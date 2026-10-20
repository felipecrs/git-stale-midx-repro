# syntax=docker/dockerfile:1

FROM buildpack-deps:noble-curl AS build

ARG GIT_VERSION=2.55.0

RUN set -eux; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" -o /etc/apt/keyrings/git-core-ppa.asc; \
    echo "deb-src [signed-by=/etc/apt/keyrings/git-core-ppa.asc] http://ppa.launchpad.net/git-core/ppa/ubuntu noble main" > /etc/apt/sources.list.d/git-core-ppa.list; \
    apt-get update; \
    apt-get build-dep -y --no-install-recommends git

RUN set -eux; \
    mkdir /build; \
    cd /build; \
    apt-get source git=1:2.55.0-0ppa1~ubuntu24.04.2; \
    srcdir=$(ls -d */); \
    sed -i -e '/^ git-man (>>/d' -e 's/^\(Depends:.*liberror-perl\),$/\1/' "${srcdir}debian/control"; \
    if [ "${srcdir}" != "git-${GIT_VERSION}/" ]; then \
        curl -fsSLO "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"; \
        tar xzf "git-${GIT_VERSION}.tar.gz"; \
        cp -a "${srcdir}debian" "git-${GIT_VERSION}"; \
        ver=$(dpkg-parsechangelog -l"${srcdir}debian/changelog" -S Version); \
        suffix=${ver#*:}; \
        suffix=${suffix#*-}; \
        printf 'git (1:%s-%s) noble; urgency=medium\n\n  * New upstream release.\n\n -- Felipe Santos <felipecassiors@gmail.com>  %s\n\n' \
            "${GIT_VERSION}" "${suffix}" "$(date -R)" \
            | cat - "git-${GIT_VERSION}/debian/changelog" > "git-${GIT_VERSION}/debian/changelog.new"; \
        mv "git-${GIT_VERSION}/debian/changelog.new" "git-${GIT_VERSION}/debian/changelog"; \
    fi; \
    cd "git-${GIT_VERSION}"; \
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -B -uc -us

FROM buildpack-deps:noble-curl

ARG GIT_VERSION=2.55.0

RUN --mount=type=bind,from=build,source=/build,target=/tmp/debs \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/debs/git_*.deb; \
    rm -rf /var/lib/apt/lists/*; \
    git --version | tee /dev/stderr | grep -q "git version ${GIT_VERSION}"