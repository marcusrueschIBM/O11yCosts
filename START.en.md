[Deutsch](START.md) | **English**

# Start Guide: Stack, Containers, URLs and Ports

Runs with **Docker** or **Podman** on Linux, macOS and Windows (via WSL2 only). So far only macOS (Apple Silicon) with Podman 6.1.1 and Docker Compose 5.5.1 as the provider has been tested. The first-time Podman installation is described in `OTel_Astronomy_Shop_Installation_Mac_Podman.pdf`. This file is the short version for daily use.

All commands run in the **repo root** (where `setup.sh`, `stack.sh` and `config.sh` live).

---

## 1. One-time: Setup

```bash
./setup.sh
```

Clones the upstream demo into `opentelemetry-demo/` (pinned to commit `fdbd62ca`), lays the lab files on top and activates the baseline configuration. Safe to run multiple times.

If the Podman machine is not running (macOS and Windows with Podman only):

```bash
podman machine list
podman machine start podman-machine-default   # only if not "Currently running"
```

Do not run `podman machine init` again if the machine already exists.

---

## 2. Start, stop and check the stack

```bash
./stack.sh up              # shop + observability + MCP advisor
./stack.sh up --no-mcp     # without MCP (phases 1-4 of GUIDE.en.md)
./stack.sh down            # stop and remove containers (volumes are kept)
./stack.sh status          # check containers and URLs
./stack.sh check           # show collector errors (Kafka noise hidden)
./stack.sh logs <service>  # e.g. otel-collector
./stack.sh engine          # detected engine (docker or podman)
```

Force an engine: `CONTAINER_ENGINE=podman ./stack.sh up`.

Important:
- Startup takes about 1–2 minutes because `frontend` only starts after several dependencies.
- A changed collector configuration only takes effect after `./stack.sh up` (force-recreate).
- `stack.sh` always uses `compose.yaml`, `compose.observability.yaml`, `compose.extras.yaml` and `compose.lab.yaml`, plus `compose.mcp.yaml` when MCP is enabled. `compose.yaml` alone starts neither Jaeger nor Prometheus nor Grafana.

### Contents of `compose.lab.yaml`

File: `overlay/compose.lab.yaml` (copied to `opentelemetry-demo/`).

```yaml
services:
  grafana:
    deploy: {resources: {limits: {memory: 512M}}}
  checkout:
    deploy: {resources: {limits: {memory: 128M}}}
  product-catalog:
    deploy: {resources: {limits: {memory: 128M}}}
  recommendation:
    healthcheck:
      test: ["CMD-SHELL", "bash -c '</dev/tcp/127.0.0.1/${RECOMMENDATION_PORT}'"]
```

The `recommendation` entry replaces the healthcheck `nc -z ...`. The current `latest-recommendation` image does not contain `nc`. Without this change `recommendation` stays `unhealthy` permanently, and `frontend`, `frontend-proxy` and `load-generator` stay in the `Created` state. The shop is then unreachable.

---

## 3. Switch the sampling variant

```bash
./config.sh list           # baseline, head-50, head-10, tail, ai-policy
./config.sh show           # which variant is active on disk?
./config.sh use tail       # activate a variant
./stack.sh up              # only now does the collector pick it up
```

A variant only takes effect after `./stack.sh up`. `config.sh show` only checks the file, not the running collector.

---

## 4. URLs and fixed ports

| Component | Address | Host port |
|---|---|---|
| Astronomy Shop | http://localhost:8080/ | 8080 |
| Jaeger | http://localhost:8080/jaeger/ui/ | 8080 |
| Grafana | http://localhost:8080/grafana/ | 8080 |
| Load Generator (Locust) | http://localhost:8080/loadgen/ | 8080 |
| Feature Flags | http://localhost:8080/feature | 8080 |
| Prometheus | http://localhost:9090/ | 9090 |
| MCP Sampling Advisor | http://localhost:8000/mcp | 8000 |
| Envoy admin of the frontend proxy | – | 10000 |

Shop, Jaeger, Grafana, Load Generator and Feature Flags are all served through the frontend proxy on port 8080. All other containers (e.g. `grafana`, `jaeger`, `cart`) get dynamic host ports from Podman. Open Grafana and Jaeger only via the addresses above, not via the dynamic ports shown by `podman ps`.

---

## 5. Containers (26 in total)

| Group | Containers |
|---|---|
| Entry points | `frontend-proxy`, `frontend`, `load-generator` |
| Shop services | `ad`, `cart`, `checkout`, `currency`, `email`, `image-provider`, `payment`, `product-catalog`, `quote`, `recommendation`, `shipping` |
| Feature flags | `flagd`, `flagd-ui` |
| Databases | `astronomy-db` (PostgreSQL), `valkey-cart`, `opensearch` |
| Telemetry | `otel-collector`, `jaeger`, `prometheus`, `grafana` |
| Helper services | `opamp-server`, `telemetry-docs` |
| MCP (only with `compose.mcp.yaml`) | `otel-demo-mcp-sampling-advisor-1` |

Without MCP there are 25 containers.

---

## 6. Check the status

```bash
./stack.sh status
```

All containers should be `Up`. Containers with a healthcheck additionally show `(healthy)`. `flagd`, `jaeger`, `prometheus`, `grafana`, `cart`, `otel-collector` and the MCP container have no healthcheck and only show `Up`.

Quick URL test (all should return `200`):

```bash
for u in http://localhost:8080/ http://localhost:8080/jaeger/ui/ \
         http://localhost:8080/grafana/ http://localhost:8080/loadgen/ \
         http://localhost:8080/feature http://localhost:9090/-/healthy; do
  printf "%-40s %s\n" "$u" "$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 10 $u)"
done
```

Further checks:

```bash
curl -s http://localhost:9090/-/healthy                                   # Prometheus
docker exec grafana curl -s http://127.0.0.1:3000/api/health              # Grafana (use "podman exec" with Podman)
./stack.sh check                                                          # collector
```

---

## 7. Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Port 8080 unreachable, `frontend`, `frontend-proxy`, `load-generator` in state `Created` | `recommendation` is `unhealthy` (`nc: not found`) | Make sure the `recommendation` healthcheck from `compose.lab.yaml` (in `overlay/`, section 2) is applied, then restart the stack |
| No connection to Podman (macOS/Windows) | Podman machine stopped | `podman machine start` |
| Collector log: `lookup kafka ... no such host` | The collector scrapes Kafka, but there is no Kafka container in the stack | Permanent noise, no effect on the shop or on sampling |
| Collector log: export to Prometheus `HTTP Status Code 500` | Prometheus was not ready yet at startup | Check after a minute whether the error occurs again |
| Collector does not start | YAML error or unknown processor in `otelcol-config.yml` | `./stack.sh logs otel-collector`, fix the error, recreate the stack |
| Spans/s close to 0 in the measurements | No traffic | Is `load-generator` running? `./stack.sh status`, wait at least 5 minutes of traffic |
| `Connection refused` on port 8000 | MCP container missing | Start the stack with `./stack.sh up` (MCP is included by default; not with `--no-mcp`) |

---

## 8. Note on the baseline

Before every baseline measurement, check which variant is active:

```bash
./config.sh show
```

If it shows anything other than `baseline`, it is no longer a baseline:

```bash
./config.sh use baseline
./stack.sh up
```
