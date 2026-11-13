#!/bin/bash

set -e

UNPACKBOOTIMG=../../../system/tools/mkbootimg/unpack_bootimg.py
DUMP=${1%/}

error_handler() {
    if [[ -d $extract_out ]]; then
        echo "Error detected, cleaning temporal working directory $extract_out"
        rm -rf $extract_out
    fi
}

trap error_handler ERR

function usage() {
	echo "Usage: ./extract-files.sh <path-to-dump-directory>"
	exit 1
}

function get_path() {
	echo "$extract_out/$1"
}

function unpackbootimg() {
	$UNPACKBOOTIMG $@
}

if [[ ! -f $UNPACKBOOTIMG ]]; then
	echo "Missing $UNPACKBOOTIMG, are you on the correct directory?"
	exit 1
fi

if [[ -z $DUMP ]] || [[ ! -d $DUMP ]]; then
	usage
fi

for f in boot.img vendor_boot.img dtbo.img; do
	if [[ ! -f $DUMP/$f ]]; then
		echo "Missing $DUMP/$f, is this a valid dump directory?"
		exit 1
	fi
done

for d in vendor_dlkm system_dlkm; do
	if [[ ! -d $DUMP/$d ]]; then
		echo "Missing $DUMP/$d, is this a valid dump directory?"
		exit 1
	fi
done

# Clean and create needed directories
for dir in ./modules/vendor_dlkm ./modules/system_dlkm ./modules/vendor_boot ./images ./images/dtbs; do
    rm -rf $dir
    mkdir -p $dir
done

# Temporary working directory
extract_out=$(mktemp -d)
echo "Using $extract_out as working directory"
echo "Using dump at $DUMP"

# BOOT
echo "Extracting the kernel image from boot.img"
out=$extract_out/boot-out
mkdir $out

echo "Extracting at $out"
unpackbootimg --boot_img $DUMP/boot.img --out $out --format mkbootimg

echo "Done. Copying the kernel"
cp $out/kernel ./images/kernel
echo "Done"

# VENDOR_BOOT
echo "Extracting the ramdisk kernel modules and DTB"
out=$extract_out/vendor_boot-out
mkdir $out

echo "Extracting at $out"
unpackbootimg --boot_img $DUMP/vendor_boot.img --out $out --format mkbootimg

echo "Done. Extracting the ramdisk"
mkdir $out/ramdisk
unlz4 $out/vendor_ramdisk00 $out/vendor_ramdisk
cpio -i -F $out/vendor_ramdisk -D $out/ramdisk

echo "Copying all ramdisk modules"
for module in $(find $out/ramdisk -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist"); do
	cp $module ./modules/vendor_boot/
done

# VENDOR_DLKM (already extracted in the dump, copy directly)
echo "Copying all vendor dlkm modules from $DUMP/vendor_dlkm"
for module in $(find $DUMP/vendor_dlkm -name "*.ko" -o -name "modules.load*" -o -name "modules.blocklist"); do
	cp $module ./modules/vendor_dlkm/
done

# SYSTEM_DLKM (already extracted in the dump, copy directly)
echo "Copying all system dlkm modules from $DUMP/system_dlkm"
if [[ ! -d $DUMP/system_dlkm/lib/modules ]]; then
	echo "Missing $DUMP/system_dlkm/lib/modules"
	exit 1
fi
cp -r $DUMP/system_dlkm/lib/modules/* ./modules/system_dlkm/

# Extract DTBO and DTBs
echo "Extracting DTBO and DTBs"

curl -sSL "https://raw.githubusercontent.com/PabloCastellano/extract-dtb/master/extract_dtb/extract_dtb.py" > ${extract_out}/extract_dtb.py

# Copy DTB
python3 "${extract_out}/extract_dtb.py" "${extract_out}/vendor_boot-out/dtb" -o "${extract_out}/dtbs" > /dev/null
find "${extract_out}/dtbs" -type f -name "*.dtb" \
    -exec cp {} ./images/dtbs/ \; \
    -exec printf "  - dtbs/" \; \
    -exec basename {} \;

# DTBO (no patching, copied as-is from the dump)
cp "$DUMP/dtbo.img" ./images/dtbo.img
echo "    + Copied images/dtbo.img"

rm -rf $extract_out
echo "Extracted files successfully"
