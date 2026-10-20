# syntax=docker/dockerfile:1

# git 2.56.0 debs for Ubuntu 24.04 (noble), built on the git-core PPA packaging,
# because the PPA itself still publishes only 2.55.0. git 2.56.0 is the first
# release tolerating a stale multi-pack-index (see README).
# git-man is a hard Depends of git in this packaging, so it is dropped from git's
# dependency list; the git deb then installs standalone, and the git-man deb is
# shipped alongside for anyone who wants the man pages.
FROM buildpack-deps:noble-curl AS build

ARG GIT_VERSION=2.56.0
ARG PPA_GIT_VERSION=1:2.55.0-0ppa1~ubuntu24.04.2

RUN set -eux; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" -o /etc/apt/keyrings/git-core-ppa.asc; \
    echo "deb-src [signed-by=/etc/apt/keyrings/git-core-ppa.asc] http://ppa.launchpad.net/git-core/ppa/ubuntu noble main" > /etc/apt/sources.list.d/git-core-ppa.list; \
    apt-get update; \
    apt-get build-dep -y --no-install-recommends git

RUN set -eux; \
    mkdir /build; \
    cd /build; \
    apt-get source "git=${PPA_GIT_VERSION}"; \
    srcdir=$(ls -d */); \
    sed -i -e '/^ git-man (/d' -e 's/^\(Depends:.*liberror-perl\),$/\1/' "${srcdir}debian/control"; \
    if [ "${srcdir}" != "git-${GIT_VERSION}/" ]; then \
        curl -fsSLO "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"; \
        tar xzf "git-${GIT_VERSION}.tar.gz"; \
        cp -a "${srcdir}debian" "git-${GIT_VERSION}"; \
        ver=$(dpkg-parsechangelog -l"${srcdir}debian/changelog" -S Version); \
        suffix=${ver#*:}; \
        suffix=${suffix#*-}; \
        printf 'git (1:%s-%s) noble; urgency=medium\n\n  * New upstream release.\n\n -- Felipe Santos <felipecassiors@gmail.com>  Wed, 01 Oct 2025 12:00:00 +0000\n\n' \
            "${GIT_VERSION}" "${suffix}" \
            | cat - "git-${GIT_VERSION}/debian/changelog" > "git-${GIT_VERSION}/debian/changelog.new"; \
        mv "git-${GIT_VERSION}/debian/changelog.new" "git-${GIT_VERSION}/debian/changelog"; \
    fi; \
    cd "git-${GIT_VERSION}"; \
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us

FROM scratch
COPY --from=build /build/*.deb /debs/