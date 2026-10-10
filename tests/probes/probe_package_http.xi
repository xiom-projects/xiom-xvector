// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Probe: xiom.http 0.1.4 helper gate (adoption 2026-10-10; see
// docs/XIOM-HTTP-EVAL.md). Direct consumption checks for the adopted
// surface -- the status reason phrases behind http_service.status_text:
//   - every reason phrase the service can emit matches the package table;
//   - the upstream gap is pinned: xiom.http.status has NO 507 entry
//     (returns "Unknown"), so the lane adapter owns "Insufficient
//     Storage" (tripwire: if upstream adds/changes 507 this check flags
//     the drift for a re-sync);
//   - the category predicates behave as documented.
// The wire side (raw "HTTP/1.1 507 Insufficient Storage") is pinned by
// probe_http_service.
// Exit = failed checks.

module probe_package_http

use xiom.http.status;
use xiom.io;
use xiom.convert;

fn check(ok: Bool, name: Str, fails: Int) -> Int {
  if ok { io.println("  [PASS] " + name); return fails; }
  io.println("  [FAIL] " + name); return fails + 1;
}

fn main() -> Int {
  io.println("=== xvector probe: xiom.http helper adoption ===");
  var fails: Int = 0;

  fails = check(http_status_text(200) == "OK" && http_status_text(201) == "Created"
    && http_status_text(400) == "Bad Request" && http_status_text(401) == "Unauthorized"
    && http_status_text(403) == "Forbidden" && http_status_text(404) == "Not Found",
    "status: lane-emitted reason phrases A (200/201/400/401/403/404)", fails);
  fails = check(http_status_text(405) == "Method Not Allowed" && http_status_text(409) == "Conflict"
    && http_status_text(413) == "Payload Too Large" && http_status_text(429) == "Too Many Requests"
    && http_status_text(500) == "Internal Server Error" && http_status_text(501) == "Not Implemented",
    "status: lane-emitted reason phrases B (405/409/413/429/500/501)", fails);
  fails = check(http_status_text(507) == "Unknown",
    "status: 507 still missing upstream (lane adapter owns 'Insufficient Storage')", fails);
  fails = check(http_is_success(200) && !http_is_success(404) && http_is_redirect(301)
    && http_is_client_error(429) && !http_is_client_error(500) && http_is_server_error(500),
    "status: category predicates (success/redirect/client/server)", fails);
  fails = check(http_status_category(200) == 200 && http_status_category(301) == 300
    && http_status_category(404) == 400 && http_status_category(503) == 500,
    "status: category mapping", fails);

  io.println("");
  io.println("probe_package_http: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
