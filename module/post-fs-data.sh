#!/system/bin/sh
# KeepStrong — early boot (post-fs-data): OPTIONAL locked/verified-boot props.
#
# OFF by default (spoof_boot_state=0). PlayIntegrityFork already spoofs the
# locked-bootloader / verified-boot / warranty / build-tags props at boot, so
# KeepStrong should NOT duplicate that and risk fighting it. This is only a
# fallback for a device where PIF's own boot scripts don't cover it — enable
# spoof_boot_state and you get this minimal core set. We deliberately do NOT
# touch build.tags / build.type across every partition (that is PIF's job).

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
