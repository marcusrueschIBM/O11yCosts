[Deutsch](MCP_SERVER_ERKLAERUNG.md) | **English**

# MCP Sampling Advisor — Explanation for Beginners

## What is MCP anyway?

**MCP** stands for **Model Context Protocol** — an open protocol from Anthropic that defines how an AI model communicates with external tools and data sources.

Think of MCP as a standardized power socket:

```
AI client (e.g. Claude, IBM Bob)
    │
    │  speaks MCP — always the same, whichever AI
    │
    ▼
MCP server (our sampling advisor)
    │
    │  queries Prometheus
    │
    ▼
Prometheus (real measurement data)
```

Without MCP, every AI would need its own connection to Prometheus.
With MCP you build the server once — any MCP-capable AI can use it.

---

## What exactly does our MCP server do?

The **OTel Sampling Advisor** is a read-only MCP server. It:

1. Receives requests from an AI
2. Queries Prometheus with PromQL
3. Returns the results to the AI in a structured form

**Read-only** means: it changes nothing. It only reads data.
No write access to the collector, no automatic changes.
The AI recommends — a human decides and makes the change.

---

## The four tools

The server provides the AI with four tools:

| Tool | Asks Prometheus for | Returns |
|---|---|---|
| `top_operations` | Which operations generate the most span volume? | Ranking of service + operation + spans/s |
| `error_hotspots` | Which operations have the highest error rate? | Ranking of service + operation + error % |
| `slow_operations` | Which operations have the highest p95 latency? | Ranking of service + operation + ms |
| `sampling_candidates` | All three combined | Volume + errors + latency + rules |

The AI calls these tools, evaluates the data and formulates a recommendation.
It does not invent values — everything is based on real measurement data from Prometheus.

---

## Architecture: where does the MCP server sit?

```
┌─────────────────────────────────────────────────────────┐
│  macOS                                                  │
│                                                         │
│  AI client ──MCP──► http://localhost:8000/mcp           │
│                                │                        │
│  ┌─────────────────────────────▼───────────────────┐    │
│  │  Podman Machine (Linux VM)                      │    │
│  │                                                 │    │
│  │  ┌─────────────────┐    ┌──────────────────┐   │    │
│  │  │  mcp-sampling-  │    │   Prometheus      │   │    │
│  │  │  advisor        │◄───│   :9090           │   │    │
│  │  │  :8000          │    │                   │   │    │
│  │  └─────────────────┘    └──────────────────┘   │    │
│  │                                  ▲              │    │
│  │  ┌─────────────────┐             │              │    │
│  │  │  OTel Collector │─────────────┘              │    │
│  │  │  (span metrics) │                            │    │
│  │  └─────────────────┘                            │    │
│  │         ▲                                       │    │
│  │  ┌──────┴──────────┐                            │    │
│  │  │  Astronomy Shop │                            │    │
│  │  │  (spans/traces) │                            │    │
│  │  └─────────────────┘                            │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

The diagram shows the tested setup (macOS with Podman).

The MCP server runs as a container **next to** the rest of the stack.
It reaches Prometheus over the internal container network (`http://prometheus:9090`).
From outside (macOS) it is reachable at `http://localhost:8000/mcp`.

---

## The three files of the MCP server

### 1. `requirements.txt` — Python dependencies

```
mcp[cli]>=2.2,<3
httpx>=0.27,<1
```

- **`mcp[cli]`** — the MCP Python SDK. Provides `MCPServer`, `@mcp.tool()` and the HTTP transport.
- **`httpx`** — HTTP client for the Prometheus API queries. Async-capable, so non-blocking.

### 2. `Containerfile` — build instructions for the container

```dockerfile
FROM python:3.12-slim        # base: minimal Python 3.12 image
WORKDIR /app                 # working directory in the container
COPY requirements.txt .      # copy dependencies
RUN pip install --no-cache-dir -r requirements.txt  # install them
COPY server.py .             # copy server code
EXPOSE 8000                  # document the port (does not open it)
CMD ["python", "server.py"]  # start command
```

### 3. `server.py` — the actual server

```python
import os, httpx
from mcp.server import MCPServer

# Create the server with a name
mcp = MCPServer("OTel Sampling Advisor")

# Read configuration from environment variables
# (defaults fit the demo environment)
PROM   = os.getenv("PROM_URL",  "http://prometheus:9090")
CALLS  = os.getenv("CALLS_METRIC", "traces_span_metrics_calls_total")
DUR    = os.getenv("DURATION_BUCKET_METRIC",
                   "traces_span_metrics_duration_milliseconds_bucket")
SVC    = os.getenv("SERVICE_LABEL",  "service_name")
SPAN   = os.getenv("SPAN_LABEL",     "span_name")
STATUS = os.getenv("STATUS_LABEL",   "status_code")
ERR    = os.getenv("ERROR_VALUE",    "STATUS_CODE_ERROR")
```

**Why environment variables?** The metric names can differ depending on the
collector version. Via `.env.override` you can adjust them
without changing the code.

```python
# Helper function: call the Prometheus HTTP API
async def q(expr):
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.get(f"{PROM}/api/v1/query", params={"query": expr})
        r.raise_for_status()
        return r.json()["data"]["result"]
```

This function sends a PromQL query to Prometheus and returns the
raw results. `async` means: while Prometheus is answering,
the server can handle other requests.

```python
# Convert results into a readable format
def out(rows):
    return [{"labels": r.get("metric", {}),
             "value": float(r["value"][1])} for r in rows]
```

Converts the raw Prometheus response into a simple list:
`[{"labels": {"service_name": "frontend", ...}, "value": 8.92}, ...]`

```python
# Tool 1: top operations by volume
@mcp.tool()
async def top_operations(window: str = "5m", limit: int = 15):
    return out(await q(
        f"topk({limit},sum by ({SVC},{SPAN})(rate({CALLS}[{window}])))"
    ))
```

`@mcp.tool()` registers the function as an MCP tool. The AI can call
it with `top_operations(window="10m", limit=20)`.

```python
# Tool 4: all three combined — the main tool for the AI
@mcp.tool()
async def sampling_candidates(window: str = "5m", limit: int = 20):
    return {
        "volume": await top_operations(window, limit),
        "errors": await error_hotspots(window, limit),
        "slow":   await slow_operations(window, limit),
        "rules":  ["keep errors", "keep slow",
                   "protect critical", "human review"]
    }
```

`sampling_candidates` is the most important tool — it calls all three
others and returns everything at once. The `rules` list gives the AI
explicit guidelines.

```python
# Start the server
if __name__ == "__main__":
    mcp.run("streamable-http", host="0.0.0.0", port=8000)
```

**Streamable HTTP** is the MCP transport protocol for network connections.
`0.0.0.0` means: listen on all network interfaces (required in the container).

---

## Installation step by step

### Prerequisite

The Astronomy Shop stack is already running (Prometheus reachable at
`http://localhost:9090`). Check:

```bash
curl -s http://localhost:9090/-/healthy
# Expected: Prometheus Server is Healthy.
```

### Step 1 — Provide the files

Do not type anything in: `./setup.sh` creates all files in the demo directory. In the repo they live under `overlay/`:

- `overlay/mcp-sampling-advisor/server.py`
- `overlay/mcp-sampling-advisor/requirements.txt`
- `overlay/mcp-sampling-advisor/Containerfile`
- `overlay/compose.mcp.yaml`

The content corresponds to the excerpts in the section "The three files of the MCP server" above.

### Step 2 — compose.mcp.yaml

**What does `${CALLS_METRIC:-traces_span_metrics_calls_total}` mean in `compose.mcp.yaml`?**
"Take the value from `.env.override` if set — otherwise the default."
This way you can override names without changing the code.

### Step 3 — Build and start the container

```bash
./stack.sh up
```

After changes to `server.py`, rebuild the image and recreate the stack:

```bash
./stack.sh build-mcp
./stack.sh up
```

### Step 4 — Check the logs

```bash
./stack.sh logs mcp-sampling-advisor
```

Expected output (approximately):
```
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

Errors here usually mean: pip install failed or
a Python syntax error in `server.py`.

### Step 5 — Test the MCP server without an AI (MCP Inspector)

The MCP Inspector is a browser tool for manually testing MCP servers.

```bash
npx -y @modelcontextprotocol/inspector
```

The browser opens automatically. There:
1. Select transport: **Streamable HTTP**
2. Enter the URL: `http://localhost:8000/mcp`
3. Click **Connect**
4. In the **Tools** tab, test the four tools:
   - `top_operations` — returns a ranking by volume?
   - `error_hotspots` — returns error rates?
   - `slow_operations` — returns latencies?
   - `sampling_candidates` — returns all three combined?

**If a tool returns empty results:**
- Is Prometheus running? → `curl -s http://localhost:9090/-/healthy`
- Are there span metrics? → `curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep span`
- Are the metric names correct? → Check whether `traces_span_metrics_calls_total` exists

### Step 6 — Connect an AI client

Use an AI client that supports **Streamable HTTP MCP**.
Configure it with the endpoint: `http://localhost:8000/mcp`

**System prompt for the AI:**

```
You are an Observability Sampling Advisor.
Use only MCP data — do not invent values.
Preserve errors, slow traces, and business-critical flows.
Recommend aggressive sampling only for high volume,
low error rate, and low latency operations.
Deliver evidence, risk, policy idea, validation, and rollback plan.
Do not execute any change — a human decides.
```

**Questions for the AI:**

1. Call `sampling_candidates` and analyze the results.
2. Which operations have high volume but a low error rate and low latency?
3. Propose a tail sampling policy — with reasoning per operation.

---

## Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `Connection refused` on port 8000 | Container not started | Check `./stack.sh status` |
| Tools return an empty list | Prometheus has no data | Is the load generator running? `./stack.sh status` |
| `ModuleNotFoundError: mcp` | pip install failed | Rebuild the container: `./stack.sh build-mcp` |
| `Connection refused` on Prometheus | Wrong PROM_URL | Is `http://prometheus:9090` reachable? Only internally in the container network |
| MCP Inspector shows "No tools" | Wrong transport protocol | Choose **Streamable HTTP**, not SSE |

---

## One sentence per component

- **`server.py`** — reads Prometheus, provides 4 tools, runs on port 8000
- **`Containerfile`** — packages server.py into a Python 3.12 container image
- **`requirements.txt`** — MCP SDK + httpx, nothing else
- **`compose.mcp.yaml`** — starts the container next to the rest of the stack
- **MCP Inspector** — browser tool for testing the tools without an AI
- **AI client** — asks questions, gets real measurement data, recommends a policy
