FROM alpine:3.19

RUN apk add --no-cache \
    inotify-tools \
    redis \
    bash \
    grep \
    curl

COPY watch.sh /usr/local/bin/watch.sh
COPY sync_netpol.sh /usr/local/bin/sync_netpol.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x \
    /usr/local/bin/watch.sh \
    /usr/local/bin/sync_netpol.sh \
    /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
