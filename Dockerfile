# PS3 homebrew cross-compiler toolchain image — CORE.
#
# The base image every PS3 homebrew build starts from: ps3toolchain (ppu-gcc + PSL1GHT)
# plus the common, render-agnostic PSL1GHT portlibs (zlib/freetype/libpng, MikMod,
# PolarSSL, libcurl, Mini18n). The RENDERER stacks are separate variants built FROM this
# core (Dockerfile.tiny3d / Dockerfile.rsxgl / Dockerfile.raylib), so a renderer never
# drags another's libs. All cloned/downloaded from upstream at build time; no third-party
# source is committed here.
#
# Build (slow — compiles the cross toolchain from source):
#   docker build -t ps3-toolchain .
# Use it to compile render-agnostic PS3 homebrew (or as the base for a variant):
#   docker run --rm -v "$PWD":/src -w /src ghcr.io/02900/ps3-toolchain make
#
# CI builds this and publishes ghcr.io/02900/ps3-toolchain; it only rebuilds when this
# Dockerfile changes. A private, fully-vendored (offline) variant lives in
# 02900/ps3-toolchain-vendored.

# Ubuntu 20.04's host GCC-9 can build ps3toolchain's GCC 7.2.0; newer hosts
# (GCC 12/13 on 22.04/24.04) fail to compile that old GCC source. The host OS
# only builds the cross toolchain — it does not affect the PPU output.
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Library versions are pinned to match the README recipes.
ARG POLARSSL_VER=1.3.9
ARG CURL_VER=7.64.1
ARG MIKMOD_VER=3.1.11

# --- System dependencies -------------------------------------------------------------
# Superset of the repo README and ps3toolchain's own dependency checks. Notes:
#   - libtool-bin provides the `libtool` wrapper that check-libtool.sh runs (the
#     `libtool` package alone only ships libtoolize on modern Ubuntu).
#   - libncurses-dev satisfies check-ncurses.sh.
#   - python-is-python3 makes `python` resolve during the toolchain build.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential clang autoconf automake bison flex \
        libelf-dev libtool libtool-bin pkg-config texinfo \
        libgmp3-dev libmpfr-dev libmpc-dev libncurses-dev \
        zlib1g-dev libssl-dev wget git subversion ca-certificates \
        bzip2 xz-utils patch \
        python3 python3-dev python3-setuptools python-is-python3 2to3 && \
    rm -rf /var/lib/apt/lists/*

# Make every wget retry: the GNU/savannah mirrors that ps3toolchain and the lib
# recipes pull from (config.guess/config.sub, curl, mikmod, ...) time out
# intermittently from CI runners, which otherwise fails the build mid-download.
RUN printf 'tries = 5\ntimeout = 30\nwaitretry = 15\nretry_connrefused = on\ndns_timeout = 30\nconnect_timeout = 30\n' > /etc/wgetrc

# --- Toolchain environment -----------------------------------------------------------
ENV PS3DEV=/usr/local/ps3dev
ENV PSL1GHT=$PS3DEV
ENV PORTLIBS=$PS3DEV/portlibs/ppu
ENV PATH=$PS3DEV/bin:$PS3DEV/ppu/bin:$PS3DEV/spu/bin:$PATH

WORKDIR /build

# --- ps3toolchain: cross compiler + PSL1GHT + base portlibs (zlib, freetype, ...) ----
# config.guess/config.sub are fetched from git.savannah.gnu.org, which times out
# from CI runners; and the binutils stage's local fetch writes them to build/ rather
# than archives/ where it then looks. So skip Savannah (NO_SAVANNAH) and pre-seed
# archives/ with the fallback copies that ship in the repo. Also work around an
# upstream bug: scripts 008/009 source ../utils/util.sh but the file is utils.sh.
ENV NO_SAVANNAH=1
RUN git clone --depth 1 https://github.com/02900/ps3toolchain.git && \
    mkdir -p ps3toolchain/archives && \
    cp ps3toolchain/config/config.guess ps3toolchain/config/config.sub ps3toolchain/archives/ && \
    cp ps3toolchain/utils/utils.sh ps3toolchain/utils/util.sh && \
    cd ps3toolchain && \
    ./toolchain.sh && \
    rm -rf /build/ps3toolchain

# ps3libraries provides the patches the README applies to PolarSSL.
RUN git clone --depth 1 https://github.com/02900/ps3libraries.git

# Keep the CORE render-agnostic. ps3toolchain's toolchain.sh (above) bundles a baseline
# Tiny3D (libtiny3d + libfont3d + their headers) in the portlibs — strip it so a renderer
# never drags Tiny3D. The tiny3d variant (Dockerfile.tiny3d, FROM this image) reinstalls
# the full render stack (Tiny3D + font3d + YA2D). ps3libraries (cloned above) is kept: it
# provides the PolarSSL/MikMod patches used below.
RUN rm -f $PORTLIBS/lib/libtiny3d.a $PORTLIBS/lib/libfont3d.a \
          $PORTLIBS/include/tiny3d.h $PORTLIBS/include/libfont.h

# --- PolarSSL v1.3.9 -----------------------------------------------------------------
RUN wget --no-check-certificate -O polarssl-${POLARSSL_VER}.gpl.tgz \
        "https://src.fedoraproject.org/repo/pkgs/polarssl/polarssl-${POLARSSL_VER}-gpl.tgz/48af7d1f0d5de512cbd6dacf5407884c/polarssl-${POLARSSL_VER}-gpl.tgz" && \
    tar xfz polarssl-${POLARSSL_VER}.gpl.tgz && \
    cd polarssl-${POLARSSL_VER} && \
    patch -p1 < /build/ps3libraries/patches/polarssl-${POLARSSL_VER}-ipv6.patch && \
    cd library && \
    patch -p1 < /build/ps3libraries/patches/polarssl-${POLARSSL_VER}-net.patch && \
    patch -p1 < /build/ps3libraries/patches/polarssl-${POLARSSL_VER}-timing.patch && \
    sed -i '4d' Makefile && \
    CC=$PS3DEV/ppu/bin/powerpc64-ps3-elf-gcc \
    AR=$PS3DEV/ppu/bin/powerpc64-ps3-elf-ar \
    CFLAGS="-I$(pwd)/../include -I$PS3DEV/ppu/powerpc64-ps3-elf/include -I$PSL1GHT/ppu/include -I$PORTLIBS/include -mcpu=cell" \
        make && \
    cp libpolarssl.a $PORTLIBS/lib/ && \
    cp -R ../include/polarssl $PORTLIBS/include/ && \
    cd /build && rm -rf polarssl-${POLARSSL_VER}*

# --- libcurl v7.64.1 -----------------------------------------------------------------
RUN wget "https://curl.se/download/curl-${CURL_VER}.tar.gz" && \
    wget -O config.guess "http://git.savannah.gnu.org/cgit/config.git/plain/config.guess" && \
    wget -O config.sub "http://git.savannah.gnu.org/cgit/config.git/plain/config.sub" && \
    tar xfz curl-${CURL_VER}.tar.gz && \
    cd curl-${CURL_VER} && \
    cp ../config.guess ../config.sub . && \
    mkdir -p build-ppu && cd build-ppu && \
    AR="ppu-ar" CC="ppu-gcc" RANLIB="ppu-ranlib" \
    CFLAGS="-O2 -Wall" \
    CPPFLAGS="-I$PSL1GHT/ppu/include -I$PORTLIBS/include -I$PSL1GHT/ppu/include/net" \
    LDFLAGS="-L$PSL1GHT/ppu/lib -L$PORTLIBS/lib" \
    LIBS="-lnet -lsysutil -lsysmodule -lm" \
    ../configure --prefix="$PORTLIBS" --host="powerpc64-ps3-elf" \
        --disable-threaded-resolver --disable-ipv6 \
        --without-ssl --with-polarssl="$PORTLIBS/include/polarssl" && \
    make -j"$(nproc)" && \
    cp lib/.libs/libcurl.a $PORTLIBS/lib/ && \
    cp -R ../include/curl $PORTLIBS/include/ && \
    cd /build && rm -rf curl-${CURL_VER}*

# --- MikMod --------------------------------------------------------------------------
RUN wget "http://mikmod.raphnet.net/files/libmikmod-${MIKMOD_VER}.tar.gz" && \
    tar xfz libmikmod-${MIKMOD_VER}.tar.gz && \
    cd libmikmod-${MIKMOD_VER} && \
    patch -p1 < /build/ps3libraries/patches/libmikmod-${MIKMOD_VER}-PPU.patch && \
    mkdir -p build-ppu && cd build-ppu && \
    CFLAGS="-I$PSL1GHT/ppu/include -I$PORTLIBS/include" \
    LDFLAGS="-L$PSL1GHT/ppu/lib -L$PORTLIBS/lib -lrt -llv2" \
    CC="powerpc64-ps3-elf-gcc" RANLIB="powerpc64-ps3-elf-ranlib" \
    ../configure --prefix="$PORTLIBS" --host="powerpc64-ps3-elf" \
        --disable-esd --disable-dl --disable-shared && \
    make -j"$(nproc)" && \
    cp libmikmod/.libs/libmikmod.a $PORTLIBS/lib/ && \
    cp include/mikmod.h $PORTLIBS/include/ && \
    cd /build && rm -rf libmikmod-${MIKMOD_VER}*

# --- Mini18n -------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/02900/mini18n.git && \
    make -C mini18n install && \
    rm -rf mini18n

# --- PSL1GHT header refresh + Python 3 ps3py fix (README steps 5 & 6) -----------------
RUN git clone --depth 1 https://github.com/02900/PSL1GHT.git /tmp/PSL1GHT && \
    cp /tmp/PSL1GHT/ppu/include/sysutil/sysutil.h $PS3DEV/ppu/include/sysutil/ && \
    ln -sf /usr/bin/python3 /usr/bin/python && \
    cp /tmp/PSL1GHT/tools/ps3py/sfo.py /tmp/PSL1GHT/tools/ps3py/pkg.py \
       /tmp/PSL1GHT/tools/ps3py/Struct.py /tmp/PSL1GHT/tools/ps3py/fself.py $PS3DEV/bin/ && \
    2to3 -w $PS3DEV/bin/sfo.py $PS3DEV/bin/pkg.py $PS3DEV/bin/Struct.py $PS3DEV/bin/fself.py && \
    (cd /tmp/PSL1GHT/tools/ps3py && python3 setup.py build_ext --inplace && \
        cp pkgcrypt*.so $PS3DEV/bin/) && \
    rm -rf /tmp/PSL1GHT /build/ps3libraries

WORKDIR /src
