#!/usr/bin/env bash
set -uo pipefail
SRCDIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$SRCDIR/../prefix-android"
OUT="${GITHUB_WORKSPACE:-$PWD}/out"
LOG="${GITHUB_WORKSPACE:-$SRCDIR/..}/logs"
API=29
TC="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TC/bin/aarch64-linux-android$API-clang"
export CXX="$TC/bin/aarch64-linux-android$API-clang++"
export AR="$TC/bin/llvm-ar" RANLIB="$TC/bin/llvm-ranlib" STRIP="$TC/bin/llvm-strip"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_ALLOW_CROSS=1
export CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export PATH="$TC/bin:$PATH"
HOST=aarch64-linux-android
JOBS=$(nproc 2>/dev/null || echo 4)
mkdir -p "$PREFIX/lib/pkgconfig" "$OUT" "$LOG" /tmp/asrc
cd /tmp/asrc

fetch() { local d="$1" u="$2"; [ -d "$d" ] && return 0
  wget -q --tries=3 -O "$d.tb" "$u" || return 1
  mkdir -p "$d"; tar xf "$d.tb" -C "$d" --strip-components=1 || return 1; }

stage() { local n="$1"; shift; echo "########## START $n ##########"
  if ( set -e; "$@" ) > "$LOG/$n.log" 2>&1; then
    echo "########## OK $n ##########"; return 0
  else echo "########## FAIL $n ##########"; tail -60 "$LOG/$n.log"; return 1; fi }

build_lib() { local d="$1" v="$2" repo="$3"; shift 3
  fetch "$d-$v" "https://github.com/libimobiledevice/$d/releases/download/$v/$d-$v.tar.bz2" \
    || fetch "$d-$v" "https://github.com/$repo/archive/refs/tags/$v.tar.gz" \
    || { rm -rf "$d-$v"; git clone --depth 1 "https://github.com/$repo.git" "$d-$v"; } || return 1
  ( cd "$d-$v" && { [ -f configure ] || NOCONFIGURE=1 ./autogen.sh; } \
    && ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared "$@" \
    && make -j"$JOBS" && make install ) }

s_openssl() { fetch openssl-3.0.15 https://github.com/openssl/openssl/releases/download/openssl-3.0.15/openssl-3.0.15.tar.gz || return 1
  cd openssl-3.0.15 && ./Configure android-arm64 -D__ANDROID_API__=$API no-shared no-tests \
    --prefix="$PREFIX" && make -j"$JOBS" build_libs && make install_sw; }

s_libusb() { fetch libusb-1.0.27 https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.27.tar.bz2 || return 1
  cd libusb-1.0.27 && ./configure --host="$HOST" --prefix="$PREFIX" \
    --enable-static --disable-shared --disable-udev && make -j"$JOBS" && make install; }

# libplist 2.3.0: 2.6.0 clashes with libimobiledevice 1.3.0 (PLIST_FORMAT_* redefinition)
# --without-cython alone does NOT reliably skip the Python devel check in this release's
# configure (confirmed by CI log: full Python probe still ran and fatally failed trying
# to link host x86_64 libpython against the aarch64 cross toolchain). Forcing CYTHON=false
# pre-empts AC_PATH_PROG's own detection, so AC_PROG_CYTHON short-circuits before the
# Python-devel/link check ever runs.
s_plist() { build_lib libplist 2.3.0 libimobiledevice/libplist --without-cython CYTHON=false; }

s_curl() { fetch curl-8.4.0 https://curl.se/download/curl-8.4.0.tar.xz || return 1
  cd curl-8.4.0 && ./configure --host="$HOST" --prefix="$PREFIX" \
    --enable-static --disable-shared --with-openssl="$PREFIX" \
    --without-libpsl --without-libidn2 --without-brotli --without-zstd \
    --without-nghttp2 --disable-ldap --disable-ldaps && make -j"$JOBS" && make install; }

# libssh2 with OpenSSL backend (wincng is Windows-only)
s_ssh2() { fetch libssh2-1.11.1 https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.gz || return 1
  cd libssh2-1.11.1 && ./configure --host="$HOST" --prefix="$PREFIX" \
    --enable-static --disable-shared --with-crypto=openssl --with-libssl-prefix="$PREFIX" \
    --without-libz --disable-examples-build && make -j"$JOBS" && make install; }

s_usbmuxd() { build_lib libusbmuxd 2.0.2 libimobiledevice/libusbmuxd; }

# libirecovery: tag 1.0.1 requires readline unconditionally; master has --without-tools
s_irecv() { rm -rf libirecovery-m; git clone --depth 1 https://github.com/libimobiledevice/libirecovery.git libirecovery-m || return 1
  cd libirecovery-m && NOCONFIGURE=1 ./autogen.sh \
    && ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared --without-tools \
    && make -j"$JOBS" && make install; }

s_glue() { build_lib libimobiledevice-glue 1.0.0 libimobiledevice/libimobiledevice-glue; }

s_imd() { build_lib libimobiledevice 1.3.0 libimobiledevice/libimobiledevice \
  --without-cython ac_cv_lib_pthread_pthread_once=yes; }

stage openssl  s_openssl  || true
stage libusb   s_libusb   || true
stage libplist s_plist    || true
stage curl     s_curl     || true
stage libssh2  s_ssh2     || true
stage usbmuxd  s_usbmuxd  || true
stage irecovery s_irecv   || true
stage glue     s_glue     || true
stage imobiledevice s_imd || true
