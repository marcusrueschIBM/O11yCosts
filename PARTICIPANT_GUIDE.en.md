[Deutsch](TEILNEHMER.md) | **English**

# Participant Guide: Rebuild the Lab at Home

This guide takes you from an empty machine to your first measurement. Plan generously (rough estimate: 60–90 minutes, much of it for downloads). The duration depends on your internet connection and has not been measured.

Repository: https://github.com/marcusrueschIBM/O11yCosts

> **Important up front:** So far the lab has only been fully tested on **macOS (Apple Silicon) with Podman**. Linux, Windows and Docker are prepared but **not tested**. If something gets stuck there, troubleshooting is at the end (section 8).
>
> **Language of the scripts:** The scripts print their messages in **German**. This guide quotes them verbatim, with the English meaning in brackets, so you can recognise them in your terminal.

---

## 1. What you get

A local online shop (the *OpenTelemetry Astronomy Shop*) with 26 containers: shop services, load generator, OpenTelemetry Collector, Jaeger, Prometheus, Grafana and an MCP server. You measure how much telemetry each sampling variant produces and check whether errors and slow traces remain visible.

---

## 2. Requirements

### Hardware

| Resource | Minimum | Measured in the lab |
|---|---|---|
| RAM for the container engine | 8 GB (VM) or 8 GB free machine RAM | Containers use about 4 GB while running; the Podman VM was set up with 8 GB and 5 CPUs |
| CPUs | 4 | 5 |
| Free disk space | **about 25 GB** | Images of the 26 containers: about 9 GB, plus volumes and build cache |
| Internet | yes | Images come from `ghcr.io`, `quay.io` and `docker.io` |

The lab was tested on a machine with **16 GB RAM**. I have not tried it with less RAM. It may become unstable.

### Software

| Tool | Used for | Check with |
|---|---|---|
| **Docker** (with Compose) **or Podman** | Containers | `docker compose version` or `podman compose version` |
| **git** | Get the repo | `git --version` |
| **bash** | All scripts | `bash --version` |
| **python3** | Evaluation of the measurements | `python3 --version` |
| **curl** | Status checks | `curl --version` |
| Node.js with `npx` | Only for the MCP Inspector (optional) | `npx --version` |

You need **one** of Docker or Podman, not both.

### Free ports

These ports must not be in use on your machine:

| Port | Used for |
|---|---|
| 8080 | Shop, Jaeger, Grafana, Load Generator, Feature Flags |
| 9090 | Prometheus |
| 8000 | MCP server |
| 10000 | Admin port of the frontend proxy (Envoy) |

Check (macOS and Linux):

```bash
lsof -i :8080 -i :9090 -i :8000 -i :10000
```

No output means all ports are free.

---

## 3. Prepare your platform

Pick the section for your system.

### 3a. macOS

**Docker Desktop** (easiest way):
1. Install and start Docker Desktop: https://www.docker.com/products/docker-desktop/
2. In Docker Desktop under *Settings → Resources*, set at least **5 CPUs and 8 GB Memory**.
3. Check: `docker info` shows no error message.

**Or Podman** (this is how the lab was tested):
1. Install Podman Desktop: https://podman-desktop.io/
2. Set up Docker Compose as the compose provider (in Podman Desktop: *Settings → Resources → Compose → Setup*).
3. Create and start the Podman machine:
   ```bash
   podman machine init --cpus 5 --memory 8192 --disk-size 100
   podman machine start
   ```
   If a machine already exists, do **not** run `init` again, only `podman machine start`.
4. Check: `podman run --rm quay.io/podman/hello` prints a greeting.

### 3b. Linux

1. Install Docker Engine with the Compose plugin: https://docs.docker.com/engine/install/ (or Podman through your package manager).
2. Add your user to the `docker` group so that `sudo` is not needed, then log in again.
3. Check: `docker compose version` and `docker run --rm hello-world`.

### 3c. Windows

Native Windows without a Linux environment does **not** work, because the scripts need Bash.

1. Set up **WSL2 with Ubuntu** (PowerShell as administrator): `wsl --install -d Ubuntu`, then restart.
2. Install **Docker Desktop** and enable "Use the WSL 2 based engine" under *Settings → General*. Under *Settings → Resources → WSL Integration*, switch on your Ubuntu distribution.
3. Run all further commands in the **Ubuntu console**, not in PowerShell.
4. Keep the repo **in the Linux file system** (for example `~/lab`), not under `/mnt/c/...`. Otherwise it is very slow and line endings can cause problems.

---

## 4. Get the repo and set it up

```bash
git clone https://github.com/marcusrueschIBM/O11yCosts.git
cd O11yCosts
./setup.sh
```

`setup.sh` does four things:
1. It clones the OpenTelemetry demo from GitHub into the folder `opentelemetry-demo/`.
2. It sets the demo to a fixed state (commit `fdbd62ca`) so that everyone has the same code.
3. It copies the lab files from `overlay/` into it (MCP server, adjustments).
4. It activates the baseline configuration (no sampling).

Expected output at the end:

```
Fertig. Naechste Schritte:
  ./stack.sh up        # start the stack (detects docker or podman)
  ...
```

("Fertig. Naechste Schritte:" means "Done. Next steps:".)

If `./setup.sh` reports "Permission denied": run `chmod +x *.sh` and try again.

Check which engine was detected:

```bash
./stack.sh engine       # docker or podman
```

Force one if needed: `CONTAINER_ENGINE=podman ./stack.sh up`.

---

## 5. Start the stack

```bash
./stack.sh up
```

- On the **first start**, about 9 GB of images are downloaded and the MCP container is built. This takes 10–30 minutes depending on your connection (rough estimate, not measured).
- Later starts take 1–2 minutes.
- Messages such as `Container frontend Waiting` are normal. Wait until the output ends.

Then check:

```bash
./stack.sh status
```

**Expected:**
- All containers show `Up`. Most of them also show `(healthy)`.
- All URLs at the end show `200`.

If containers stay in status `Created` or are `unhealthy`, see section 8.

### The user interfaces

| What | Address |
|---|---|
| Shop | http://localhost:8080/ |
| Jaeger (traces) | http://localhost:8080/jaeger/ui/ |
| Grafana | http://localhost:8080/grafana/ |
| Load Generator | http://localhost:8080/loadgen/ |
| Feature Flags | http://localhost:8080/feature |
| Prometheus | http://localhost:9090/ |
| MCP server | http://localhost:8000/mcp |

Open Grafana and Jaeger only through these addresses, not through the random ports shown by `docker ps`.

### Go/No-Go: is everything running?

- [ ] The shop opens and shows products
- [ ] After a few clicks in the shop, Jaeger shows services such as `frontend` and `checkout`
- [ ] Prometheus reports: `curl -s http://localhost:9090/-/healthy` → `Prometheus Server is Healthy.`
- [ ] `./stack.sh check` shows no collector errors (Kafka messages are hidden)

Continue only when everything is ticked.

---

## 6. The first measurement (baseline)

The load generator starts automatically and produces load. You do not need to click anything.

1. Check that the baseline is active:
   ```bash
   ./config.sh show        # expected: Aktive Variante: baseline   ("Active variant: baseline")
   ```
2. **Wait at least 5 minutes.** Before that, the values are not meaningful, because Prometheus evaluates a 5-minute window.
3. Measure:
   ```bash
   ./measure.sh "Baseline"
   ```
4. Enter the values marked with `-->` into the table in `MEASUREMENT_TABLE.en.md`. (The script prints them as `--> Tabelle: ...`, meaning "--> Table: ...".)

The output shows four measurements: volume (spans per second), error rate, p95 latency and collector resources.

---

## 7. The other variants

The same pattern for each variant. Everything except the sampling stays the same: same load, same wait time (5 minutes), same measure command.

```bash
./config.sh list                  # baseline, head-50, head-10, tail, ai-policy
./config.sh use head-50           # activate the variant
./stack.sh up                     # recreate the collector (otherwise the change has no effect!)
./stack.sh check                  # no errors?
# wait 5 minutes
./measure.sh "50%"
```

| Variant | Command | Measurement name |
|---|---|---|
| Baseline | `./config.sh use baseline` | `"Baseline"` |
| Head 50 % | `./config.sh use head-50` | `"50%"` |
| Head 10 % | `./config.sh use head-10` | `"10%"` |
| Tail sampling | `./config.sh use tail` | `"Tail"` |
| AI policy | `./config.sh use ai-policy` | `"KI-Policy"` |

The name `"KI-Policy"` is German for "AI policy". Use it exactly like this so the results stay comparable.

In addition:
- **Check errors and slow traces:** Under http://localhost:8080/feature, switch on a feature flag for a simulated error, wait a few minutes, look for error traces in Jaeger, then switch the flag off again.
- **MCP advisor:** `./mcp_advisor.sh` shows a recommendation per operation (KEEP / WATCH / SAMPLE).
- **The complete step-by-step explanation** including the AI client is in `GUIDE.en.md`.

### Clean up

```bash
./stack.sh down                   # stop and remove the containers
```

The downloaded images are kept, so a restart is fast. To delete everything, see section 9.

---

## 8. If something does not work

| Symptom | Possible cause | Solution |
|---|---|---|
| `./setup.sh`: `git: command not found` | git is missing | Install git |
| `weder docker noch podman gefunden` ("neither docker nor podman found") | No engine installed or not started | Start Docker Desktop or the Podman machine |
| Port 8080 not reachable, `frontend`, `frontend-proxy`, `load-generator` stay in status `Created` | `recommendation` is `unhealthy` | The fix is in `overlay/compose.lab.yaml`. Did you run `./setup.sh`? Then `./stack.sh up` |
| `bind: address already in use` | Port is taken | Stop the other program (`lsof -i :8080`) |
| Containers end with `Killed`, stack breaks | Not enough RAM | Give the engine more RAM (section 2) |
| `no space left on device` | Disk is full | Free up space; `docker system df` shows the usage |
| Measurement shows almost only 0 | Too little traffic | Check that `load-generator` is running (`./stack.sh status`), wait 5 minutes |
| Measurement shows "Keine Daten" ("no data") | Prometheus has no span metrics | `./stack.sh check`, wait 2–3 minutes |
| Collector log: `lookup kafka ... no such host` | The stack contains no Kafka | Ignore, harmless |
| Collector log: `host_metrics ... permission denied` | Access to host processes is restricted | Ignore, only affects host metrics |
| `./measure.sh`: `Prometheus ist nicht erreichbar` ("Prometheus is not reachable") | Stack is not running | `./stack.sh status` |
| Script aborts with strange characters (`\r`) (Windows) | Wrong line endings | Clone the repo again inside WSL, not under `/mnt/c` |
| An image cannot be pulled | Network, proxy or login limit | Check your connection; behind a company proxy, configure it in the engine |

For everything else: `./stack.sh logs <container name>` shows the logs of a service.

### Known limitations

- The demo images are pulled with the tag `latest`. The source code is pinned to one state, the container images are not. If upstream publishes new images, behaviour may change.
- The collector mounts the host file system (`/hostfs`). On Docker Desktop, Windows and Linux this can differ. It only affects host metrics, not the sampling measurements.
- The measured numbers depend on your machine. **Compare variants with each other only, not with other people's numbers.**

---

## 9. Remove everything

```bash
./stack.sh down                       # remove the containers
docker system prune -a --volumes      # WARNING: deletes ALL unused images and volumes, including ones that are not from this lab
```

With Podman use `podman system prune -a --volumes`. The command affects **all** container data on your machine, not just this lab. If you still use Docker or Podman for other things, skip it and delete selectively through Docker Desktop or Podman Desktop.

You can delete the directory `O11yCosts/` including `opentelemetry-demo/` normally.
