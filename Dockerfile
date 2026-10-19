FROM buildpack-deps:noble-scm

RUN set -eux; \
    mkdir -p /etc/apt/keyrings; \
    curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217" -o /etc/apt/keyrings/git-core-ppa.asc; \
    echo "deb [signed-by=/etc/apt/keyrings/git-core-ppa.asc] http://ppa.launchpad.net/git-core/ppa/ubuntu noble main" > /etc/apt/sources.list.d/git-core-ppa.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends git; \
    git --version