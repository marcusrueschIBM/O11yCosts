[Deutsch](ANLEITUNG.md) | **English**

# Step-by-Step Guide: Baseline, Sampling and MCP/AI Advisor

**Prerequisite:** `./setup.sh` has been run and `./stack.sh status` shows all containers as well as the shop, Jaeger, Prometheus, Grafana, Load Generator and Feature Flags as reachable (see `README.en.md` and `START.en.md`).

The working directory for all following steps is the **repo root** (where `setup.sh`, `stack.sh`, `config.sh` and `measure.sh` live):

```bash
cd <path-to-repo>
```

The four sampling variants are ready-made in the `collector-configs/` folder and are activated with `./config.sh use <name>`. The YAML excerpts in phases 2–4 show what is in the files.

> **Note on script output:** The scripts print German messages (for example `Aktive Variante:` = "Active variant", `FEHLER:` = "ERROR"). They are quoted verbatim below, with the meaning in brackets where needed. The measurement label `"KI-Policy"` stands for the AI policy variant.

---

## Phase 1 — Measure the baseline

### Step 1.1 — Activate the baseline configuration

`./setup.sh` stores the original configuration as `otelcol-config.original.yml` (way back) and activates the baseline. Check that the baseline is really active:

```bash
./config.sh show      # expected: Aktive Variante: baseline   ("Active variant: baseline")
```

If the script shows anything else, reset it and recreate the stack:

```bash
./config.sh use baseline
./stack.sh up --no-mcp
```

### Step 1.2 — Define reproducible traffic

**The most important principle of the whole lab:** Between all variants (Baseline, 50%, 10%, Tail, AI) you change only the sampling configuration. Everything else stays identical:

- The same shop journey (product → cart → checkout)
- The same number of repetitions (e.g. 10×) **or** the running load generator for exactly 5 minutes
- The same PromQL time range when reading the values (e.g. always `[5m]` after the test ends)

Decide on one option now and stick to it.

### Step 1.3 — Confirm the metric names

The metric names can differ depending on the demo and collector version. Check once:

```bash
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep span
```

In this environment the names are confirmed:
- `traces_span_metrics_calls_total`
- `traces_span_metrics_duration_milliseconds_bucket`

The following commands use these names directly. If your environment returns different names, replace them accordingly.

### Step 1.4 — Measure and record the baseline values

Run the defined traffic (step 1.2). Then run all four measurements immediately.

> **Shortcut: measure.sh**
> The script lives in the repo root and runs all four measurements one after the other. For each row of the measurement table it shows the value to enter.
>
> ```bash
> ./measure.sh "Baseline"
> ```
>
> After each sampling variant, call the same command with the matching name:
> ```bash
> ./measure.sh "50%"
> ./measure.sh "10%"
> ./measure.sh "Tail"
> ./measure.sh "KI-Policy"
> ```
>
> The individual commands below are for explanation — the script does everything in one run.

---

> **Why in the terminal instead of the Prometheus UI?**
> The Prometheus UI does not give you a sorted table — you see the results in random order and cannot compare them directly. The terminal commands below format the output immediately as a sorted, readable table. This saves time and makes the results directly comparable between variants.

---

#### Measurement 1 — Volume: top 20 operations by span rate

**Why this measurement?**
It shows who generates the most traffic. This is the starting point for every sampling decision: high-volume operations that are not critical are the best candidates for aggressive sampling. Low-volume operations can hardly be reduced further — they hardly matter.

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=topk(20,sum by (service_name, span_name)(rate(traces_span_metrics_calls_total[5m])))' \
  | python3 -c "
import json,sys
r=sorted(json.load(sys.stdin)['data']['result'],key=lambda x:float(x['value'][1]),reverse=True)
print(f'{'Rang':<4} {'Service':<30} {'Operation':<40} {'Spans/s':>8}')
print('-'*84)
[print(f'{i:<4} {x[\"metric\"].get(\"service_name\",\"?\"):<30} {x[\"metric\"].get(\"span_name\",\"?\"):<40} {float(x[\"value\"][1]):>8.2f}') for i,x in enumerate(r,1)]
"
```

(The column header `Rang` means "rank".)

Write down the **top 5** — these services are the first to be reduced in the next steps.

---

#### Measurement 2 — Quality: top 15 operations by error rate

**Why this measurement?**
Volume alone is not enough. An operation with 10 spans/s and a 30% error rate must **not** be sampled — every dropped span could hide an error. This measurement protects you from unknowingly sacrificing error visibility. The combination of volume (measurement 1) and error rate (measurement 2) is the basis of every sound sampling decision.

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=topk(15,100*sum by(service_name,span_name)(rate(traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m]))/clamp_min(sum by(service_name,span_name)(rate(traces_span_metrics_calls_total[5m])),0.000001))' \
  | python3 -c "
import json,sys
r=sorted(json.load(sys.stdin)['data']['result'],key=lambda x:float(x['value'][1]),reverse=True)
print(f'{'Service':<30} {'Operation':<40} {'Fehler%':>8}')
print('-'*80)
[print(f'{x[\"metric\"].get(\"service_name\",\"?\"):<30} {x[\"metric\"].get(\"span_name\",\"?\"):<40} {float(x[\"value\"][1]):>7.1f}%') for x in r]
"
```

(The column header `Fehler%` means "error %".)

Classification (identical to `mcp_advisor.sh` in step 5.8):
- Error rate **> 5%** → **KEEP** list
- Error rate **> 0%** → **WATCH** (observe, do not sample aggressively)

---

#### Measurement 3 — Latency: top 15 operations by p95 response time

**Why this measurement?**
Slow operations are often what you need first when something goes wrong. If an operation has p95 > 1000 ms, you want to keep those traces completely — they show you exactly where a performance problem lies. Without this measurement you may collect the wrong 10% and lose exactly the slow traces that would help you with diagnosis.

```bash
curl -s 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=topk(15,histogram_quantile(0.95,sum by(le,service_name,span_name)(rate(traces_span_metrics_duration_milliseconds_bucket[5m]))))' \
  | python3 -c "
import json,sys
r=sorted(json.load(sys.stdin)['data']['result'],key=lambda x:float(x['value'][1]),reverse=True)
print(f'{'Service':<30} {'Operation':<40} {'p95 ms':>8}')
print('-'*80)
[print(f'{x[\"metric\"].get(\"service_name\",\"?\"):<30} {x[\"metric\"].get(\"span_name\",\"?\"):<40} {float(x[\"value\"][1]):>7.0f}') for x in r]
"
```

Classification (identical to `mcp_advisor.sh` in step 5.8):
- p95 **> 1000 ms** → **KEEP** list
- p95 **> 500 ms** → **WATCH**

Operations without errors and with p95 ≤ 500 ms are **SAMPLE** candidates.

---

#### Measurement 4 — Collector resources

**Why this measurement?**
Collector RAM is especially relevant for tail sampling — it buffers complete traces in memory until it can make a decision. Comparing before and after sampling shows whether the configuration change relieves or burdens the collector.

```bash
docker stats --no-stream otel-collector     # or: podman stats --no-stream otel-collector
```

`measure.sh` detects the engine itself and runs this measurement automatically as well.

---

After each variant, enter the values from the four measurements in this table:

| Metric | Source | Baseline | 50% | 10% | Tail | AI policy |
|---|---|---|---|---|---|---|
| Test duration | Clock / note — how long did the traffic run? | | | | | |
| Total rate spans/s | Measurement 1 — sum of spans/s over all operations | | | | | |
| Top-1 operation spans/s | Measurement 1 — value of the loudest single operation | | | | | |
| Operations with errors | Measurement 2 — number of rows with error rate > 0% | | | | | |
| Max. error rate % | Measurement 2 — highest single value in the error table | | | | | |
| Max. p95 latency ms | Measurement 3 — highest single value in the latency table | | | | | |
| Errors visible in Jaeger? | Check Jaeger manually — yes / no | | | | | |
| Slow traces visible? | Check Jaeger manually — yes / no | | | | | |
| Collector CPU % | Measurement 4 — `docker/podman stats` column CPU | | | | | |
| Collector RAM MiB | Measurement 4 — `docker/podman stats` column MEM USAGE | | | | | |

---

## Phase 2 — Probabilistic sampling 50%

### Step 2.1 — Activate the variant

```bash
./config.sh use head-50
```

This copies `collector-configs/head-50.yml` to `opentelemetry-demo/src/otel-collector/otelcol-config.yml`. The file differs from the baseline only by the two changes in 2.2 and 2.3. To see it yourself:

```bash
diff collector-configs/baseline.yml collector-configs/head-50.yml
```

### Step 2.2 — What is in the processor block

The following was added under `processors:` (existing processor entries remain unchanged):

```yaml
processors:
  # ... existing configuration remains unchanged ...
  probabilistic_sampler:
    sampling_percentage: 50
```

### Step 2.3 — Processor in the pipeline

In the trace pipeline, `probabilistic_sampler` is at the end of the `processors` list:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [resource_detection, memory_limiter,
        transform/sanitize_spans, gen_ai_normalizer,
        transform/redact_sensitive_data, redaction,
        probabilistic_sampler]
      exporters: [debug, span_metrics]
```

> **Note:** The list shows the processor names of the pinned upstream state (`fdbd62ca`). If you edit the configuration by hand, only append `probabilistic_sampler` at the end and delete nothing.

### Step 2.4 — Recreate the stack

A changed YAML file does **not** automatically update a running collector. Always recreate:

```bash
./stack.sh up --no-mcp
```

### Step 2.5 — Check the collector for errors

```bash
./stack.sh check
```

No output = no errors. If the collector does not start because of a YAML error or an unknown processor: **fix the configuration error first before you measure further.**

### Step 2.6 — Run the test and measure

Run identical traffic as for the baseline. Then measure:

```bash
./measure.sh "50%"
```

Enter the values in the **50% column**. Note: Because of the probabilistic selection, the result will not be exactly 50% of the baseline — that is normal.

---

## Phase 3 — Probabilistic sampling 10%

### Step 3.1 — Activate the variant

```bash
./config.sh use head-10
```

Compared to `head-50`, exactly one line changes in the `probabilistic_sampler` block:

```yaml
probabilistic_sampler:
  sampling_percentage: 10
```

### Step 3.2 — Restart the stack and check

```bash
./stack.sh up --no-mcp

./stack.sh check
```

### Step 3.3 — Run the test and measure

Run identical traffic. Then measure:

```bash
./measure.sh "10%"
```

Enter the values in the **10% column**.

---

## Phase 4 — Tail sampling

### Step 4.1 — Activate the variant

```bash
./config.sh use tail
```

Compared to `head-10`, the `probabilistic_sampler` is missing (block and pipeline entry); `tail_sampling` is in the configuration instead.

### Step 4.2 — What the tail sampler contains

Under `processors:` you find:

```yaml
processors:
  # ... existing processors remain ...
  tail_sampling:
    decision_wait: 10s
    num_traces: 5000
    expected_new_traces_per_sec: 100
    policies:
      - name: keep-errors
        type: status_code
        status_code: {status_codes: [ERROR]}
      - name: keep-slow
        type: latency
        latency: {threshold_ms: 1000}
      - name: sample-normal
        type: probabilistic
        probabilistic: {sampling_percentage: 10}
```

In the trace pipeline, `tail_sampling` is at the end of the list:

```yaml
processors: [resource_detection, memory_limiter,
  transform/sanitize_spans, gen_ai_normalizer,
  transform/redact_sensitive_data, redaction,
  tail_sampling]
```

### Step 4.3 — Restart the stack and check

```bash
./stack.sh up --no-mcp

./stack.sh check
```

### Step 4.4 — Test three traffic scenarios

Test one after the other:

**Normal traffic:** The load generator is running, or manual shop journeys.

**Error scenario:** Enable a feature flag at http://localhost:8080/feature. Switch on a flag for a simulated error. Run a few journeys. Reset the flag afterwards.

**Slow scenario:** Enable a feature flag for a simulated slowdown. Run a few journeys. Reset the flag.

> **Important:** After the restart, wait at least `decision_wait` (10 seconds) before searching Jaeger for results. Tail sampling first buffers the complete trace before it decides.

### Step 4.5 — Check the results

Check in Jaeger:
- Error traces: Are ERROR traces present in full?
- Slow traces: Are traces with latency > 1000 ms present in full?
- Normal traces: Are these reduced to ~10%?

Then measure:

```bash
./measure.sh "Tail"
```

Enter the values in the **Tail column**.

---

## Phase 5 — Build the MCP Sampling Advisor

### Step 5.1 — Confirm the Prometheus metric names

Before configuring the MCP server, confirm the actual names from step 1.3 once more:

```bash
curl -s 'http://localhost:9090/api/v1/label/__name__/values' | python3 -m json.tool | grep span
```

If the names differ from the defaults, enter them in `opentelemetry-demo/.env.override` (with any editor):

Example if your names are different:
```
CALLS_METRIC=your_actual_metric_name_calls
DURATION_BUCKET_METRIC=your_actual_metric_name_bucket
```

### Step 5.2 — The MCP files (already in the repo)

`./setup.sh` has already created the MCP server files. Do not type anything in. They live in `overlay/` and end up in the demo directory:

| File in the repo | Purpose |
|---|---|
| `overlay/mcp-sampling-advisor/server.py` | The MCP server with the four tools |
| `overlay/mcp-sampling-advisor/requirements.txt` | Python dependencies (`mcp[cli]`, `httpx`) |
| `overlay/mcp-sampling-advisor/Containerfile` | Container image (Python 3.12) |
| `overlay/compose.mcp.yaml` | Starts the MCP container next to the stack (port 8000) |

The structure and code of the server are explained line by line in `MCP_SERVER_EXPLAINED.en.md`.

### Step 5.3 — Changes to the server

If you change `overlay/mcp-sampling-advisor/server.py`, copy the file into the demo directory again and rebuild the image:

```bash
./setup.sh
./stack.sh build-mcp
./stack.sh up
```

### Step 5.4 — Overridable settings

`compose.mcp.yaml` reads metric and label names from environment variables with defaults. Only needed if step 5.1 showed different names (`CALLS_METRIC`, `DURATION_BUCKET_METRIC`, `SERVICE_LABEL`, `SPAN_LABEL`, `STATUS_LABEL`, `ERROR_VALUE`).

### Step 5.5 — Build and start the MCP container

```bash
./stack.sh up
```

### Step 5.6 — Check the MCP logs

```bash
./stack.sh logs mcp-sampling-advisor
```

Expected output: the server starts on port 8000, no errors.

### Step 5.7 — Test the MCP tools with the Inspector

Start the MCP Inspector:

```bash
npx -y @modelcontextprotocol/inspector
```

The Inspector opens in the browser. There:
1. Select transport: **Streamable HTTP** (not SSE — otherwise the Inspector shows "No tools")
2. Enter the URL:
   ```
   http://localhost:8000/mcp
   ```
3. Click **Connect**, then open the **Tools** tab

Test all four tools one after the other:
1. `top_operations` — returns operations with a high call volume?
2. `error_hotspots` — returns operations with a high error rate?
3. `slow_operations` — returns operations with a high p95 latency?
4. `sampling_candidates` — returns all three combined?

### Step 5.8 — Show recommendations as a list (mcp_advisor.sh)

The script `mcp_advisor.sh` lives in the repo root. It calls `sampling_candidates` via MCP and shows one recommendation per operation — without an AI client and without a browser:

```bash
./mcp_advisor.sh
```

Classification per operation:

| Recommendation | Condition |
|---|---|
| 🔴 **KEEP** | Error rate > 5% **or** p95 > 1000 ms |
| 🟡 **WATCH** | Error rate > 0% **or** p95 > 500 ms |
| 🟢 **SAMPLE** | everything else — candidate for aggressive sampling |

In addition, the script prints the error hotspots (> 5%), the slow operations (p95 > 1000 ms) and a recommended tail sampling configuration. The values are a rule-based preview of what the AI recommends with reasoning in phase 6 — **human review** is still mandatory.

If `FEHLER: MCP-Server nicht erreichbar` ("ERROR: MCP server not reachable") appears: check `./stack.sh status`.

> **Stop:** Only when all four tools and `mcp_advisor.sh` return plausible data, continue to phase 6. Empty results mean: the PromQL query is wrong, the metric names are wrong, or Prometheus has no data yet.

---

## Phase 6 — AI-assisted sampling policy

### Step 6.1 — Connect an AI client to MCP

Use an AI client that supports Streamable HTTP MCP (e.g. IBM Bob, Claude Desktop, or another MCP-capable client). Connect it to:

```
http://localhost:8000/mcp
```

### Step 6.2 — Set the system prompt

Give the AI client this system prompt:

```
You are an Observability Sampling Advisor.
Use only MCP data — do not invent values.
Preserve errors, slow traces, and business-critical flows.
Recommend aggressive sampling only for high volume, low error rate, and low latency operations.
Deliver evidence, risk, policy idea, validation, and rollback plan.
Do not execute any change — a human decides.
```

### Step 6.3 — Request the analysis

Ask the AI the following questions (one after the other or combined):

1. Which operations generate high volume while having few errors and being fast?
2. Which operations should be kept in full because of errors, latency or business criticality?
3. Propose a tail sampling policy — but do not execute any change.

Expected output format of the AI per operation:

| Operation | Volume | Errors | p95 | Recommendation | Reasoning |
|---|---|---|---|---|---|
| service/span | high/medium/low | % | ms | KEEP / SAMPLE / DROP | Evidence from MCP |

### Step 6.4 — Review the AI policy by a human (human review)

**Check before every change to the collector:**

- Are all error traces kept? (`keep-errors`)
- Are all slow traces kept? (`keep-slow`)
- Are business-critical flows explicitly protected?
- Are the recommended routes/attributes actually present in your traces?

> **Important:** The routes `/api/checkout` and `/api/payment` in the example policy below are **placeholders**. Use only attributes you have actually seen in Jaeger.

### Step 6.5 — Transfer the policy into the `ai-policy` variant

`collector-configs/ai-policy.yml` is a copy of the `tail` variant with a **commented-out** placeholder for critical routes. Enter the human-reviewed AI policy there (with any editor). The `tail_sampling` block should then look like this:

```yaml
tail_sampling:
  decision_wait: 10s
  num_traces: 5000
  expected_new_traces_per_sec: 100
  policies:
    - name: keep-errors
      type: status_code
      status_code: {status_codes: [ERROR]}
    - name: keep-slow
      type: latency
      latency: {threshold_ms: 1000}
    - name: keep-critical-routes        # ONLY if the route is actually present in traces
      type: string_attribute
      string_attribute:
        key: http.route
        values: [/api/checkout, /api/payment]   # REPLACE WITH REAL ROUTES
    - name: sample-normal
      type: probabilistic
      probabilistic: {sampling_percentage: 10}
```

### Step 6.6 — Activate the variant, recreate the stack and check

```bash
./config.sh use ai-policy
./stack.sh up

./stack.sh check
```

Run identical traffic (all three scenarios: normal, error, slow).

---

## Phase 7 — Document before / after

### Step 7.1 — Measure the after values

Run identical traffic as for the baseline. Then measure:

```bash
./measure.sh "KI-Policy"
```

Enter the values in the **AI policy column**.

### Step 7.2 — Calculate the reduction

```
Reduction % = (Baseline - After) / Baseline × 100
```

Example: Baseline = 1000 calls/s, After = 120 calls/s → reduction = 88%

### Step 7.3 — Check the visibility of the valuable signals

Checklist:
- [ ] Error traces visible in Jaeger?
- [ ] Slow traces visible in Jaeger?
- [ ] Critical flows traceable?
- [ ] MTTD/MTTR not worsened?

### Step 7.4 — Test the rollback

Make sure the rollback works:

```bash
./config.sh use baseline
./stack.sh up

./stack.sh check
```

After the rollback: briefly check Jaeger and Prometheus, and check the collector logs for errors.

---

## Summary of the story for the talk

1. **We measure first** — no estimates, real data from Prometheus
2. **Blanket sampling** reduces volume but can cost context
3. **Tail sampling protects valuable signals** — errors and slow traces are kept
4. **MCP gives the AI real telemetry data** — no guessing, only evidence
5. **The AI proposes, a human decides** — rollback is possible at any time
6. **We measure again** and prove the reduction with the same metrics
