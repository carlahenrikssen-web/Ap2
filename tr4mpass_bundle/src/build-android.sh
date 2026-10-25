#!/usr/bin/env bash
set -uo pipefail
SRCDIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$SRCDIR/../prefix-android"
OUT="${GITHUB_WORKSPACE:-$PWD}/out"
API=29
TOOLCHAIN="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TOOLCHAIN/bin/aarch64-linux-android$API-clang"
export CXX="$TOOLCHAIN/bin/aarch64-linux-android$API-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar" RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_ALLOW_CROSS=1 CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export PATH="$TOOLCHAIN/bin:$PATH"
HOST=aarch64-linux-android
JOBS=$(nproc 2>/dev/null || echo 4)
mkdir -p "$PREFIX/lib/pkgconfig" "$OUT" /tmp/asrc
cd /tmp/asrc

fetch() { local d="$1" u="$2"; [ -d "$d" ] && return 0
  wget -q --tries=3 -O "$d.tb" "$u" || return 1
  mkdir -p "$d"; tar xf "$d.tb" -C "$d" --strip-components=1 || return 1; }

build_lib() { local d="$1" v="$2" repo="$3"; shift 3
  fetch "$d-$v" "https://github.com/libimobiledevice/$d/releases/download/$v/$d-$v.tar.bz2" \
   || fetch "$d-$v" "https://github.com/$repo/archive/refs/tags/$v.tar.gz" \
   || { rm -rf "$d-$v"; git clone --depth 1 "https://github.com/$repo.git" "$d-$v"; } || { echo "FAIL-download $d"; return 1; }
  ( cd "$d-$v" && { [ -f configure ] || NOCONFIGURE=1 ./autogen.sh; } \
      && ./configure --host="$HOST" --prefix="$PREFIX" --enable-static --disable-shared "$@" \
      && make -j"$JOBS" && make install ) || { echo "FAIL-build $d"; return 1; } }

fetch openssl-3.0.15 https://github.com/openssl/openssl/releases/download/openssl-3.0.15/openssl-3.0.15.tar.gz \
 && ( cd openssl-3.0.15 && ./Configure android-arm64 -D__ANDROID_API__=$API no-shared no-tests \
      --prefix="$PREFIX" && make -j"$JOBS" build_libs && make install_sw ) || echo "FAIL openssl (continuing)"

fetch libusb-1.0.27 https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.27.tar.bz2 \
 && ( cd libusb-1.0.27 && ./configure --host="$HOST" --prefix="$PREFIX" \
      --enable-static --disable-shared --disable-udev && make -j"$JOBS" && make install ) || echo "FAIL libusb (continuing)"

build_lib libplist 2.6.0 libimobiledevice/libplist || true
build_lib libimobiledevice-glue 1.0.0 libimobiledevice/libimobiledevice-glue || true
build_lib libusbmuxd 2.0.2 libimobiledevice/libusbmuxd || true

# curl for Android (tatsu requires libcurl.pc)
fetch curl-8.4.0 https://curl.se/download/curl-8.4.0.tar.xz \
 && ( cd curl-8.4.0 && ./configure --host="$HOST" --prefix="$PREFIX" \
      --enable-static --disable-shared --with-openssl="$PREFIX" \
      --without-libpsl --without-libidn2 --without-brotli --without-zstd \
      --without-nghttp2 --disable-ldap --disable-ldaps \
      && make -j"$JOBS" && make install ) || echo "FAIL curl (continuing)"

# irecovery: --without-tools avoids the readline requirement
build_lib libirecovery 1.0.1 libimobiledevice/libirecovery --without-tools || true

# tatsu: needs libcurl (built above)
build_lib libtatsu 1.0.3 libimobiledevice/libtatsu || true

# imobiledevice: bionic has pthread in libc -> pre-seed the pthread_once check
build_lib libimobiledevice 1.3.0 libimobiledevice/libimobiledevice \
  --without-cython ac_cv_lib_pthread_pthread_once=yes || true

echo "===== pkg-config visibility ====="
LIBS="libusb-1.0 libplist-2.0 libimobiledevice-glue-1.0 libusbmuxd-2.0 libirecovery-1.0 libtatsu-1.0 libimobiledevice-1.0"
for p in $LIBS; do pkg-config --exists "$p" && echo "OK $p" || echo "MISSING $p"; done

cd "$SRCDIR"
CF="$(pkg-config --cflags $LIBS 2>/dev/null || true)"
LF="$(pkg-config --static --libs $LIBS 2>/dev/null || true)"
SRCS=$(find src -name '*.c' ! -name '*.o' | tr '\n' ' ')
echo "compiling: $SRCS"
$CC -O2 -std=c99 -D_GNU_SOURCE -Iinclude $CF $SRCS -o "$OUT/tr4mpass-arm64" $LF -lm -llog \
 || { echo "BUILD FAILED — see missing headers/libs above"; exit 1; }
ls -l "$OUT/tr4mpass-arm64"
