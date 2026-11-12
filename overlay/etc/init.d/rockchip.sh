#!/bin/bash -eE

platform_setup()
{
install_packages() {
    case $1 in
        rk3288)
		MALI=midgard-t76x-r18p0-r0p0
		ISP=rkisp
		# 3288w
		cat /sys/devices/platform/*gpu/gpuinfo | grep -q r1p0 && \
		MALI=midgard-t76x-r18p0-r1p0
		sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf
		;;
        rk3399|rk3399pro)
		MALI=midgard-t86x-r18p0
		ISP=rkisp
		sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf
		;;
        rk3328|rk3528)
		MALI=utgard-450
		ISP=rkisp
		sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf
		;;
        rk3326|px30)
		MALI=bifrost-g31-g13p0
		ISP=rkisp
		sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf
		;;
        rk3128|rk3036)
		MALI=utgard-400
		ISP=rkisp
		sed -i "s/always/none/g" /etc/X11/xorg.conf.d/20-modesetting.conf
		;;
        rk3568|rk3566)
		MALI=bifrost-g52-g13p0
		ISP=rkaiq_rk3568
		if [ -e /usr/lib/aarch64-linux-gnu/ ]; then tar xvf /rknpu2.tar -C /; fi
		;;
        rk3562)
		MALI=bifrost-g52-g13p0
		ISP=rkaiq_rk3562
		if [ -e /usr/lib/aarch64-linux-gnu/ ]; then tar xvf /rknpu2.tar -C /; fi
		;;
        rk3576)
		MALI=bifrost-g52-g13p0
		ISP=rkaiq_rk3576
		if [ -e /usr/lib/aarch64-linux-gnu/ ]; then tar xvf /rknpu2.tar -C /; fi
		;;
        rk3588|rk3588s)
		ISP=rkaiq_rk3588
		MALI=valhall-g610-g24p0
		if [ -e /usr/lib/aarch64-linux-gnu/ ]; then tar xvf /rknpu2.tar -C /; fi
		;;
    esac
}

# Upgrade NPU FW
update_npu_fw() {
    /usr/bin/npu-image.sh
    sleep 1
    /usr/bin/npu_transfer_proxy &
}


compatible=$(cat /proc/device-tree/compatible | tr -d '\0')
chipname=""
case "$compatible" in
    *rk3288*)  chipname="rk3288" ;;
    *rk3328*)  chipname="rk3328" ;;
    *rk3399pro*)
        chipname="rk3399pro"
        update_npu_fw
        ;;
    *rk3399*)  chipname="rk3399" ;;
    *rk3326*)  chipname="rk3326" ;;
    *px30*)    chipname="px30" ;;
    *rk3128*)  chipname="rk3128" ;;
    *rk3528*)  chipname="rk3528" ;;
    *rk3562*)  chipname="rk3562" ;;
    *rk3566*)  chipname="rk3566" ;;
    *rk3568*)  chipname="rk3568" ;;
    *rk3576*)  chipname="rk3576" ;;
    *rk3588*)  chipname="rk3588" ;;
    *rk3036*)  chipname="rk3036" ;;
    *rk3308*)  chipname="rk3208" ;;
    *rv1126*)  chipname="rv1126" ;;
    *rv1109*)  chipname="rv1109" ;;
    *)
        echo "Please check if the SoC is supported on Rockchip Linux!"
        exit 1
        ;;
esac
compatible="${compatible#rockchip,}"
boardname="${compatible%%rockchip,*}"

/etc/init.d/boot_init.sh

sleep 3s

# first boot configure
if [ ! -e "/usr/local/first_boot_flag" ]; then
    echo "It's the first time booting. The rootfs will be configured."

    Mem_Size=$(free -m | grep Mem | awk '{print $2}')
    if [ '1500' -gt $Mem_Size  ] ;
    then
        echo 'Mem_Size =' $Mem_Size 'MB , make swap memory '
        swapoff -a
        dd if=/dev/zero of=/var/swapfile bs=1M count=1024
        mkswap /var/swapfile
        swapon /var/swapfile
        echo "/var/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi

    # Force rootfs synced
    # Flush explicitly when committing initialization state; keep normal I/O mode.

    install_packages "$chipname"

    if [ -e /usr/bin/gst-launch-1.0 ]; then
        setcap CAP_SYS_ADMIN+ep /usr/bin/gst-launch-1.0
    fi

    # Keep the kernel-created rfkill device node intact.

    # Keep source packages until initialization has completed successfully.

    # # The base target does not come with lightdm/rkaiq_3A
    # if [ -e /etc/gdm3/daemon.conf ]; then
    #     systemctl restart gdm3.service || true
    # elif [ -e /etc/lightdm/lightdm.conf ]; then
    #     systemctl restart lightdm.service || true
    # fi

    # if [ -e /usr/lib/systemd/system/rkisp_3A.service ]; then
    #     systemctl restart rkisp_3A.service || true
    # elif [ -e /usr/lib/systemd/system/rkaiq_3A.service ]; then
    #     systemctl restart rkaiq_3A.service || true
    # fi

    # The coordinator writes first_boot_flag after this entire script succeeds.
fi

# #usb configfs reset
# /usr/bin/usbdevice restart

# support power management
if [ -e "/usr/sbin/pm-suspend" ] && [ -e /etc/Powermanager ]; then
    if [ "$chipname" == "rk3399pro" ]; then
        mv /etc/Powermanager/01npu /usr/lib/pm-utils/sleep.d/
        mv /etc/Powermanager/02npu /lib/systemd/system-sleep/
        service input-event-daemon restart
    fi
    rm -rf /etc/Powermanager
fi

# Create dummy video node for chromium V4L2 VDA/VEA with rkmpp plugin
echo dec > /dev/video-dec0
echo enc > /dev/video-enc0
chmod 660 /dev/video-*
chown root:video /dev/video-*

# The chromium using fixed pathes for libv4l2.so
ln -rsf /usr/lib/*/libv4l2.so /usr/lib/
if [ -e /usr/lib/aarch64-linux-gnu/ ]; then
    ln -Tsf lib /usr/lib64
fi

# sync system time
hwclock --systohc || echo "Warning: RTC clock update failed; continuing boot" >&2

}

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /run/lock /var/log /var/lib/armsom
exec 9>/run/lock/armsom-first-boot.lock
flock -w 120 9 || { echo "Another initialization is still running" >&2; exit 1; }
exec > >(exec 9>&-; tee -a /var/log/armsom-first-boot.log) 2>&1
first_boot_failed()
{
    local rc=$1 line=$2
    trap - ERR
    first_boot_recover_kernel || echo "[first-boot] Recovery deferred; journal retained" >&2
    echo "[first-boot] FAILED at line $line (exit $rc); source packages retained" >&2
    exit "$rc"
}
trap 'first_boot_failed "$?" "$LINENO"' ERR
. /usr/lib/armsom/first-boot-common.sh
planned_reboot=0
trap 'if [ "$planned_reboot" = 1 ]; then exit 0; fi; echo "Initialization interrupted; recovery journal retained" >&2; exit 1' TERM INT HUP

echo "[first-boot] Starting initialization for boot $(cat /proc/sys/kernel/random/boot_id)"
userspace_needed=0
[ -e /usr/local/first_boot_flag ] || userspace_needed=1
platform_setup 9>&-

[ -e /boot/boot_init ] || {
    echo "[first-boot] Boot stage incomplete; refusing userspace completion" >&2
    exit 1
}
if [ "$userspace_needed" = 1 ]; then
    first_boot_request_reboot
    first_boot_mark /usr/local/first_boot_flag
fi

pending=/var/lib/armsom/first-boot-reboot
if [ -f "$pending" ]; then
    if [ "$(cat "$pending")" != "$(cat /proc/sys/kernel/random/boot_id)" ]; then
        # A later boot has already activated the initialized system.
        shopt -s nullglob
        if [ -f /var/lib/armsom/first-boot-kernel-release ]; then
            [ "$(uname -r)" = "$(cat /var/lib/armsom/first-boot-kernel-release)" ] || {
                echo "Expected initialized kernel is not running; keeping recovery files" >&2; exit 1;
            }
        fi
        packages=(/var/lib/armsom/kernel-packages/linux-image-*.deb /var/lib/armsom/kernel-packages/linux-headers-*.deb)
        if [ "${#packages[@]}" -gt 0 ]; then
            rm -f -- "${packages[@]}" || echo "[first-boot] Warning: could not clean cached kernel packages" >&2
        fi
        rm -f "$pending"
        sync -f /var/lib/armsom
    else
        # Reboot only after both stages and normal platform setup succeeded.
        [ -e /boot/boot_init ] && [ -e /usr/local/first_boot_flag ] || {
            echo "[first-boot] Initialization markers incomplete; refusing reboot" >&2
            exit 1
        }
        sync
        echo "[first-boot] Initialization complete; one planned reboot is required before desktop startup"
        planned_reboot=1
        systemctl --no-block reboot || { planned_reboot=0; exit 1; }
        # Stay activating so the display manager cannot race the reboot request.
        # systemd terminates this service when processing the shutdown transaction.
        sleep infinity
        exit 0
    fi
fi
echo "[first-boot] Initialization complete; continuing normal boot"
