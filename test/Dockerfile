# Verifies the zsh config loads and that the Infisical fragment behaves.
# Hermetic: a stub CLI stands in for infisical, so no credentials, no network,
# and no dependence on a live vault.
#
#   docker build -f test/Dockerfile -t dotfiles-shell-test .
#   docker run --rm dotfiles-shell-test
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends zsh jq ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/zsh tester

# Ahead of /usr/bin so the stub wins; dropping it from PATH simulates a machine
# where the CLI was never installed.
COPY test/stub/infisical /opt/stub/infisical
RUN chmod 0755 /opt/stub/infisical
ENV PATH="/opt/stub:${PATH}"

COPY test/secrets.json /opt/test/secrets.json

COPY zshrc /opt/dotfiles/zshrc
COPY zsh /opt/dotfiles/zsh
COPY test/shell-test.zsh /opt/test/shell-test.zsh

# Run unprivileged: root would mask permission mistakes on the cache.
USER tester
WORKDIR /home/tester

CMD ["zsh", "/opt/test/shell-test.zsh"]
