# v0.3.0

- **Hot install — no reboot on update.** Flashing a new version over an existing
  one now applies live: the installer swaps the update into the live dir and
  re-runs the full pipeline immediately. Delegates to native hot install (ksud /
  mountify) when present, else a safe swap-with-rollback. First install still
  reboots as normal. (Adapted from Specter.) Dropped the empty sepolicy.rule so
  the module is unambiguously userspace-only and hot-installable.

# v0.2.1

- **Auto-target every user app.** Like AlwaysStrong/Specter, both TEESimulator
  and HMA-OSS now target every installed user app (`pm list packages -3`) plus
  the Play Integrity core, so new installs are covered automatically. Xposed /
  LSPosed managers are excluded (attesting through a hooked process breaks
  STRONG). Toggle `auto_target` (WebUI "Auto-target all apps").
- Confirmed the Action button runs PlayIntegrityFork's own `action.sh` first.

# v0.2.0

Aligned to the latest TEESimulator, one-tap full pipeline, and HMA-OSS config.

- **Latest TEESimulator format.** `mode` is configurable (generation/patch, auto-fallback); osVersion now mirrors the PIF Android release; security patch matches the PIF key on all three partitions; `overrides.json` uses the current field names.
- **Action does everything.** The Action button now also runs PlayIntegrityFork's own fetch (action.sh / autopif4.sh) so Build is fresh before mirroring — one tap: PIF fetch -> keybox -> targets -> patch -> TEESimulator -> HMA -> restart. Hourly skips the PIF fetch to avoid churn.
- **HMA-OSS config.** Merges a managed hide template into your EXISTING HMA-OSS config (preserving your templates, scope and configVersion, backing it up first). Brace-aware merger bails safely if it can't parse. Extra hide packages in hma_hide.list / the WebUI.
- **WebUI** gains the Run-PIF-action and Manage-HMA toggles, a TEESimulator mode selector, and an HMA hide-list editor. Every button tested.

Still untested on a device — the on-device STRONG result is the one thing left to confirm.

# v0.1.2

Leaner, less intrusive — stops stepping on your other modules.

- **Zero system props by default.** `spoof_boot_state` and `spoof_patch_props`
  are now OFF — PlayIntegrityFork already spoofs the locked/verified-boot and
  patch props, so KeepStrong no longer duplicates (and fights) that. Enable
  either only if PIF isn't covering it on your device.
- Trimmed the optional boot-prop set to a minimal core; dropped the broad
  build.tags/build.type sweeps across every partition (PIF's job).
- Gentler GMS restart: kills DroidGuard + force-stops the Play Store, no more
  `pm clear` wiping your Play Store login on every sync.
- Added a "Footprint" section to the README spelling out exactly what it touches.

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
