FROM alpine/git:2.54.0 AS base

RUN apk add --no-cache bash && git --version

COPY reproduce.sh /scripts/reproduce.sh

FROM base AS repro

RUN REPRO_DATA_DIR=/tmp/repro bash /scripts/reproduce.sh && rm -rf /tmp/repro