#!/bin/bash

mkdir -p /tmp/rom
cd /tmp/rom

# export sync start time
SYNC_START=$(date +"%s")

git config --global user.name TheGhoulEater
git config --global user.email ghouleater00@gmail.com
git config --global credential.helper store
echo "https://PrajjuS:${GH_TOKEN}@github.com" > ~/.git-credentials

# Rom repo sync & dt ( Add roms and update case functions )
rom_one(){
     repo init --depth=1 --no-repo-verify -u https://github.com/Project-Elixir/official_manifest -b snow -g default,-device,-mips,-darwin,-notdefault
     git clone https://github.com/PrajjuS/local_manifest_vince --depth 1 -b elixir-12 .repo/local_manifests
     repo sync -c --no-clone-bundle --no-tags --optimized-fetch --force-sync -j8
     repo sync --force-sync -j1 --fail-fast
     export SELINUX_IGNORE_NEVERALLOWS=true
     source build/envsetup.sh && lunch aosp_vince-userdebug
}

rom_two(){
     repo init --depth=1 --no-repo-verify -u https://github.com/ProjectSakura/android -b 12 -g default,-device,-mips,-darwin,-notdefault
     git clone https://github.com/PrajjuS/local_manifest_vince --depth 1 -b sakura-12 .repo/local_manifests
     repo sync -c --no-clone-bundle --no-tags --optimized-fetch --force-sync -j8
     repo sync --force-sync -j1 --fail-fast
     export SELINUX_IGNORE_NEVERALLOWS=true
     source build/envsetup.sh && lunch lineage_vince-userdebug
}

# setup TG message and build posts
telegram_message() {
        curl -s -X POST "https://api.telegram.org/bot${BOTTOKEN}/sendMessage" -d chat_id="${CHATID}" \
        -d "parse_mode=Markdown" \
        -d text="$1"
}

telegram_build() {
        curl --progress-bar -F document=@"$1" "https://api.telegram.org/bot${BOTTOKEN}/sendDocument" \
        -F chat_id="${CHATID}" \
        -F "disable_web_page_preview=true" \
        -F "parse_mode=Markdown" \
        -F caption="$2"
}

# Function to be chose based on rom flag in .yml
case "${rom}" in
 "ProjectElixir") rom_one
    ;;
 "ProjectSakura") rom_two
    ;;
 *) echo "Invalid option!"
    exit 1
    ;;
esac

# export sync end time and diff with sync start
SYNC_END=$(date +"%s")
SDIFF=$((SYNC_END - SYNC_START))


# Send 'Build Triggered' message in TG along with sync time
telegram_message "
*$rom Build Triggered*
*Date:* \`$(date +"%d-%m-%Y %T")\`
*Sync Time:* \`$((SDIFF / 60)) minute(s) and $((SDIFF % 60)) seconds\`"  &> /dev/null


# export build start time
BUILD_START=$(date +"%s")

# setup ccache
export CCACHE_DIR=/tmp/ccache
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
export CCACHE_COMPRESS=true
export CCACHE_COMPRESSLEVEL=1
export CCACHE_LIMIT_MULTIPLE=0.9
export CCACHE_MAXSIZE=50G
ccache -z

# Build commands for each roms on basis of rom flag in .yml / an additional full build.log is kept.
case "${rom}" in
 "ProjectElixir") mka sepolicy -j18 2>&1 | tee build.log
    ;;
 "ProjectSakura") mka bacon 2>&1 | tee build.log
    ;;
 *) echo "Invalid option!"
    exit 1
    ;;
esac

ls -a $(pwd)/out/target/product/${T_DEVICE}/ # show /out contents
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))

# sorting final zip ( commonized considering ota zips, .md5sum etc with similiar names  in diff roms)
ZIP=$(find $(pwd)/out/target/product/${T_DEVICE}/ -maxdepth 1 -name "*${T_DEVICE}*.zip" | perl -e 'print sort { length($b) <=> length($a) } <>' | head -n 1)
ZIPNAME=$(basename ${ZIP})
ZIPSIZE=$(du -sh ${ZIP} |  awk '{print $1}')
echo "${ZIP}"

# Post Build finished with Time,duration,md5,size&Tdrive link OR post build_error&trimmed build.log in TG
telegram_post(){
 if [ -f $(pwd)/out/target/product/${T_DEVICE}/${ZIPNAME} ]; then
        rclone copy ${ZIP} vince-new:/Roms/${rom} -P
        MD5CHECK=$(md5sum ${ZIP} | cut -d' ' -f1)
        DWD=${TDRIVE}${rom}/${ZIPNAME}
        telegram_message "
        *$rom Build Finished Successfully*
        *Build Time:* `\$(($DIFF / 3600)) hour(s) and $(($DIFF % 3600 / 60)) minute(s) and $(($DIFF % 60)) seconds\`
        *ROM:* \`${ZIPNAME}\`
        *MD5 Checksum:* \`${MD5CHECK}\`
        *Download Link:* [Here](${DWD})
        *Size:* \`${ZIPSIZE}\`
        *Date:*  \`$(date +"%d-%m-%Y %T")\`" &> /dev/null
 else
        BUILD_LOG=$(pwd)/build.log
        tail -n 10000 ${BUILD_LOG} >> $(pwd)/buildtrim.txt
        LOG1=$(pwd)/buildtrim.txt
        echo "CHECK BUILD LOG" >> $(pwd)/out/build_error
        LOG2=$(pwd)/out/build_error
        TRANSFER=$(curl --upload-file ${LOG1} https://transfer.sh/$(basename ${LOG1}))
        telegram_build ${LOG2} "
        *$rom Build Failed to Compile*
    *Build Time:* \`$(($DIFF / 3600)) hour(s) and $(($DIFF % 3600 / 60)) minute(s) and $(($DIFF % 60)) seconds\`
    *Build Log:* [Here](${TRANSFER})
    *Date:*  $(date +"%d-%m-%Y %T")" &> /dev/null
 fi
}

telegram_post
ccache -s
