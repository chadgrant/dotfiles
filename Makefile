
test:
	docker build -t setup-test .
	docker run --rm -it setup-test