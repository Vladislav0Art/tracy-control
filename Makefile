IMAGE ?= local-tracy-evaluation-control
NAME  ?= tracy-eval

.PHONY: help bootstrap build run

help:
	@echo "Targets:"
	@echo "  make bootstrap         clone tracy + evaluator into ./artifacts/"
	@echo "  make build             build the docker image ($(IMAGE))"
	@echo "  make run [NAME=<n>]    start container (default name: $(NAME))"

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
		-v "$(CURDIR)/TASK.md:/root/control/TASK.md:ro" \
		-v "$(CURDIR)/claude_settings.json:/root/.claude/settings.json:ro" \
		$(IMAGE)
	@echo "==> [run] container started: $(NAME)"
	@echo "    tail stdout:  docker logs -f $(NAME)"
	@echo "    tail logfile: docker exec $(NAME) tail -f /root/control/claude.log"
	@echo "    shell into:   docker exec -it $(NAME) bash"
