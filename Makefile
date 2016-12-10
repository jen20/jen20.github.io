default: help

DOCKER_IMAGE ?= jekyll/jekyll:pages
DOCKER_VOLUME ?= $(shell pwd):/srv/jekyll
DOCKER_COMMAND ?= jekyll serve --watch --incremental

.PHONY: run
run: ## Run Jekyll in a container. Override DOCKER_IMAGE to change container image.
	docker run \
		-p 4000:4000 -t -i \
		-v "$(DOCKER_VOLUME)" \
		$(DOCKER_IMAGE) \
		$(DOCKER_COMMAND)


.PHONY: help
help:
	@echo "Valid targets:"
	@grep -E '^[a-zA-Z_-]+%*:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

