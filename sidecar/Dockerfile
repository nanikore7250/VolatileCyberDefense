FROM alpine:3.19

RUN apk add --no-cache \
    inotify-tools \
    redis \
    bash \
    grep

COPY watch.sh /usr/local/bin/watch.sh
RUN chmod +x /usr/local/bin/watch.sh

ENTRYPOINT ["/usr/local/bin/watch.sh"]
