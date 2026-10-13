# The image a Remote AI Docker session gets when this repo is its dotfiles:
# the stock base image, the repo at /opt/dotfiles, and `setup.sh --container`
# run as root at build time. `make test-container` builds it and starts a
# shell in it the way a session does.
FROM node:22-bookworm-slim

COPY . /opt/dotfiles
RUN /opt/dotfiles/setup.sh --container

CMD ["/opt/dotfiles/test/container-test.sh"]
