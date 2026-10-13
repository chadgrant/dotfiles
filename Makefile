.PHONY: test test-shell test-container test-init

# Interactive container for exercising setup.sh by hand.
test:
	docker build -t setup-test .
	docker run --rm -it setup-test

# Verifies the zsh config loads and the Infisical fragment behaves.
# Hermetic — a stub CLI stands in for infisical, so no credentials or network.
test-shell:
	docker build -f test/Dockerfile -t dotfiles-shell-test .
	docker run --rm dotfiles-shell-test

# Proves the two container entry points: builds the image a Remote AI Docker
# session would get (setup.sh --container), then starts a shell in it as an
# arbitrary uid with HOME on an empty tmpfs (container-init.sh, then zsh -i),
# once linking ~/.zshrc and once with a ZDOTDIR, as Remote AI passes when HOME
# is the server's own. Fails if shell start writes anything to stderr. The
# last line of output of each run on success is "zsh direnv infisical jq ok".
test-container:
	docker build -f test/container.Dockerfile -t dotfiles-container-test .
	docker run --rm --user 1000:1000 -e HOME=/home/u --tmpfs /home/u:mode=1777 dotfiles-container-test
	docker run --rm --user 1000:1000 -e HOME=/home/u -e ZDOTDIR=/home/u/.zdot --tmpfs /home/u:mode=1777 dotfiles-container-test

# container-init.sh against empty, already-initialised and bind-mounted homes.
# Plain bash, no Docker.
test-init:
	bash test/container-init-test.sh
