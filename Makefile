.PHONY: up down ps logs smoke clean example-mine example-mine-stop install upgrade uninstall status endpoints upload-build generate-data copy-build unity-demo check-secrets helm-smoke lint

# ---------------------------------------------------------------------------
# Docker Compose deployment (local development and CI): deploy/compose/
# ---------------------------------------------------------------------------
COMPOSE_BASE := docker compose -f deploy/compose/docker-compose.yml
# Once `make example-mine` has run, every compose command also loads the mine
# overlay, so `down` stops its simulator and `up` keeps its Grafana dashboard.
# `make clean` forgets it.
MINE_MARKER  := deploy/compose/.example-mine
MINE_COMPOSE := examples/mine/compose.yml
COMPOSE := $(COMPOSE_BASE)$(if $(wildcard $(MINE_MARKER)), -f $(MINE_COMPOSE))

## Start the whole platform with Docker Compose (first run: generates credentials)
up:
	@bash scripts/compose-env.sh
	@bash scripts/compose-preflight.sh
	$(COMPOSE) up -d --build --wait --wait-timeout 900
	@# `--wait` does not wait for one-shot jobs to finish: a running init counts
	@# as up. Wait for it to exit, then check how.
	@test "$$(docker wait $$($(COMPOSE) ps -a -q init))" = 0 || { \
	  echo "ERROR: the init job (policy + Ditto connections) failed:"; $(COMPOSE) logs init; exit 1; }
	@bash scripts/compose-wait-ready.sh
	@bash scripts/compose-urls.sh

## Stop the platform, keep data
down:
	$(COMPOSE) down

## Show compose service status
ps:
	@$(COMPOSE) ps -a

## Follow logs (one service: make logs S=gateway)
logs:
	$(COMPOSE) logs -f --tail=100 $(S)

## End-to-end check of the running compose stack
smoke:
	@bash scripts/compose-smoke.sh

## Run the Example Mine (twins + haul-cycle simulator + Grafana dashboard) on the compose stack
example-mine: up
	$(COMPOSE_BASE) -f $(MINE_COMPOSE) up -d --build --wait --wait-timeout 300
	@touch $(MINE_MARKER)
	@echo "Example Mine running: Grafana -> Dashboards -> OpenEgiz Examples -> Example Mine"

## Stop the Example Mine simulator (twins and data stay)
example-mine-stop:
	$(COMPOSE_BASE) -f $(MINE_COMPOSE) stop mine-simulator

## Stop the platform and DELETE all its data and credentials
clean:
	$(COMPOSE) down -v --remove-orphans
	rm -f deploy/compose/.env $(MINE_MARKER)

# ---------------------------------------------------------------------------
# Helm v3 deployment (Kubernetes): charts/openegiz
# ---------------------------------------------------------------------------
RELEASE_NAME ?= openegiz
NAMESPACE    ?= openegiz
CHART_PATH   := charts/openegiz

# Credentials live OUTSIDE this repo. values.yaml leaves all credentials empty
# so installs fail fast unless either SECRETS_FILE or EXISTING_SECRET is set.
SECRETS_FILE    ?= $(HOME)/openegiz-deploy/secrets.values.yaml
EXISTING_SECRET ?=
HELM_VALUES     ?=

HELM_CRED_ARGS = $(if $(EXISTING_SECRET),--set credentials.existingSecret=$(EXISTING_SECRET),-f "$(SECRETS_FILE)")

check-secrets:
	@if [ -z "$(EXISTING_SECRET)" ] && [ ! -f "$(SECRETS_FILE)" ]; then \
	  echo "ERROR: secrets override not found: $(SECRETS_FILE)"; \
	  echo "       Create it from charts/openegiz/secrets.values.yaml.example, or pass:"; \
	  echo "       make install SECRETS_FILE=/path/to/file"; \
	  echo "       make install EXISTING_SECRET=<k8s-secret-name>"; \
	  exit 1; \
	fi

## Install the OpenEgiz Helm v3 chart (override RELEASE_NAME, NAMESPACE, HELM_VALUES)
install: check-secrets
	helm install $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) --create-namespace $(HELM_VALUES) $(HELM_CRED_ARGS) --wait --timeout=15m

## Upgrade the OpenEgiz Helm v3 chart
upgrade: check-secrets
	helm upgrade --install $(RELEASE_NAME) $(CHART_PATH) -n $(NAMESPACE) --create-namespace $(HELM_VALUES) $(HELM_CRED_ARGS) --wait --timeout=15m

## Uninstall the OpenEgiz Helm v3 chart
uninstall:
	helm uninstall $(RELEASE_NAME) -n $(NAMESPACE) --wait

## Show pod statuses for the Helm release
status:
	@kubectl get pods -n $(NAMESPACE) -l app.kubernetes.io/instance=$(RELEASE_NAME) -o wide

## Show Service and Ingress endpoints for the Helm release
endpoints:
	@RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) bash scripts/show-endpoints.sh

## Upload 3D Scene WebGL build files to the persistent scene-server pod
upload-build:
	@NAMESPACE=$(NAMESPACE) bash scripts/upload-build.sh $(RELEASE_NAME)

## End-to-end black-box smoke check against a running Helm release
helm-smoke:
	@RELEASE_NAME=$(RELEASE_NAME) NAMESPACE=$(NAMESPACE) bash scripts/helm-smoke.sh

## Oven demo: create the oven twins, then stream telemetry (Ctrl+C to stop).
## Compose by default; against Helm use port-forward or Ingress (DITTO_URL, MQTT_PORT, DITTO_PASSWORD).
generate-data:
	@bash scripts/demo-oven.sh

## Download the demo Unity WebGL scene (88 MB, kept out of git) into ./build/
unity-demo:
	@bash scripts/unity-demo.sh

## Copy 4 Unity WebGL build files from SRC into ./build/
## Usage: make copy-build SRC=/path/to/source
copy-build:
	@bash scripts/copy-build.sh $(SRC)

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

## Static checks, same as the CI lint job: run before pushing
.PHONY: lint
lint:
	@bash scripts/helm-lint.sh
	git ls-files -z '*.sh' | xargs -0 -n1 bash -n
	git ls-files -z 'scripts/*.sh' 'deploy/*.sh' | xargs -0 shellcheck --severity=warning
	git ls-files -z '*.py' | xargs -0 python3 -c 'import ast, sys; [ast.parse(open(f, encoding="utf-8").read(), f) for f in sys.argv[1:]]'
	@# Repository hygiene: no banned lab/course identifiers or stray legacy naming.
	@python3 scripts/repo-hygiene.py
	# Plugin Bundle: shipped zips reproduce from upstream and every pinned
	# plugin chunk matches its SRI digest (packaging/grafana-plugins/verify_bundle.py).
	python3 packaging/grafana-plugins/verify_bundle.py
	@bash scripts/compose-env.sh
	docker compose -f deploy/compose/docker-compose.yml config -q
	@# Every compose image must be pinned to an exact x.y.z version (no
	@# :latest, no floating major.minor tags).
	@bash scripts/compose-pinned-images.sh
	@# Extended API (services/extended-api/): TypeScript must compile and its
	@# stack-independent unit tests (auth middleware) must pass. Needs node/yarn.
	command -v node >/dev/null || { echo "ERROR: lint: node is required to check services/extended-api"; exit 1; }
	@[ -x services/extended-api/node_modules/.bin/tsc ] || (cd services/extended-api && yarn install --frozen-lockfile)
	cd services/extended-api && yarn lint
	@echo "lint: ok"
