#!/system/bin/sh
# KeepStrong — early boot (post-fs-data): verified-boot / locked-state props.
#
# These are the device-integrity props a STRONG verdict wants to see: a locked
# bootloader, Verified (green) boot state, no warranty trip, release-keys build
# tags. TEESimulator attests the root of trust from its own harvest + our
# overrides.json, but these props back it up for every other check that reads
# them directly. Gated behind spoof_boot_state so you can turn it off.
#
# Adapted from AlwaysStrong / PlayIntegrityFork boot scripts (GPL-3.0).

MODPATH="${0%/*}"
. "$MODPATH/common.sh"
ks_init
ks_on enabled || exit 0
ks_on spoof_boot_state || exit 0
_have_resetprop || exit 0

resetprop_if_diff ro.boot.warranty_bit 0
resetprop_if_diff ro.vendor.boot.warranty_bit 0
resetprop_if_diff ro.vendor.warranty_bit 0
resetprop_if_diff ro.warranty_bit 0
resetprop_if_diff ro.boot.verifiedbootstate green
resetprop_if_diff vendor.boot.verifiedbootstate green
resetprop_if_diff ro.boot.vbmeta.device_state locked
resetprop_if_diff vendor.boot.vbmeta.device_state locked
resetprop_if_diff ro.boot.flash.locked 1
resetprop_if_diff ro.secureboot.lockstate locked
resetprop_if_diff ro.boot.veritymode enforcing
resetprop_if_diff vendor.boot.veritymode enforcing
resetprop_if_diff ro.boot.realmebootstate green
resetprop_if_diff ro.is_ever_orange 0
resetprop_if_diff ro.boot.vbmeta.hash_alg sha256
resetprop_if_diff ro.boot.vbmeta.avb_version 1.0
resetprop_if_diff ro.boot.vbmeta.invalidate_on_error yes
resetprop_if_diff ro.secure 1
resetprop_if_diff ro.adb.secure 1
resetprop_if_diff ro.debuggable 0
resetprop_if_diff ro.force.debuggable 0
resetprop_if_diff sys.oem_unlock_allowed 0

for PROP in $(resetprop 2>/dev/null | grep -oE 'ro.*.build.tags'); do
  resetprop_if_diff "$PROP" release-keys
done
for PROP in $(resetprop 2>/dev/null | grep -oE 'ro.*.build.type'); do
  resetprop_if_diff "$PROP" user
done

delprop_if_exist ro.boot.verifiedbooterror
delprop_if_exist ro.boot.verifyerrorpart
exit 0
