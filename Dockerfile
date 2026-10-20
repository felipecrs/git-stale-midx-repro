FROM alpine/git:2.54.0

RUN apk add --no-cache bash && git --version

COPY reproduce.sh /scripts/reproduce.sh

RUN REPRO_DATA_DIR=/tmp/repro bash /scripts/reproduce.sh && rm -rf /tmp/repro