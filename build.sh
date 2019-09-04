#!/bin/bash

usage()
{
    echo "Usage: $0" \
        "[-h arm-none-linux]" \
        "[-p <PREFIX>]" \
        "[-b <BUILD_DIR>]" \
        "[-j 4]" \
        "[-s build|trim|pack]" 1>&2
    exit 1
}

while getopts ":h:p:b:j:s:" o; do
    case "${o}" in
        h) HOST=$OPTARG ;;
        p) PREFIX=$OPTARG ;;
        b) BUILD_DIR=$OPTARG ;;
        j) JOBS=$OPTARG ;;
        s) STAGE=$OPTARG ;;
        V) VERSION=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND-1))

SCRIPT_DIR=$(readlink -f $(dirname $0))
[ -z $HOST ] && HOST=arm-none-linux-gnueabi
[ -z $PREFIX ] && PREFIX=$SCRIPT_DIR/_install/$HOST
[ -z $BUILD_DIR ] && BUILD_DIR=$SCRIPT_DIR/build/$HOST
[ -z $JOBS ] && JOBS=4
[ -z $STAGE ] && STAGE=build
[ -z $VERSION ] && VERSION=`git tag |tail -n1`

export MAKE=make
export CC=$HOST-gcc
export CXX=$HOST-g++
export CPP=$HOST-cpp
export AS=$HOST-as
export LD=$HOST-ld
export STRIP=$HOST-strip
export C_INCLUDE_PATH=$PREFIX/include
export CPLUS_INCLUDE_PATH=$PREFIX/include
export LD_LIBRARY_PATH=$PREFIX/lib
RPATH='-Wl,-rpath,$$\ORIGIN:$$\ORIGIN/../lib'
mkdir -p $PREFIX/share/
echo "CPPFLAGS=-I$PREFIX/include LDFLAGS=-L$PREFIX/lib" > $PREFIX/share/config.site

do_build()
{
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Building $1\033[0m"
    $*
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Finished $1\033[0m"
}

do_make()
{
    local make_dir=$1
    local make_jobs=$2
    local make_opts=$3

    if [ -z "$make_opts" ]; then
        $MAKE -C $make_dir -j$make_jobs
    else
        $MAKE -C $make_dir -j$make_jobs "$make_opts"
    fi

    if [ ! $? -eq 0 ]; then
        rm -rf $make_dir
        echo -e "\033[31m($(date '+%Y-%m-%d %H:%M:%S')): Failed to make $1\033[0m"
        exit 1
    fi

    if [[ ! $make_opts =~ 'install' ]]; then
        $MAKE -C $make_dir install
    fi
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Success to make  $1\033[0m"
}

do_build_with_configure()
{
    local name=$1
    local config_opts=$2
    local make_opts=$3
    local build=$BUILD_DIR/$name

    # Skip or start
    if [ -e $build ]; then
        echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Skip $1\033[0m"
        return
    fi
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Start building $1\033[0m"

    # autogen & configure
    if [ ! -e $SCRIPT_DIR/$name/configure ]; then
        pushd $SCRIPT_DIR/$name && ./autogen.sh && popd
    fi
    mkdir -p $build && pushd $build
    $SCRIPT_DIR/$name/configure $config_opts
    popd
    if [ ! $? -eq 0 ]; then
        rm -rf $build
        echo -e "\033[31m($(date '+%Y-%m-%d %H:%M:%S')): Failed to configure $1\033[0m"
        exit 1
    fi

    # make
    do_make $build $JOBS "$make_opts"
}

do_build_with_cmake()
{
    local name=$1
    local config_opts=$2
    local make_opts=$3
    local build=$BUILD_DIR/$name

    # Skip or start
    if [ -e $build ]; then
        echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Skip $1\033[0m"
        return
    fi
    echo -e "\033[32m($(date '+%Y-%m-%d %H:%M:%S')): Start building $1\033[0m"

    # cmake
    mkdir -p $build && pushd $build
    cmake $SCRIPT_DIR/$name $config_opts
    popd
    if [ ! $? -eq 0 ]; then
        rm -rf $build
        echo -e "\033[31m($(date '+%Y-%m-%d %H:%M:%S')): Failed to configure $1\033[0m"
        exit 1
    fi

    # make
    do_make $build $JOBS "$make_opts"
}

do_patch()
{
    local name=$1

    pushd $SCRIPT_DIR/$name
    git reset --hard HEAD
    for item in $(ls $SCRIPT_DIR/patchs/$name); do
        git apply $SCRIPT_DIR/patchs/$name/$item
    done
    popd
}

stage_build()
{
    git submodule init
    git submodule update

    # zlib
    do_build_with_cmake zlib "-DCMAKE_INSTALL_PREFIX=$PREFIX"
    rm -f $PREFIX/lib/libz.so*

    # elfutils
    pushd elfutils && autoreconf -i -f && automake --add-missing && popd
    do_patch elfutils
    do_build_with_configure elfutils "--prefix=$PREFIX --host=${HOST} \
        --enable-maintainer-mode --disable-textrelcheck"

    # libunwind
    do_build_with_configure libunwind \
        "--prefix=$PREFIX --host=${HOST} --enable-shared=yes"

    # binutils & gdb
    do_patch binutils-gdb
    do_build_with_configure binutils-gdb \
        "--prefix=$PREFIX --host=$HOST" \
        "CFLAGS=-g -O2 -DHAVE_FCNTL_H -DHAVE_LIMITS_H"

    # systemtap
    do_build_with_configure systemtap "--prefix=$PREFIX --host=${HOST} --without-avahi"

    # strace
    [ ! -e $BUILD_DIR/strace ] && cd strace && ./bootstrap && cd -
    do_build_with_configure strace \
        "--prefix=$PREFIX --host=${HOST} --enable-mpers=no"

    # ltrace
    do_build_with_configure ltrace "--prefix=$PREFIX --host=${HOST}"

    # valgrind
    do_build_with_configure valgrind \
        "--prefix=$PREFIX --host=${HOST/arm/armv7}"

    # gperftools
    do_build_with_configure gperftools \
        "--prefix=$PREFIX --host=${HOST} --enable-libunwind \
        --disable-static --disable-debugalloc" \
        "install-libLTLIBRARIES"

    # heaptrack
    pushd boost
    echo "using gcc : arm : aarch64-linux-gnu-g++ ;" > boost/user-config.jam
    ./bootstrap.sh --prefix=$PREFIX
    ./b2 install -a -q \
        --disable-icu \
        --with-system \
        --with-filesystem \
        --with-iostreams \
        --user-config=user-config.jam \
        -s NO_ZLIB=0 \
        -s NO_COMPRESSION=0 \
        -s ZLIB_INCLUDE=$PREFIX/include \
        -s ZLIB_LIBPATH=$PREFIX/lib \
        -s ZLIB_BINARY=z \
        -j $JOBS \
        abi=aapcs address-model=64 architecture=arm \
        binary-format=elf threading=multi toolset=gcc-arm
    rm -rf $PREFIX/lib/libboost_*
    popd
    do_build_with_cmake heaptrack \
        "-DCMAKE_INSTALL_PREFIX=$PREFIX -DHEAPTRACK_BUILD_PRINT=off \
        -DHEAPTRACK_BUILD_GUI=off -DHEAPTRACK_BUILD_TRACK=on"

    # tcpdump
    do_build_with_configure libpcap \
        "--prefix=$PREFIX --host=${HOST} --with-pcap=linux --enable-shared=no"
    do_build_with_cmake tcpdump "-DCMAKE_INSTALL_PREFIX=$PREFIX"
}

stage_trim()
{
    pushd $PREFIX

    # Strip
    find bin -mindepth 1 -type f -exec $STRIP -s {} \; 2>/dev/null
    find lib -path lib/valgrind -name '*.so*' -type f -exec $STRIP -s {} \;

    # Valgrind
    find lib/valgrind/ -perm 0755 \
        ! -name '*core*' \
        ! -name '*memcheck*' \
        ! -name '*.a' \
        -exec rm -f {} \;

    popd
}

stage_pack()
{
    pushd $PREFIX
    find lib/ -maxdepth 1 -name '*.so*' -type f -exec chrpath -r '$ORIGIN/../lib' {} \;
    tar --transform 'flags=r;s#^#edt/#' -czvf edt-$HOST-$VERSION.tar.gz \
        lib/libdw*.so* \
        lib/libelf*.so* \
        lib/libunwind.so* \
        lib/libtcmalloc.so* \
        lib/libprofiler.so* \
        lib/valgrind/*.so \
        lib/valgrind/*-*-linux \
        lib/valgrind/*.xml \
        lib/heaptrack \
        bin/nm \
        bin/objdump \
        bin/readelf \
        bin/strip \
        bin/strings \
        bin/gdb* \
        bin/dtrace\
        bin/stap* \
        bin/strace \
        bin/ltrace \
        bin/valgrind \
        bin/vgdb \
        bin/heaptrack \
        sbin/tcpdump
    popd
}

if [ "$STAGE" = build ]; then
    stage_build
    STAGE=trim
fi

if [ "$STAGE" = trim ]; then
    stage_trim
    STAGE=pack
fi

if [ "$STAGE" = pack ]; then
    stage_pack
fi
