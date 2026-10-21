[Deutsch](MESSTABELLE.md) | **English**

# Measurement Table — Signal Over Noise: Smarter OpenTelemetry Sampling with AI

Record measurements with:
```bash
cd ~/Documents/otel-cost-workshop/opentelemetry-demo
./measure.sh "Baseline"   # then: "50%", "10%", "Tail", "KI-Policy"
```

Note: `"KI-Policy"` is the label for the AI policy variant. It is a free-text label and the scripts print it as given.

---

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
| Collector CPU % | Measurement 4 — `podman stats` column CPU | | | | | |
| Collector RAM MiB | Measurement 4 — `podman stats` column MEM USAGE | | | | | |

---

## Before / After evaluation

| KPI | Before (Baseline) | After (AI policy) | Goal |
|---|---|---|---|
| Total rate spans/s | | | reduced |
| Top-1 operation spans/s | | | reduced |
| Errors visible in Jaeger? | | | yes |
| Slow traces visible? | | | yes |
| Collector CPU % | | | not worse |
| Collector RAM MiB | | | not worse |

**Reduction % = (Baseline − After) / Baseline × 100**

Baseline spans/s: ______  |  After spans/s: ______  |  Reduction: ______ %
