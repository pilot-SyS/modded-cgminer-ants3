#!/bin/bash
# This is a script for build avalon controller image
#
#  Copyright 2014-2015 Mikeqin <Fengling.Qin@gmail.com>
#  Copyright 2012-2015 Xiangfu <xiangfu@openmobilefree.com>
#
# OPENWRT_DIR is ${ROOT_DIR}/openwrt, build the image in it
# Controller's image should include the following configurations:
#    ${AVA_MACHINE}_owrepo : OpenWrt repo, format: repo_url@repo_ver
#    feeds.${AVA_MACHINE}.conf : OpenWrt feeds, file locate in cgminer-openwrt-packages
#    ${AVA_TARGET_BOARD}_brdcfg : OpenWrt target and config, file locate in cgminer-openwrt-packages
#
# Learn bash: http://explainshell.com/
set -e

SCRIPT_VERSION=17092017

# Support machine: avalon6, avalon4 , bitmain
[ -z "${AVA_MACHINE}" ] && AVA_MACHINE=bitmain

# Support target board: rpi2-modelb, rpi1-modelb, tl-wr703n-v1, tl-mr3020-v1
[ -z "${AVA_TARGET_BOARD}" ] && AVA_TARGET_BOARD=tl-mr3020-v1

# OpenWrt repo
avalon4_owrepo="svn://svn.openwrt.org/openwrt/trunk@43076"
avalon6_owrepo="git://git.openwrt.org/15.05/openwrt.git@master"
gekko_owrepo="git://git.openwrt.org/15.05/openwrt.git@master"
#bitmain_owrepo="git://git.openwrt.org/15.05/openwrt.git@master"
#bitmain_owrepo="git://github.com/openwrt/archive.git@master"
#bitmain_owrepo="git://github.com/csa402/openwrt-archive.git@master"
bitmain_owrepo="git://github.com/openwrt/archive.git@chaos_calmer"

# OpenWrt feeds
FEEDS_CONF=feeds.${AVA_MACHINE}.conf

# Board config: target(get it in the OpenWrt bin), config
rpi2_modelb_brdcfg=("brcm2708" "config.${AVA_MACHINE}.rpi2")
rpi1_modelb_brdcfg=("brcm2708" "config.${AVA_MACHINE}.raspberry-pi")
tl_wr703n_v1_brdcfg=("ar71xx" "config.${AVA_MACHINE}.703n")
tl_mr3020_v1_brdcfg=("ar71xx" "config.${AVA_MACHINE}.mr3020")

which wget > /dev/null && DL_PROG=wget && DL_PARA="-nv -O"
which curl > /dev/null && DL_PROG=curl && DL_PARA="-L -o"

# According to http://wiki.openwrt.org/doc/howto/build
unset SED
unset GREP_OPTIONS
[ "`id -u`" == "0" ] && echo "[ERROR]: Please use non-root user" && exit 1
# Adjust CORE_NUM by yourself
[ -z "${CORE_NUM}" ] && CORE_NUM="$(expr $(nproc) + 1)"
DATE=`date +%Y%m%d`
SCRIPT_FILE="$(readlink -f $0)"
SCRIPT_DIR=`dirname ${SCRIPT_FILE}`
ROOT_DIR=${SCRIPT_DIR}/avalon
OPENWRT_DIR=${ROOT_DIR}/openwrt

prepare_version() {
    cd ${OPENWRT_DIR}
    GIT_VERSION=`git ls-remote https://github.com/csa402/cgminer-ants3 master | cut -f1 | cut -c1-7`
    LUCI_GIT_VERSION=`git --git-dir=./feeds/luci/.git rev-parse HEAD | cut -c1-7`
    OW_GIT_VERSION=`git --git-dir=./feeds/cgminer/.git rev-parse HEAD | cut -c1-7`

    cat > ./files/etc/avalon_version << EOL
Firmware - $DATE
luci: $LUCI_GIT_VERSION
cgminer: $GIT_VERSION
cgminer-packages: $OW_GIT_VERSION
EOL
}

prepare_config() {
    cd ${OPENWRT_DIR}
    eval OPENWRT_CONFIG=\${"`echo ${AVA_TARGET_BOARD//-/_}`"_brdcfg[1]} && cp ./feeds/cgminer/cgminer/data/${OPENWRT_CONFIG} .config
}

prepare_feeds() {
    cd ${OPENWRT_DIR}
    $DL_PROG https://raw.github.com/csa402/cgminer-openwrt-packages/master/cgminer/data/${FEEDS_CONF} $DL_PARA feeds.conf && \
    ./scripts/feeds update -a && \
    ./scripts/feeds install -a

    if [ ! -e files ]; then
        ln -s feeds/cgminer/cgminer/root-files files
    fi
}

prepare_source() {
    echo "Gen firmware for ${AVA_TARGET_BOARD}:${AVA_MACHINE}"
    cd ${SCRIPT_DIR}
    [ ! -d avalon ] && mkdir -p avalon/bin
    cd avalon
    if [ ! -d openwrt ]; then
        eval OPENWRT_URL=\${${AVA_MACHINE}_owrepo}
        PROTOCOL="`echo ${OPENWRT_URL} | cut -d : -f 1`"

        case "${PROTOCOL}" in
            git)
                GITBRANCH="`echo ${OPENWRT_URL} | cut -d @ -f 2`"
                GITREPO="`echo ${OPENWRT_URL} | cut -d @ -f 1`"
                git clone -b ${GITBRANCH} ${GITREPO} openwrt
                ;;
            svn)
                SVNVER="`echo ${OPENWRT_URL} | cut -d @ -f 2`"
                SVNREPO="`echo ${OPENWRT_URL} | cut -d @ -f 1`"
                svn co ${SVNREPO}@${SVNVER} openwrt
                ;;
            *)
                echo "Protocol not supported"; exit 1;
                ;;
        esac
    fi
    [ ! -e dl ] && mkdir dl
    cd ${OPENWRT_DIR}
    ln -sf ../dl
}

build_image() {
    cd ${OPENWRT_DIR}
    yes "" | make oldconfig > /dev/null
    # clean before build
    #make -j${CORE_NUM} clean world V=s
    make -j${CORE_NUM} world V=s

}

build_cgminer() {
    cd ${OPENWRT_DIR}
    rm -f ./dl/cgminer-*-avalon*.tar.bz2
    yes "" | make oldconfig > /dev/null
    make -j${CORE_NUM} package/cgminer/{clean,compile}
    if [ "$?" == "0" ]; then
        eval AVA_TARGET_PLATFORM=\${"`echo ${AVA_TARGET_BOARD//-/_}`"_brdcfg[0]}
        cd ..
        mkdir -p ./bin/${AVA_TARGET_BOARD}
        cp ./openwrt/bin/${AVA_TARGET_PLATFORM}/packages/cgminer/cgminer*.ipk  ./bin/${AVA_TARGET_BOARD}
    fi
}

do_release() {
    cd ${ROOT_DIR}
    eval AVA_TARGET_PLATFORM=\${"`echo ${AVA_TARGET_BOARD//-/_}`"_brdcfg[0]}
    mkdir -p ./bin/${DATE}/${AVA_TARGET_BOARD}/
    cp -a ./openwrt/bin/${AVA_TARGET_PLATFORM}/* ./bin/${DATE}/${AVA_TARGET_BOARD}/
}

cleanup() {
    cd ${ROOT_DIR}
    rm -rf openwrt/ > /dev/null
}

show_help() {
    echo "\
Usage: $0 [--version] [--help] [--build] [--cgminer] [--cleanup]

     --version
     --help             Display help message
     --build            Get .config file and build firmware
     --cgminer          Re-compile only cgminer openwrt package
     --test		Dowload and prebuild files
     --cleanup          Remove all files

     AVA_TARGET_BOARD   Environment variable, available target:
                        tl-wr703n-v1, pi-modelb-v1
                        pi-modelb-v2, tl-mr3020-v1
                        use pi-modelb-v2 if unset

     AVA_MACHINE        Environment variable, available machine:
                        avalon6, avalon4, gekko , bitmain
                        use avalon6 if unset

Written by: Xiangfu <xiangfu@openmobilefree.net>
            Fengling <Fengling.Qin@gmail.com>
	    wareck <wareck@gmail.com>
                                                     Version: ${SCRIPT_VERSION}"
 }

if [ "$#" == "0" ]; then
    $0 --help
    exit 0
fi

for i in "$@"
do
    case $i in
        --version|--help)
            show_help
            exit
            ;;
        --build)
            prepare_source && prepare_feeds && prepare_config && prepare_version && build_image && do_release
            ;;
        --cgminer)
            prepare_source && prepare_feeds && prepare_config && prepare_version && build_cgminer
            ;;
	--test)
	    prepare_source && prepare_feeds && prepare_config && prepare_version
	    ;;
        --cleanup)
            cleanup
            ;;
        *)
            show_help
            exit
            ;;
    esac
done
