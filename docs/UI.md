<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# Station web UI (read-only MVP)

`xvectord` serves a built-in, dependency-free admin page at **`/ui`**. It is
a static HTML/JS asset served by the same process as the API, so there is no
second server, no CORS, and no network calls to a CDN. The first increment is
read-only: browse, visualize, inspect, and search.

## Run

```
# Windows
.\out\xvectord.exe                 # default 127.0.0.1:7707
# WSL / Linux
./out/xvectord

open http://127.0.0.1:7707/ui
```

Environment:

- `XVECTORD_UI_DIR` -- directory containing `index.html` (default `ui/`,
  relative to the daemon's working directory).
- `XVECTOR_API_KEYS` -- when auth is enabled, paste the key into the UI's
  API-key field (sent as `X-API-Key`; read scope is enough for this MVP).
- The UI is served on the daemon's bind address. Keep it on localhost or put
  it behind a TLS reverse proxy for remote access.

## What it does

- Collection picker and `/stats` summary (dimension, metric, index, points).
- **Sampled vector scatter**: `GET /collections/{name}/sample?limit=N&seed=S`
  returns ids + vectors from the active store; the page projects them to 2D
  with a seeded random projection (Canvas 2D). Hover shows the id, click
  selects a point and shows its vector.
- **Search playground**: paste a vector, run `/search`, and see hits
  highlighted on the scatter plus a ranked list with distances.
- API-key field (kept in `sessionStorage`), refresh, sample size, and a seed
  readout so a projection is reproducible.

## Sample endpoint semantics

`GET /collections/{n}/sample?limit=&seed=` returns:

```json
{ "collection": "docs", "dim": 128, "total": 100000,
  "sampled": 500, "scope": "active",
  "points": [ { "id": 42, "vector": [0.1, 0.2, ...] } ] }
```

- `limit` is clamped to **1..2000** (default 500). Sampling is a deterministic
  stride (`step = max(1, total / limit)`, offset by `seed % step`).
- The sample covers the **active store only**. Points already rolled into
  sealed segments are not included yet; `total` is the active-store size and
  `scope` says `"active"`. A union sample over D7 segments is the next step.
- The endpoint is read-scoped and runs under the engine mutex; keep `limit`
  bounded. It never scans the whole store for a sample.

## Projection and rendering

The MVP uses a seeded random projection (two normalized random directions;
data centered by the per-dimension mean) and Canvas 2D. It is deterministic
for a given seed, has no dependencies, and handles the sampled size well.
Planned upgrades, in order:

1. PCA (two components) for a more stable view, and a 3D WebGL/three.js view.
2. Payload-aware coloring and a filter builder.
3. HNSW graph view (sampled layers/edges).
4. Live updates (SSE/WebSocket) once the station exposes a stream.

## Security / limits

- The static page is public on the daemon's bind; the **API calls enforce
  auth/scopes**, so a remote deployment should still use TLS/ingress and a
  read key.
- No API key is written to the server; it lives in `sessionStorage` and is
  sent per request.
- This increment is read-only. The editor (upsert/delete, payload/filter
  builder, collection create/drop, index rebuild, move/drain) is a separate
  slice with admin-scope confirmations.
- The sample is bounded and active-only; it is not a full export path.

## Gates

`tests/probes/probe_ui.xi` starts the real threaded server, checks
`GET /ui`, `HEAD /ui` (headers only), the sample endpoint (`limit` clamp and
exact active-store count), an unknown `/ui/*` 404, and a graceful quit/join.
The probe is registered in both batteries.

## Relationship to PULSE / native apps

The station already serves HTTP; the UI is a same-origin static client of the
existing API and follows the PULSE wire conventions. A separate PULSE app or
a native `xiom.sdl3` + `xiom.imgui` desktop client can reuse the same
endpoints later; embedding a GUI event loop in the daemon is deliberately
avoided.
