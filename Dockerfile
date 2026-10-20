FROM alpine/git:2.54.0

RUN apk add --no-cache bash && git --version