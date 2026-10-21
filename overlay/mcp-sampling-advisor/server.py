import os, httpx
from mcp.server import MCPServer

mcp = MCPServer("OTel Sampling Advisor")
PROM   = os.getenv("PROM_URL",               "http://prometheus:9090")
CALLS  = os.getenv("CALLS_METRIC",            "traces_span_metrics_calls_total")
DUR    = os.getenv("DURATION_BUCKET_METRIC",  "traces_span_metrics_duration_milliseconds_bucket")
SVC    = os.getenv("SERVICE_LABEL",           "service_name")
SPAN   = os.getenv("SPAN_LABEL",              "span_name")
STATUS = os.getenv("STATUS_LABEL",            "status_code")
ERR    = os.getenv("ERROR_VALUE",             "STATUS_CODE_ERROR")

async def q(expr):
    async with httpx.AsyncClient(timeout=20) as c:
        r = await c.get(f"{PROM}/api/v1/query", params={"query": expr})
        r.raise_for_status()
        return r.json()["data"]["result"]

def out(rows):
    return [{"labels": r.get("metric", {}), "value": float(r["value"][1])} for r in rows]

@mcp.tool()
async def top_operations(window: str = "5m", limit: int = 15):
    return out(await q(f"topk({limit},sum by ({SVC},{SPAN})(rate({CALLS}[{window}])))"))

@mcp.tool()
async def error_hotspots(window: str = "5m", limit: int = 15):
    e = f'100*sum by ({SVC},{SPAN})(rate({CALLS}{{{STATUS}="{ERR}"}}[{window}]))/clamp_min(sum by ({SVC},{SPAN})(rate({CALLS}[{window}])),0.000001)'
    return out(await q(f"topk({limit},{e})"))

@mcp.tool()
async def slow_operations(window: str = "5m", limit: int = 15):
    e = f"histogram_quantile(0.95,sum by (le,{SVC},{SPAN})(rate({DUR}[{window}])))"
    return out(await q(f"topk({limit},{e})"))

@mcp.tool()
async def sampling_candidates(window: str = "5m", limit: int = 20):
    return {
        "volume": await top_operations(window, limit),
        "errors": await error_hotspots(window, limit),
        "slow":   await slow_operations(window, limit),
        "rules":  ["keep errors", "keep slow", "protect critical", "human review"]
    }

if __name__ == "__main__":
    mcp.run("streamable-http", host="0.0.0.0", port=8000)
