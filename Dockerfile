FROM ubuntu:latest
USER nobody
ADD --chown=nobody:nobody ./app/ /app/
ADD --chown=nobody:nobody ./opt /opt
WORKDIR /app
EXPOSE 4049
ENTRYPOINT ["/app/bingo", "run_server"]