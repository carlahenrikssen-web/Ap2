#!/data/data/com.termux/files/usr/bin/bash
export HOST=i686-w64-mingw32
export PREFIX="$HOME/win32"
export SRC="$HOME/src"
export LOGS="$HOME/41/logs"
export CONFIG_SHELL=/data/data/com.termux/files/usr/bin/bash
export SHELL=$CONFIG_SHELL
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_ALLOW_CROSS=1
export CFLAGS="-O2 -std=gnu17"
export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export LIBS="-lcrypt32 -lws2_32 -lgdi32 -luser32 -ladvapi32"
export CPPFLAGS="$CPPFLAGS -DLIMD_GLUE_STATIC -DLIBPLIST_STATIC -DLIBUSBMUXD_STATIC -DLIBIRECOVERY_STATIC -DLIBTATSU_STATIC -DLIBIMOBILEDEVICE_STATIC"
mkdir -p "$PREFIX/lib/pkgconfig" "$SRC" "$LOGS"
command -v $HOST-gcc >/dev/null \
  || { echo "NO_CROSS_GCC"; exit 1; }
CFG="--host=$HOST --build=$(gcc -dumpmachine)"
CFG="$CFG --prefix=$PREFIX --disable-shared --enable-static"
GH=https://github.com

runlog() {
  local n=$1; shift
  echo "##### START $n"
  if "$@" > "$LOGS/$n.log" 2>&1; then
    echo "##### OK $n"
  else
    echo "##### FAIL $n  ($LOGS/$n.log)"
    tail -25 "$LOGS/$n.log"
    return 1
  fi
}

# git repo: name url fallback-version [configure args]
b_git() (
  n=$1; url=$2; ver=$3; shift 3
  [ -d "$SRC/$n/.git" ] || git clone "$url" "$SRC/$n" || exit 1
  cd "$SRC/$n" || exit 1
  git fetch --tags -q
  git clean -fdxq
  git describe --tags >/dev/null 2>&1 \
    || echo "$ver" > .tarball-version
  NOCONFIGURE=1 "$CONFIG_SHELL" ./autogen.sh || exit 1
  "$CONFIG_SHELL" ./configure $CFG "$@" || exit 1
  make -j"$(nproc)" || exit 1
  make install
)

# tarball: name url dir [configure args]
b_tar() (
  n=$1; url=$2; dir=$3; shift 3
  cd "$SRC" || exit 1
  f="${url##*/}"
  [ -s "$f" ] || curl -fL -o "$f" "$url" || exit 1
  rm -rf "$dir"
  tar xf "$f" || exit 1
  cd "$dir" || exit 1
  "$CONFIG_SHELL" ./configure $CFG "$@" || exit 1
  make -j"$(nproc)" || exit 1
  make install
)

b_ossl() (
  v=3.0.15
  f=openssl-$v.tar.gz
  cd "$SRC" || exit 1
  [ -s "$f" ] || curl -fL -o "$f" \
    "$GH/openssl/openssl/releases/download/openssl-$v/$f" \
    || exit 1
  rm -rf openssl-$v
  tar xf "$f" || exit 1
  cd openssl-$v || exit 1
  ./Configure mingw --cross-compile-prefix=$HOST- \
    --prefix="$PREFIX" --libdir=lib no-shared no-tests \
    || exit 1
  make -j"$(nproc)" build_libs || exit 1
  make install_dev
)

CURLV=8.11.1
CURLU="$GH/curl/curl/releases/download/curl-8_11_1"
SSHU="$GH/libssh2/libssh2/releases/download/libssh2-1.11.1"

runlog libimobiledevice b_git libimobiledevice \
     $GH/libimobiledevice/libimobiledevice.git 1.4.0 \
     --without-cython

echo "########## SUMMARY ##########"
for p in openssl libcurl libusb-1.0 libssh2 libplist-2.0 \
  libimobiledevice-glue-1.0 libusbmuxd-2.0 \
  libirecovery-1.0 libtatsu-1.0 libimobiledevice-1.0; do
  if pkg-config --exists $p; then
    echo "OK       $p $(pkg-config --modversion $p)"
  else
    echo "MISSING  $p"
  fi
done
