IMAGE ?= local-tracy-evaluation-control
NAME  ?= tracy-eval-1

.PHONY: help bootstrap build run watch exec stop

help:
	@echo "Targets:"
	@echo "  make bootstrap         clone tracy + evaluator into ./artifacts/"
	@echo "  make build             build the docker image ($(IMAGE))"
	@echo "  make run [NAME=<n>]    start container (default name: $(NAME))"
	@echo "  make watch [NAME=<n>]  follow container stdout (docker logs -f)"
	@echo "  make exec [NAME=<n>]   start (if exited) and bash into container"
	@echo "  make stop [NAME=<n>]   stop & remove container (default name: $(NAME))"

bootstrap:
	@echo "==> [bootstrap] running ./bootstrap.sh"
	./bootstrap.sh
	@echo "==> [bootstrap] done"

build:
	@echo "==> [build] building image: $(IMAGE)"
	docker build -t $(IMAGE) .
	@echo "==> [build] done: $(IMAGE)"

run:
	@echo "==> [run] starting container '$(NAME)' from image '$(IMAGE)'"
	docker run -d --name $(NAME) \
		--env-file .env \
		-v "$(CURDIR)/TASK.md:/home/coder/control/TASK.md:ro" \
		$(IMAGE)
	@echo "==> [run] container started: $(NAME)"
	@echo "    tail stdout:  make watch NAME=$(NAME)"
	@echo "    tail logfile: docker exec $(NAME) tail -f /home/coder/control/claude.log"
	@echo "    shell into:   docker exec -it $(NAME) bash"

watch:
	@echo "==> [watch] following stdout of container '$(NAME)' (Ctrl-C to stop)"
	docker logs -f $(NAME)

exec:
	@echo "==> [exec] starting (if stopped) and bash'ing into '$(NAME)'"
	docker start $(NAME) >/dev/null
	docker exec -it $(NAME) bash

stop:
	@echo "==> [stop] stopping & removing container '$(NAME)'"
	-docker rm -f $(NAME)
	@echo "==> [stop] done"
