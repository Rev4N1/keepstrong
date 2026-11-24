#!/system/bin/sh
# KeepStrong — early boot (post-fs-data): OPTIONAL locked/verified-boot props.
#
# On by default (spoof_boot_state=1) so the OS-reported boot state matches the
# locked/Verified one KeepStrong attests. PlayIntegrityFork also sets some of
# these, so if the two fight on your device turn spoof_boot_state off in the
# WebUI and let PIF own them. Only this minimal core set is touched; build.tags
# / build.type across partitions are left to PIF.

MODPATH="${0%/*}"
. "$MODPATH/common.sh"
ks_init
ks_on enabled || exit 0
ks_on spoof_boot_state || exit 0
_have_resetprop || exit 0

resetprop_if_diff ro.boot.verifiedbootstate green
resetprop_if_diff ro.boot.vbmeta.device_state locked
resetprop_if_diff ro.boot.flash.locked 1
resetprop_if_diff ro.secureboot.lockstate locked
resetprop_if_diff ro.boot.veritymode enforcing
resetprop_if_diff sys.oem_unlock_allowed 0
resetprop_if_diff ro.boot.warranty_bit 0
resetprop_if_diff ro.warranty_bit 0
exit 0
