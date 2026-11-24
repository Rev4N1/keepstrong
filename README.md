# KeepStrong

A **bring-your-own** STRONG Play Integrity orchestrator for Magisk / KernelSU / APatch.

KeepStrong bundles **no** other modules. It drives the ones *you* install and
keep updated yourself, and does only the glue that makes them reach `STRONG`
together:

- **[PlayIntegrityFork](https://github.com/osm0sis/PlayIntegrityFork)** (osm0sis, id `playintegrityfork`) — the Build / fingerprint spoof. Only PIFork is driven; PlayIntegrityFix / inject-s is not supported.
- **[TEESimulator](https://github.com/JingMatrix/TEESimulator)** (JingMatrix, id `teesim`) — hardware key attestation via an in-process reference KeyMint.
- **[HMA-OSS](https://github.com/Dr-TSNG/Hide-My-Applist)** (optional) — module/root hiding.

If you want a one-flash bundle that ships these for you, use
[AlwaysStrong](https://gitlab.com/Evokerr/AlwaysStrong) instead. KeepStrong is
for people who prefer to install and update each piece themselves.

## What it actually does

On the Action button (and boot), it runs the full pipeline; hourly it runs the
same minus the PIF fetch:

0. **PIF action** — triggers PlayIntegrityFork's own `action.sh` / `autopif4.sh` so Build carries a fresh Pixel fingerprint before anything is mirrored (Action/boot only, to avoid hourly churn).
1. **Keybox** — fetches a keybox from **your** endpoints (a list, tried in order), validates it, installs it at `/data/adb/teesim/keybox.xml`. A fresh install is seeded with the public AlwaysStrong / Specter mirrors; put your own endpoint first. Raw or base64-encoded XML both accepted. The keybox is then checked against Google's revocation list.
2. **PIF flags** — re-asserts only the flags STRONG depends on: `spoofBuild=1`, `spoofProps=1`, and `spoofVendingFinger=1` on SDK 33+ (0 on SDK 32 and older). Every other PIFork flag is left exactly as PIFork wrote it. Its autopif can reset these, so they are re-applied after every fetch.
3. **Security patch** — reads the patch PIFork spoofs (`ro.build.version.security_patch`, falling back to `SECURITY_PATCH`, in `custom.pif.prop`) and sets TEESimulator's patch level to it on all three partitions. No device-patch fallback, so attestation never claims a patch Build doesn't.
4. **TEESimulator config** — mirrors the PIF-spoofed Pixel identity (brand/model/device/product/manufacturer + OS version + patch) into `/data/adb/teesim/config.json`, targets **every installed user app** (`pm list packages -3`, Xposed managers excluded) plus the Play Integrity core, sets the mode, and writes `/data/adb/teesim/overrides.json` to force a locked/Verified root of trust with a stable non-zero key+hash (so an unlocked bootloader doesn't attest a zeroed ORANGE root).
5. **HMA-OSS** (optional) — merges a managed blacklist template into your **existing** HMA-OSS config so **every user app** is blinded to your root manager / modules / Xposed, preserving your own templates, scope and `configVersion`. The hidden apps themselves (root managers, HMA) are kept out of the scope. Skips cleanly if it can't parse the config.
6. **Restart** — runs PlayIntegrityFork's own `killpi.sh` so DroidGuard + Play Store restart with the new identity, no reboot.

It never launches TEESimulator's daemon (its own module does that), never
touches your keybox outside the fetch, and never edits another module's files
except HMA-OSS's config (which it merges into, never overwrites). It disables
**nothing** — your installs are yours.

## Requirements

- Magisk (Zygisk) / KernelSU / APatch, with a Zygisk implementation for PlayIntegrityFork.
- PlayIntegrityFork **and** JingMatrix TEESimulator installed (TEESimulator is arm64/x86_64 only).
- A non-revoked attestation keybox: your own endpoint, or the seeded public mirrors.
- Android 10+.

## Install

1. Install PlayIntegrityFork and TEESimulator (and HMA-OSS if you want it). Reboot.
2. Flash `keepstrong.zip` in your root manager. Reboot.
3. Tap KeepStrong's **Action**, or open its WebUI (KernelSU / APatch) and tap **Sync now**.
   Add your own keybox endpoint under **Keybox endpoints** first if you have one.
4. Verify with Play Integrity API Checker / YASNAC.

No WebUI (plain Magisk)? Edit `/data/adb/keepstrong/keybox.urls` (one URL per
line) and tap the module's Action button.

## Configuration

Everything lives in `/data/adb/keepstrong/`:

- `config` — one `key=value` per line (see below). Delete it to reset to defaults.
- `keybox.urls` — keybox endpoints, one per line, tried in order.
- `apps.list` — extra packages to attest, one per line (GMS/Vending/GSF are always covered).
- `hma_hide.list` — extra packages HMA-OSS should hide.
- `logs/keepstrong.log` — what each pass did (kept under ~256 KB). Shown in the WebUI's Output section.
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
| `restart_gms_on_sync` | 1 | Run PIFork's `killpi.sh` (DroidGuard + Play Store) after a sync |
| `teesim_mode` | generation | TEESimulator profile mode (`generation` or `patch`) |
| `spoof_boot_state` | 1 | Locked/Verified boot props (PIF covers this; turn off if they fight) |
| `spoof_patch_props` | 1 | Pin OS patch props to PIFork's patch (turn off if they fight) |
| `interval_sec` | 3600 | Refresh interval |
| `keybox_url` | *(empty)* | Legacy single endpoint (use the WebUI list / `keybox.urls` instead) |

Endpoints live in `keybox.urls` (one per line, tried in order); extra target
apps in `apps.list`; extra HMA hide packages in `hma_hide.list`. All editable
from the WebUI.

## Footprint — what it touches

KeepStrong is glue, not another spoofer. By default it:

- **Sets only the boot/patch props.** The two `spoof_*` toggles (WebUI →
  Configuration → Advanced) are on by default so the OS-reported state matches
  what is attested; turn one off if PIF already owns it on your device and the
  two fight.
- **Disables no module; edits only data, never module files.** It writes
  `/data/adb/teesim/{config.json,overrides.json,keybox.xml}` (TEESimulator's own
  data dir, the whole point), re-asserts Fork's STRONG flag set (see step 2)
  that its autopif keeps resetting, and — if `manage_hma` is on — **merges** a
  template into HMA-OSS's `config.json`, preserving everything else and backing
  it up first (`config.json.keepstrong.bak`). If the merge can't parse the
  config it leaves it untouched. Turn `manage_hma` off to never touch HMA.
- **Runs one lightweight background loop** (a sleeping shell that re-syncs on
  `interval_sec`). No native daemons, no watchers, no bundled binaries.
- **Restarts via PIFork:** runs its `killpi.sh`, which ends DroidGuard and the
  Play Store so they restart on the next check. It does **not** `pm clear` the
  Play Store (that would wipe your login every sync).
- **Keeps all its own files** under `/data/adb/keepstrong/`; uninstall removes
  only that and leaves your keybox/TEESimulator config in place.

The whole module is a ~37 KB zip of shell, one awk file and one HTML page.

## Hot install (no reboot on update)

KeepStrong is purely userspace (shell + WebUI, no partition/zygisk/sepolicy
payload), so flashing a **new version over an existing one** applies live: the
installer swaps the update into place and re-runs the pipeline immediately — no
reboot. It delegates to native hot install (ksud / mountify) when available,
otherwise does a safe swap-with-rollback. A first install still needs the normal
reboot. If the live-apply fails it says so and falls back to Action / reboot.

## Notes & caveats

- STRONG depends on your device, keybox and the exact TEESimulator version. If
  it drops, open the WebUI's Output section to read the log.
- TEESimulator mode (WebUI → Configuration): **generation** (default) mints the
  key under your keybox and works everywhere; **patch** lets the real TEE make
  the key and re-signs it. Apps that attest device IDs with their own
  attestation key (e.g. Key Attestation) fail ID attestation in both modes,
  which does not affect Play Integrity.
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
