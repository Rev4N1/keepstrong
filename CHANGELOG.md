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
