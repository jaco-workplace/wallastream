#!/bin/zsh
# Bouwt OwnTone (en libinotify-kqueue) vanaf de broncode naar ./runtime.
# Gebaseerd op OwnTone's eigen macOS-CI: .github/workflows/macos.yml
set -euo pipefail
ROOT="${0:A:h:h}"
PREFIX="$ROOT/runtime/usr"
# Geteste OwnTone-commit (29.3-dev, okt 2026); overschrijf met OWNTONE_REF=<tag/commit>.
OWNTONE_REF="${OWNTONE_REF:-8dfd6db1d0b032bff2e131e563b5e09cf2ea41ad}"
B="$(brew --prefix)"

brew install automake autoconf libtool pkg-config gettext gperf bison flex \
  libunistring confuse libplist libwebsockets libevent libgcrypt json-c \
  protobuf-c libsodium openssl ffmpeg sqlite dylibbundler

mkdir -p "$ROOT/vendor/bin"
cd "$ROOT/vendor"
[ -d libinotify-kqueue ] || git clone --depth 1 https://github.com/libinotify-kqueue/libinotify-kqueue
[ -d owntone-server ] || git clone https://github.com/owntone/owntone-server
git -C owntone-server checkout -q "$OWNTONE_REF"

# macOS heeft te oude bison/flex; die van Homebrew zijn keg-only.
ln -sf "$B/opt/bison/bin/bison" bin/bison
ln -sf "$B/opt/flex/bin/flex" bin/flex
export PATH="$ROOT/vendor/bin:$PATH"

(cd libinotify-kqueue && autoreconf -fi && ./configure --prefix="$PREFIX" && make && make install)

export ACLOCAL_PATH="$B/share/gettext/m4:${ACLOCAL_PATH:-}"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$B/opt/sqlite/lib/pkgconfig:$B/opt/openssl/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export CFLAGS="-I$B/include -I$B/opt/sqlite/include -I$PREFIX/include"
export LDFLAGS="-L$B/lib -L$B/opt/sqlite/lib -L$PREFIX/lib"

cd owntone-server
autoreconf -fi
./configure --prefix="$PREFIX" --sysconfdir="$ROOT/runtime/etc" --localstatedir="$ROOT/runtime/var"
make -j"$(sysctl -n hw.ncpu)"
make install

echo "OwnTone $(git rev-parse --short HEAD) geïnstalleerd in $PREFIX"
