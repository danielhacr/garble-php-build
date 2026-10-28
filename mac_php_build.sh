#!/bin/bash
# tools/mac_php_build.sh: the Mac bundle's PHP, built on the Mac mini from php.net's source (docs/ref/macarm/PLAN.md §3.1,
# Daniel's choice: no prebuilt binary), static, one architecture a run, with static-php-cli's build tool at a pinned
# release (its own copy per architecture: each keeps its built libraries). Never --prefer-pre-built.
#   tools/mac_php_build.sh x86_64|arm64 [php series, default 8.4]
# Output: ~/gd-php/out/php-<version>-macos-<arch>, and a line in ~/gd-php/out/build.txt (version, arch, sha256, the
# extensions php -m lists when it can run here). Logs: ~/gd-php/<arch>.log
set -euo pipefail
ARCH="${1:?x86_64 or arm64}"
SERIES="${2:-8.4}"
SPC_TAG="2.8.5"            # static-php-cli, pinned (its commit 4318ef8fa32a02460ec1554746674a7bc42b49fa)
SPC_COMMIT="4318ef8fa32a02460ec1554746674a7bc42b49fa"
EXTS="ctype,filter,mbstring,openssl,pcntl,posix,sockets,zlib,tokenizer"
ROOT="$HOME/gd-php"
WORK="$ROOT/spc-$ARCH"
OUT="$ROOT/out"
mkdir -p "$OUT"
if [ ! -d "$WORK" ]; then
  git clone -q --depth 1 -b "$SPC_TAG" https://github.com/crazywhalecc/static-php-cli.git "$WORK"
fi
cd "$WORK"
if [ "$(git rev-parse HEAD)" != "$SPC_COMMIT" ]; then echo "static-php-cli is not the pinned commit" >&2; exit 2; fi
export PATH="$WORK/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# (the oldest macOS both builds run on: the first with Apple Silicon; every library inherits it)
export MACOSX_DEPLOYMENT_TARGET=11.0
if [ "$ARCH" = "arm64" ]; then
  # (a cross build on the Intel Mac mini: the target arch for clang and for the libraries' --host)
  export MAC_ARCH=arm64 GNU_ARCH=aarch64 SPC_ARCH=arm64
fi
[ -x bin/php ] || ./bin/setup-runtime >/dev/null
[ -d vendor ] || composer install --no-dev -q
./bin/spc doctor --auto-fix
./bin/spc download --with-php="$SERIES" --for-extensions="$EXTS"
# (macarm code r1, Kimi 6: spc doesn't check php.net's published hash; this does, before anything is built)
SRC="downloads/$(/usr/bin/python3 -c 'import json; print(json.load(open("downloads/.lock.json"))["php-src"]["filename"])')"
case "$SRC" in downloads/php-"$SERIES".*.tar.xz) ;; *) echo "spc's php-src is $SRC, not a $SERIES tar.xz" >&2; exit 3 ;; esac
SRCVER="$(basename "$SRC" .tar.xz | sed 's/^php-//')"
WANT="$(curl -fsSL "https://www.php.net/releases/index.php?json&version=$SRCVER" | /usr/bin/python3 -c 'import json,sys,os; print(next(s["sha256"] for s in json.load(sys.stdin)["source"] if s["filename"] == sys.argv[1]))' "$(basename "$SRC")")"
GOT="$(shasum -a 256 "$SRC" | cut -d' ' -f1)"
if [ -z "$WANT" ] || [ "$WANT" != "$GOT" ]; then echo "php.net's SHA-256 for $SRC is '$WANT', the download's $GOT" >&2; exit 3; fi
echo "source $SRC: php.net's SHA-256 $GOT"
./bin/spc build "$EXTS" --build-cli
BIN="$WORK/buildroot/bin/php"
VER="$(strings "$BIN" | grep -m1 -E '^X-Powered-By: PHP/' | sed 's/.*PHP\///' || true)"
[ -n "$VER" ] || VER="$("$BIN" -r 'echo PHP_VERSION;' 2>/dev/null || echo unknown)"
DEST="$OUT/php-$VER-macos-$ARCH"
cp "$BIN" "$DEST"
SHA="$(shasum -a 256 "$DEST" | cut -d' ' -f1)"
MODS="$("$DEST" -m 2>/dev/null | tr '\n' ' ' || echo '(not runnable here)')"
echo "$VER $ARCH $SHA exts=[$EXTS] runs=[$MODS] spc=$SPC_TAG target=$MACOSX_DEPLOYMENT_TARGET source_sha256=$GOT" >> "$OUT/build.txt"
echo "built $DEST ($SHA)"
