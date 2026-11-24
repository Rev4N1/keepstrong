# v0.1.1

- Keybox endpoints are now a **list**, tried in order with fallback — put yours
  first and add mirrors below for when it drops. WebUI has a multi-line editor
  and a one-tap "+ Public mirrors" button (AlwaysStrong + Specter keybox URLs).
- Stored in /data/adb/keepstrong/keybox.urls (one URL per line); the old single
  keybox_url value still works and is appended.

# v0.1.0

First release. Bring-your-own STRONG orchestrator — bundles nothing, drives your
own PlayIntegrityFork + JingMatrix TEESimulator (+ optional HMA-OSS).

- Detects PlayIntegrityFork (`playintegrityfork`, legacy `playintegrityfix`) and TEESimulator (`teesim`).
- Mirrors the PIF Pixel identity + security patch into TEESimulator's config.
- Writes `overrides.json` to force a locked/Verified root of trust.
- Re-asserts Fork's STRONG spoof flags (version-aware).
- Fetches your keybox from a configurable endpoint (raw or base64 XML).
- KernelSU/APatch WebUI: status, toggles, keybox URL, target apps, sync, logs.
- Boot + hourly refresh. Disables no other module.

Untested on-device at release — check `/data/adb/keepstrong/logs/keepstrong.log`.
