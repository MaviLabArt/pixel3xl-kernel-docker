### AnyKernel3 kernel installer for crosshatch Docker kernel
## built against LineageOS 22.2 2026-02-24 nightly

properties() { '
kernel.string=LineageOS 22.2 crosshatch Docker kernel v10 delayed-start + auto-env (20260224)
do.devicecheck=1
do.modules=1
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
device.name1=crosshatch
supported.versions=15
supported.patchlevels=2026-02 - 2026-02
supported.vendorpatchlevels=
'; } # end properties

boot_attributes() {
  set_perm_recursive 0 0 755 644 $RAMDISK/*;
  if [ -d $RAMDISK/overlay.d ]; then
    set_perm_recursive 0 0 755 644 $RAMDISK/overlay.d;
  fi;
  if [ -d $RAMDISK/overlay.d/sbin ]; then
    set_perm_recursive 0 0 755 755 $RAMDISK/overlay.d/sbin;
  fi;
} # end attributes

BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

ui_print "Target: lineage-22.2-20260224-nightly-crosshatch"
ui_print "Payload: rebuilt kernel + dtb"
ui_print "Docker: kernel features enabled"
ui_print "crosshatch: wifi/audio built into kernel"
ui_print "Docker: install ak3-helper wrapper + delayed auto-start + auto-env"

dump_boot;

# Keep common legacy Docker checks satisfied on Android userspace.
patch_cmdline swapaccount "swapaccount=1";
patch_cmdline cgroup_enable "cgroup_enable=memory";
patch_cmdline cgroup_memory "cgroup.memory=1";
patch_cmdline ipv6.disable "ipv6.disable=0";

write_boot;
