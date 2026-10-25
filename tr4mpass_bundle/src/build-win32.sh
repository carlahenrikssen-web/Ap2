#!/usr/bin/env bash
set -uo pipefail
HOST=i686-w64-mingw32
BUILD=$(gcc -dumpmachine)
PREFIX="$HOME/win32"
SRC="$HOME/bsrc"
LOGDIR="${GITHUB_WORKSPACE:-$PWD}/logs"
JOBS="$(nproc 2>/dev/null || echo 4)"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_ALLOW_CROSS=1
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
mkdir -p "$PREFIX/lib/pkgconfig" "$PREFIX/include" "$SRC" "$LOGDIR"
RESULTS=()
WINLIBS="-lws2_32 -lcrypt32 -lsecur32 -lbcrypt -ladvapi32 -lgdi32 -luser32 -liphlpapi"

run_stage() {
  local name="$1"; shift
  local lf="$LOGDIR/$name.log"
  echo "########## START $name ##########"
  if ( set -e; "$@" ) > "$lf" 2>&1; then
    RESULTS+=("OK|$name"); echo "########## OK $name ##########"
  else
    RESULTS+=("FAIL|$name"); echo "########## FAIL $name ##########"
    tail -30 "$lf" || true
  fi
}

fetch() {
  local d="$1" u="$2" t
  cd "$SRC" || return 1
  t="$(basename "$u")"
  [ -s "$t" ] || wget -q --tries=3 -O "$t" "$u" || return 1
  rm -rf "$d"; tar xf "$t" || return 1
  [ -d "$d" ]
}

conf_make_install() {
  ./configure --host="$HOST" --build="$BUILD" --prefix="$PREFIX" \
    --enable-static --disable-shared "$@"
  make -j"$JOBS"
  make install
}

gh_lib() {
  local d="$1" v="$2" repo="$3"; shift 3
  fetch "$d-$v" "https://github.com/libimobiledevice/$d/releases/download/$v/$d-$v.tar.bz2" \
    || fetch "$d-$v" "https://github.com/$repo/archive/refs/tags/$v.tar.gz" \
    || { cd "$SRC" && rm -rf "$d-$v" && git clone --depth 1 "https://github.com/$repo.git" "$d-$v"; } || return 1
  cd "$SRC/$d-$v" || return 1
  [ -f configure ] || NOCONFIGURE=1 ./autogen.sh
  conf_make_install "$@"
}

s_openssl() {
  local v=3.0.15
  fetch "openssl-$v" "https://github.com/openssl/openssl/releases/download/openssl-$v/openssl-$v.tar.gz" || return 1
  cd "$SRC/openssl-$v" || return 1
  ./Configure mingw no-shared no-tests no-asm --prefix="$PREFIX" --cross-compile-prefix="$HOST-"
  make -j"$JOBS" build_libs
  make install_sw
  for p in "openssl:OpenSSL:-lssl -lcrypto" "libcrypto:libcrypto:-lcrypto" "libssl:libssl:-lssl -lcrypto"; do
    n="${p%%:*}"; r="${p#*:}"; desc="${r%%:-*}" ; desc="${r%%:*}"; libs="${r#*:}"
    printf "prefix=%s\nlibdir=\${prefix}/lib\nincludedir=\${prefix}/include\n\nName: %s\nDescription: %s\nVersion: %s\nLibs: -L\${libdir} %s\nLibs.private: %s\nCflags: -I\${includedir}\n" \
      "$PREFIX" "$n" "$desc" "$v" "$libs" "$WINLIBS" > "$PREFIX/lib/pkgconfig/$n.pc"
  done
}

s_libusb() {
  local v=1.0.27
  fetch "libusb-$v" "https://github.com/libusb/libusb/releases/download/v$v/libusb-$v.tar.bz2" || return 1
  cd "$SRC/libusb-$v" || return 1
  conf_make_install --disable-udev
}

s_curl() {
  local v=8.4.0
  fetch "curl-$v" "https://curl.se/download/curl-$v.tar.xz" || return 1
  cd "$SRC/curl-$v" || return 1
  ./configure --host="$HOST" --build="$BUILD" --prefix="$PREFIX" \
    --enable-static --disable-shared --with-openssl="$PREFIX" \
    --without-libpsl --without-libidn2 --without-brotli --without-zstd \
    --without-nghttp2 --disable-ldap --disable-ldaps
  make -j"$JOBS"; make install
}

s_ssh2() {
  local v=1.11.1
  fetch "libssh2-$v" "https://github.com/libssh2/libssh2/releases/download/libssh2-$v/libssh2-$v.tar.gz" || return 1
  cd "$SRC/libssh2-$v" || return 1
  ./configure --host="$HOST" --build="$BUILD" --prefix="$PREFIX" \
    --enable-static --disable-shared --with-crypto=wincng \
    --without-libz --disable-examples-build
  make -j"$JOBS"; make install
}

run_stage openssl          s_openssl
run_stage libusb           s_libusb
run_stage libplist         gh_lib libplist 2.4.0 libimobiledevice/libplist
run_stage curl             s_curl
run_stage libssh2          s_ssh2
run_stage libusbmuxd       gh_lib libusbmuxd 2.0.2 libimobiledevice/libusbmuxd
run_stage libirecovery     gh_lib libirecovery 1.0.1 libimobiledevice/libirecovery
run_stage tatsu            gh_lib libtatsu 1.0.3 libimobiledevice/libtatsu
run_stage libimobiledevice gh_lib libimobiledevice 1.3.0 libimobiledevice/libimobiledevice --without-cython

{
  echo "########## SUMMARY ##########"
  for r in "${RESULTS[@]}"; do echo "${r/|/  }"; done
  for p in openssl libusb-1.0 libplist-2.0 libirecovery-1.0 libtatsu-1.0 libimobiledevice-1.0 libssh2 libcurl; do
    if pkg-config --exists "$p"; then echo "OK       $p $(pkg-config --modversion "$p")"; else echo "MISSING  $p"; fi
  done
} | tee "$LOGDIR/summary.txt"

mkdir -p win32dll && cp -f "$PREFIX/bin/"*.dll win32dll/ 2>/dev/null || true
