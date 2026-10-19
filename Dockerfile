# syntax=docker/dockerfile:1

FROM buildpack-deps:noble-curl AS build

ARG GIT_VERSION=2.55.0
ARG PACKAGING_VERSION=2.55.0-0ppa1~ubuntu24.04.2

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        dpkg-dev \
        debhelper \
        dh-exec \
        dh-apache2 \
        fakeroot \
        libz-dev \
        gettext \
        libpcre2-dev \
        libcurl4-gnutls-dev \
        libexpat1-dev \
        subversion \
        libsvn-perl \
        libyaml-perl \
        tcl \
        python3 \
        libhttp-date-perl \
        libcgi-pm-perl \
        liberror-perl \
        libmailtools-perl \
        cvs \
        cvsps \
        libdbd-sqlite3-perl \
        unzip \
        libio-pty-perl \
        cargo \
        rustc \
        asciidoc \
        xmlto \
        docbook-xsl; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    mkdir /build; \
    cd /build; \
    curl -fsSLO "https://mirrors.edge.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz"; \
    tar xzf "git-${GIT_VERSION}.tar.gz"; \
    curl -fsSLO "http://ppa.launchpad.net/git-core/ppa/ubuntu/pool/main/g/git/git_${PACKAGING_VERSION}.debian.tar.xz"; \
    echo "8012a174b5c65bd56b63199596def7949d87e09634a498c45cbedbef63595be7  git_${PACKAGING_VERSION}.debian.tar.xz" | sha256sum -c -; \
    tar xf "git_${PACKAGING_VERSION}.debian.tar.xz" -C "git-${GIT_VERSION}"; \
    cd "git-${GIT_VERSION}"; \
    if [ "$(dpkg-parsechangelog -S Version)" != "1:${GIT_VERSION}-0ppa1~ubuntu24.04.2" ]; then \
        printf 'git (1:%s-0ppa1~ubuntu24.04.2) noble; urgency=medium\n\n  * New upstream release.\n\n -- Felipe Santos <felipecassiors@gmail.com>  %s\n\n' \
            "${GIT_VERSION}" "$(date -R)" \
            | cat - debian/changelog > debian/changelog.new; \
        mv debian/changelog.new debian/changelog; \
    fi; \
    DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -b -uc -us

FROM buildpack-deps:noble-curl

RUN --mount=type=bind,from=build,source=/build,target=/tmp/debs \
    apt-get update; \
    apt-get install -y /tmp/debs/git_*.deb /tmp/debs/git-man_*.deb; \
    rm -rf /var/lib/apt/lists/*

RUN git --version