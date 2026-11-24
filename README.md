# KeepStrong

A **bring-your-own** STRONG Play Integrity orchestrator for Magisk / KernelSU / APatch.

KeepStrong bundles **no** other modules. It drives the ones *you* install and
keep updated yourself, and does only the glue that makes them reach `STRONG`
together:

- **[PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork)** (osm0sis, latest `playintegrityfork` id) — the Build / fingerprint spoof. The older `playintegrityfix` inject-s id is also recognised.
- **[TEESimulator](https://github.com/JingMatrix/TEESimulator)** (JingMatrix, id `teesim`) — hardware key attestation via an in-process reference KeyMint.
- **[HMA-OSS](https://github.com/Dr-TSNG/Hide-My-Applist)** (optional) — module/root hiding.

If you want a one-flash bundle that ships these for you, use
[AlwaysStrong](https://gitlab.com/Evokerr/AlwaysStrong) instead. KeepStrong is
for people who prefer to install and update each piece themselves.

## What it actually does

On the Action button (and boot), it runs the full pipeline; hourly it runs the
same minus the PIF fetch:

0. **PIF action** — triggers PlayIntegrityFork's own `action.sh` / `autopif4.sh` so Build carries a fresh Pixel fingerprint before anything is mirrored (Action/boot only, to avoid hourly churn).
1. **Keybox** — fetches a keybox from **your** endpoints (a list, tried in order), validates it, installs it at `/data/adb/teesim/keybox.xml`. Ships no server; raw or base64-encoded XML both accepted.
2. **PIF flags** — re-asserts PlayIntegrityFork's STRONG spoof flags (its autopif keeps resetting `spoofVendingFinger`), version-aware (off on Android ≤ 12L). inject-s is left to manage its own flags.
3. **Security patch** — derives the attested patch from the PIF fingerprint; TEESimulator's patch level is set to **match the PIF key** on all three partitions.
4. **TEESimulator config** — mirrors the PIF-spoofed Pixel identity (brand/model/device/product/manufacturer + OS version + patch) into `/data/adb/teesim/config.json`, targets **every installed user app** (`pm list packages -3`, Xposed managers excluded) plus the Play Integrity core, sets the mode, and writes `/data/adb/teesim/overrides.json` to force a locked/Verified root of trust with a stable non-zero key+hash (so an unlocked bootloader doesn't attest a zeroed ORANGE root).
5. **HMA-OSS** (optional) — merges a managed blacklist template into your **existing** HMA-OSS config so **every user app** is blinded to your root manager / modules / Xposed, preserving your own templates, scope and `configVersion`. Skips cleanly if it can't parse the config.
6. **Restart** — bounces DroidGuard + Play Store so the new identity takes effect without a reboot.

It never launches TEESimulator's daemon (its own module does that), never
touches your keybox outside the fetch, and never edits another module's files
except HMA-OSS's config (which it merges into, never overwrites). It disables
**nothing** — your installs are yours.

## Requirements

- Magisk (Zygisk) / KernelSU / APatch, with a Zygisk implementation for PlayIntegrityFork.
- PlayIntegrityFork **and** JingMatrix TEESimulator installed (TEESimulator is arm64/x86_64 only).
- Your own attestation keybox, reachable at an HTTP(S) endpoint you control.
- Android 10+.

## Install

1. Install PlayIntegrityFork and TEESimulator (and HMA-OSS if you want it). Reboot.
2. Flash `keepstrong.zip` in your root manager. Reboot.
3. Open **KeepStrong** in your root manager's WebUI (KernelSU / APatch).
4. Set **Keybox URL**, tap **Fetch keybox now**, then **Sync now**.
5. Verify with Play Integrity API Checker / YASNAC.

No WebUI (plain Magisk)? Edit `/data/adb/keepstrong/config` (set `keybox_url=`),
then run `su -c 'sh /data/adb/modules/keepstrong/action.sh'`.

## Configuration

Everything lives in `/data/adb/keepstrong/`:

- `config` — one `key=value` per line (see below). Delete it to reset to defaults.
- `apps.list` — extra packages to attest, one per line (GMS/Vending/GSF are always covered).
- `logs/keepstrong.log` — what each pass did.
- `security_patch.txt`, `state` — derived data; safe to ignore.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | 1 | Master switch |
| `auto_keybox` | 1 | Fetch keybox from your endpoints |
| `auto_fp_sync` | 1 | Mirror PIF identity + patch into TEESimulator |
| `reassert_pif_flags` | 1 | Keep Fork's STRONG flags set |
| `run_pif_action` | 1 | Run PlayIntegrityFork's own fetch on Action/boot |
| `auto_target` | 1 | Target **every** user app in TEESimulator + HMA (Xposed managers excluded) |
| `manage_hma` | 1 | Merge the hide template into HMA-OSS's config |
| `restart_gms_on_sync` | 1 | Bounce DroidGuard + Play Store after a sync |
| `teesim_mode` | generation | TEESimulator profile mode (`generation` or `patch`) |
| `spoof_boot_state` | **0** | Locked/Verified boot props — **off: PIF already does this** |
| `spoof_patch_props` | **0** | Pin OS patch props — **off: PIF already does this** |
| `interval_sec` | 3600 | Refresh interval |
| `keybox_url` | *(empty)* | Legacy single endpoint (use the WebUI list / `keybox.urls` instead) |

Endpoints live in `keybox.urls` (one per line, tried in order); extra target
apps in `apps.list`; extra HMA hide packages in `hma_hide.list`. All editable
from the WebUI.

## Footprint — what it touches

KeepStrong is glue, not another spoofer. By default it:

- **Sets zero system props.** The locked-bootloader / verified-boot / patch
  props are PlayIntegrityFork's job — the two `spoof_*` toggles that would set
  them are **off by default**. Turn one on only if PIF isn't covering it.
- **Disables no module; edits only data, never module files.** It writes
  `/data/adb/teesim/{config.json,overrides.json,keybox.xml}` (TEESimulator's own
  data dir, the whole point), re-asserts the one Fork flag (`spoofVendingFinger`)
  PIF's autopif keeps resetting, and — if `manage_hma` is on — **merges** a
  template into HMA-OSS's `config.json`, preserving everything else and backing
  it up first (`config.json.keepstrong.bak`). If the merge can't parse the
  config it leaves it untouched. Turn `manage_hma` off to never touch HMA.
- **Runs one lightweight background loop** (a sleeping shell that re-syncs on
  `interval_sec`). No native daemons, no watchers, no bundled binaries.
- **Restarts gently:** kills DroidGuard and force-stops the Play Store. It does
  **not** `pm clear` the Play Store (that would wipe your login every sync).
- **Keeps all its own files** under `/data/adb/keepstrong/`; uninstall removes
  only that and leaves your keybox/TEESimulator config in place.

The whole module is ~22 KB of shell + one HTML page.

## Notes & caveats

- **Untested on-device at release.** The scripts are self-checked and the config
  generation is validated, but STRONG depends on your device, keybox and the
  exact TEESimulator version. Treat v0.1.0 as a first cut and check the log.
- The `mode: generation` + `overrides.json` recipe follows AlwaysStrong's proven
  `-TEESIM` bridge. If a future TEESimulator build changes its config schema,
  adjust `teesim_config.sh`.
- `STRONG` needs a non-revoked hardware keybox. KeepStrong cannot mint one.

## Credits

KeepStrong is glue. The hard parts belong to others:

- **[JingMatrix](https://github.com/JingMatrix/TEESimulator)** — TEESimulator (keystore2 interception, reference KeyMint).
- **[osm0sis](https://github.com/osm0sis/PlayIntegrityFork)** — PlayIntegrityFork; its WebUI inspired this one.
- **[Evokerr / AlwaysStrong](https://gitlab.com/Evokerr/AlwaysStrong)** (GPL-3.0) — the TEESimulator config/overrides shape, the version-aware PIF flag handling and the prop-spoof set are adapted from it.
- **[chiteroman](https://github.com/chiteroman)** / **[KOWX712](https://github.com/KOWX712)** — Play Integrity Fix lineage.
- **[Dr-TSNG](https://github.com/Dr-TSNG/Hide-My-Applist)** — HMA-OSS.

## License

GPL-3.0. KeepStrong adapts GPL-3.0 code from AlwaysStrong, so the combined work
is GPL-3.0. Provided as-is, no warranty.
