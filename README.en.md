[Deutsch](README.md) | **English**

# O11y Costs Lab — Sampling, Cost and AI Advisor

A reproducible lab for the talk *Signal Over Noise: Smarter OpenTelemetry Sampling with AI*. It builds on the
[OpenTelemetry Astronomy Shop](https://github.com/open-telemetry/opentelemetry-demo) and compares five sampling variants
(baseline, head 50 %, head 10 %, tail sampling, AI policy) using the same measurements. An MCP server gives an AI access to the
Prometheus data so that it can propose a sampling policy. A human decides.

This repo contains **only the lab files**. The upstream demo is cloned during setup (pinned to commit `fdbd62ca`, demo 3.1.0-48).

> **Note on language:** The documentation is available in German and English. The scripts (`setup.sh`, `stack.sh`, `config.sh`,
> `measure.sh`, `mcp_advisor.sh`) still print their messages in **German**. This guide quotes those messages verbatim and explains them
> where it matters. The measurement name `"KI-Policy"` means "AI policy"; keep it as written when you call `./measure.sh`.

## Requirements

**Software**

| Tool | Purpose | Note |
|---|---|---|
| Docker **or** Podman with `compose` | Containers | Detected automatically |
| git | Clone upstream | |
| bash | All scripts | Windows: only via WSL2 (not tested) |
| python3 | Evaluation in `measure.sh` and `mcp_advisor.sh` | |
| curl | Status checks | |
| Node.js (`npx`) | Only for the MCP Inspector | optional |

**Resources** (the stack consists of 26 containers)

| Resource | Value | Source |
|---|---|---|
| RAM and CPUs | tested with 5 CPUs and 8 GB RAM for the container engine on a machine with 16 GB RAM | measured |
| Containers while running | about 4 GB RAM | measured |
| Free disk space | about 25 GB (container images: about 9 GB, plus volumes and build cache) | images measured, total is a rough estimate |
| Internet | required, images come from `ghcr.io`, `quay.io` and `docker.io` | |
| Free ports | 8080, 9090, 8000, 10000 | |

The lab has not been tried with less RAM.

> **Participants:** The detailed guide for rebuilding the lab at home (platform preparation, go/no-go, troubleshooting) is in [`PARTICIPANT_GUIDE.en.md`](PARTICIPANT_GUIDE.en.md).

## Quick start

```bash
./setup.sh              # clone upstream, create lab files, activate baseline
./stack.sh up           # start the stack (1-2 minutes)
./stack.sh status       # check containers and URLs
```

| Component | Address |
|---|---|
| Astronomy Shop | http://localhost:8080/ |
| Jaeger | http://localhost:8080/jaeger/ui/ |
| Grafana | http://localhost:8080/grafana/ |
| Load Generator | http://localhost:8080/loadgen/ |
| Feature Flags | http://localhost:8080/feature |
| Prometheus | http://localhost:9090/ |
| MCP Advisor | http://localhost:8000/mcp |

## Lab flow

```bash
./config.sh use baseline && ./stack.sh up    # 1. activate a variant, recreate the stack
# wait at least 5 minutes with identical traffic
./measure.sh "Baseline"                      # 2. measure, enter the values in MEASUREMENT_TABLE.en.md

./config.sh use head-50 && ./stack.sh up     # then the same for head-50, head-10, tail, ai-policy
./measure.sh "50%"
```

Between the variants, only the sampling changes. Load, duration, user journey and time window stay the same.
The complete guide is in [`GUIDE.en.md`](GUIDE.en.md).

## Structure

| Path | Content |
|---|---|
| `setup.sh` | clones upstream, pins the commit, copies `overlay/` |
| `stack.sh` | start, stop, status, logs, collector error check (Docker or Podman) |
| `config.sh` | show and switch the sampling variant |
| `measure.sh` | four measurements (volume, errors, latency, collector resources) |
| `mcp_advisor.sh` | KEEP / WATCH / SAMPLE recommendations from the MCP server |
| `collector-configs/` | the variants `baseline`, `head-50`, `head-10`, `tail`, `ai-policy` |
| `overlay/` | files copied into the demo (MCP server, `compose.lab.yaml`, `compose.mcp.yaml`) |
| `PARTICIPANT_GUIDE.en.md` | Rebuild at home: requirements, setup, first measurement, troubleshooting |
| `GUIDE.en.md` | Step-by-step guide, phases 1–7 |
| `START.en.md` | Short reference: start, stop, URLs, troubleshooting |
| `MCP_SERVER_EXPLAINED.en.md` | The MCP server explained for beginners |
| `MEASUREMENT_TABLE.en.md` | Template for the measured values |

The German originals are `TEILNEHMER.md`, `ANLEITUNG.md`, `START.md`, `MCP_SERVER_ERKLAERUNG.md` and `MESSTABELLE.md`.

`opentelemetry-demo/` is created by `setup.sh` and is not part of the repo (see `.gitignore`).

## Differences from upstream

- `compose.lab.yaml`: higher memory limits for `grafana`, `checkout` and `product-catalog`, plus a **healthcheck fix for `recommendation`**.
  The image no longer contains `nc`. Without the fix, `frontend`, `frontend-proxy` and `load-generator` never start.
- `otelcol-config-full.yml` and all collector variants: `docker_stats` is removed from the metrics pipeline.
  The receiver reads through the Docker socket. Whether it works on Podman or other platforms has not been verified (see the note in `.env.override`).
- `compose.mcp.yaml` and `mcp-sampling-advisor/`: the MCP server.

## Platforms

| Platform | Status |
|---|---|
| macOS (Apple Silicon) with Podman | tested |
| macOS / Linux with Docker | **not tested**, the scripts detect Docker automatically |
| Linux with Podman | not tested |
| Windows (WSL2) | not tested |

Known limitations:
- The collector mounts `/` as `/hostfs` (`HOST_FILESYSTEM` in `.env`). On Docker Desktop and Windows this can differ.
  In that case set `HOST_FILESYSTEM` in `opentelemetry-demo/.env.override`. The `host_metrics` noise in the collector log only affects host metrics, not sampling.
- The demo images run with `DEMO_VERSION=latest`. The upstream source code is pinned, the container images are not. Newer images can
  change behaviour (as happened with the `recommendation` healthcheck).
- The collector permanently reports `kafkametrics` errors (`lookup kafka`) because the stack contains no Kafka container. This is harmless.

## License

The lab files in this repo are licensed under the license you choose for your repo. The cloned upstream demo is licensed under Apache-2.0.
