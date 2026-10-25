#!/bin/bash
cd "$(dirname "$0")/src"
pkg install mingw-w64-x86_64-gcc make git libusb libplist libimobiledevice -y
x86_64-w64-mingw32-gcc $(pkg-config --cflags libusb-1.0 libplist-2.0 libimobiledevice-1.0) \
    *.c -o tr4mpass_gui.exe \
    $(pkg-config --libs libusb-1.0 libplist-2.0 libimobiledevice-1.0) \
    -mwindows -static-libgcc -static-libstdc++ -lws2_32 -lgdi32 -lcomctl32
echo "Build complete: tr4mpass_gui.exe"
