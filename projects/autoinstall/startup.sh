#!/bin/sh

DISK_IMAGE=minix.dev-postinst.8g.img
INSTANCE_NUMBER=1
MULTIBOOT_SOURCE_DIR=""

if [ -f .settings ]
then
	#allow to override the above settings using a .settings file
	#with DISK_IMAGE=minix-usb.img for example
	. ./.settings
fi

if [ ! -f usbdisk.img ] 
then
	#create a "usb disk"
	#this part is really optional usbdisk.img is added to qemu as a usb base disk
	#and is added here to allow testing of the dde usb stack 
	echo "creating usb disk image"
	dd if=/dev/zero of=usbdisk.img bs=1M seek=1000 count=1
	
fi
USB_DISK_PARAMS="-drive id=my_usb_disk,file=usbdisk.img,if=none  -device usb-storage,drive=my_usb_disk "
QEMU_PARAMS="-usb $USB_DISK_PARAMS"


#
# Try and find free tcp ports to run a qemu instance. This part is most probably not 
# portable as it assumes output from netstat
#tcp        0      0 0.0.0.0:9418            0.0.0.0:*               LISTEN     
#
for i in `seq 0 1 10`
do
	if  ! netstat -na  | grep "tcp[^6].*LISTEN"  | awk '{print $4}' | sed "s,.*:,,g" | grep $((4444 + $i)) 1>/dev/null
	then
		INSTANCE_NUMBER=$i
		break
	fi
done

if [ ! -f $DISK_IMAGE ]
then
	echo "Did not find '${DISK_IMAGE}' to start"
	exit 1
fi


if [ -n "$MULTIBOOT_SOURCE_DIR" -a -d "$MULTIBOOT_SOURCE_DIR" ]
then
	echo "Using multiboot (found directory)"
	#
	# For multiboot in qemu we need to give the modules as parameter to qemu in the 
	# initrd argument. We need a comma separated list of items but also need to pass
	# the kernel command line arguments to the modules.
	MULTIBOOT_DEST_DIR=multiboot
	rm -rf $MULTIBOOT_DEST_DIR
	mkdir -p $MULTIBOOT_DEST_DIR
	cp $MULTIBOOT_SOURCE_DIR/* $MULTIBOOT_DEST_DIR
	for i in $MULTIBOOT_DEST_DIR/mod*.gz ; do gunzip $i ; done
	MULTIBOOT_KERNEL_CMD_LINE="rootdevname=c0d0p0s0"
	MULTIBOOT_MODULE_NAMES="
		mod01_ds \
		mod02_rs \
		mod03_pm \
		mod04_sched \
		mod05_vfs \
		mod06_memory \
		mod07_log \
		mod08_tty \
		mod09_mfs \
		mod10_vm \
		mod11_pfs \
		mod12_init \
		"
	MULTIBOOT_MODULES=""
	for i in ${MULTIBOOT_MODULE_NAMES}
	do
		MULTIBOOT_MODULES="$MULTIBOOT_MODULES,$MULTIBOOT_DEST_DIR/${i} arg=$MULTIBOOT_KERNEL_CMD_LINE"
	done
	MULTIBOOT_MODULES=${MULTIBOOT_MODULES:1}
	MULTIBOOT_PARAMS="-kernel $MULTIBOOT_DEST_DIR/kernel -initrd \"$MULTIBOOT_MODULES\""

	QEMU_PARAMS="$QEMU_PARAMS -append \"$MULTIBOOT_KERNEL_CMD_LINE\""
	QEMU_PARAMS="$QEMU_PARAMS $MULTIBOOT_PARAMS"
fi


SSH_PORT=$((2222 + $INSTANCE_NUMBER))
MONITOR_PORT=$((4444 + $INSTANCE_NUMBER))
#
# Currently 512 MB is needed to start with networking
# 1024 is needed to compile clang....
#
# start qemu with port redirection so sshing to localhost 2222 will ssh into the qemu instance
# also start the monitor on port 4444 so we can telnet to it.
echo "starting ${DISK_IMAGE} qemu instance ${INSTANCE_NUMBER} with ssh port ${SSH_PORT} and monitor on port ${MONITOR_PORT}"
sleep 2

cmd="qemu-system-i386 -curses -localtime -redir tcp:$SSH_PORT::22 -m 2024  $QEMU_PARAMS -monitor telnet::$MONITOR_PORT,server,nowait -enable-kvm  -hda $DISK_IMAGE"
#
# I don't actually know why I need the eval here ..
echo $cmd
eval $cmd
