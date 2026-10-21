# TODO — Signal Over Noise: Smarter OpenTelemetry Sampling with AI

Starting point: the OpenTelemetry Astronomy Shop is fully installed and the Go/No-Go checklist in Part 1 passes (all containers running, Shop, Jaeger, Prometheus, Grafana, Load Generator, and Feature Flags verified).

---

## Baseline

- [ ] Back up the Collector configuration as rollback reference (`otelcol-config.original.yml`)
- [ ] Define a reproducible traffic pattern (same load, duration, and user journey for every variant)
- [ ] Discover actual Prometheus metric and label names in the environment
- [ ] Measure and record 100% baseline: span call rate, error rate, p95 latency, Collector CPU/RAM

## Probabilistic Sampling — 50%

- [ ] Add `probabilistic_sampler` (50%) to the Collector configuration
- [ ] Activate the processor in the trace pipeline
- [ ] Recreate the stack and verify Collector starts without errors
- [ ] Run identical traffic and record measurements in the 50% column

## Probabilistic Sampling — 10%

- [ ] Change `sampling_percentage` to 10% in the Collector configuration
- [ ] Recreate the stack and verify Collector starts without errors
- [ ] Run identical traffic and record measurements in the 10% column

## Tail Sampling

- [ ] Remove `probabilistic_sampler` from the Collector configuration and pipeline
- [ ] Add `tail_sampling` with keep-errors, keep-slow, and sample-normal policies
- [ ] Recreate the stack and verify Collector starts without errors
- [ ] Test normal traffic, error scenario (Feature Flags), and slow scenario
- [ ] Confirm errors and slow traces remain fully visible
- [ ] Record measurements in the Tail Sampling column

## MCP Sampling Advisor

- [ ] Confirm actual Prometheus metric and label names; set overrides in `.env.override` if needed
- [ ] Create `mcp-sampling-advisor/` directory with `requirements.txt`, `Containerfile`, and `server.py`
- [ ] Create `compose.mcp.yaml` in the repository root
- [ ] Build and start the MCP container alongside the existing stack
- [ ] Verify MCP server logs show no errors
- [ ] Test all four tools with the MCP Inspector (`top_operations`, `error_hotspots`, `slow_operations`, `sampling_candidates`)

## AI-Driven Sampling Policy

- [ ] Connect an AI client (must support Streamable HTTP MCP) to `http://localhost:8000/mcp`
- [ ] Apply the provided system prompt to constrain the AI to MCP data only
- [ ] Request a per-operation recommendation: evidence, risk, policy idea, rollback plan
- [ ] Human-review the AI-generated Tail Sampling policy
- [ ] Apply the reviewed policy to the Collector configuration
- [ ] Recreate the stack and run identical traffic

## Before / After

- [ ] Record After measurements: span rate, errors visible, slow traces visible, Collector CPU/RAM
- [ ] Calculate reduction percentage: `(Baseline - After) / Baseline * 100`
- [ ] Confirm errors, slow traces, and critical flows remain visible
- [ ] Document Before/After delta (technical telemetry reduction only — no cost figures without contract data)
- [ ] Test rollback to `otelcol-config.original.yml`
