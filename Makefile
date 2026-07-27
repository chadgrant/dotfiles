.PHONY: test test-shell

# Interactive container for exercising setup.sh by hand.
test:
	docker build -t setup-test .
	docker run --rm -it setup-test

# Verifies the zsh config loads and the Infisical fragment behaves.
# Hermetic — a stub CLI stands in for infisical, so no credentials or network.
test-shell:
	docker build -f test/Dockerfile -t dotfiles-shell-test .
	docker run --rm dotfiles-shell-test
