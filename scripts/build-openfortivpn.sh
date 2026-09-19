#!/bin/bash
set -euo pipefail

OPENFORTIVPN_VERSION="1.24.1"
OPENFORTIVPN_SHA256="c40d33acd97b89c2e943bfd839c19b69e5a7a5997052e2fc9a595602745c0465"
OPENSSL_VERSION="3.5.8"
OPENSSL_SHA256="a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-26.0}"
ARCHITECTURES="${ARCHITECTURES:-arm64 x86_64}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/.build/openfortivpn}"
OUTPUT_PATH="${OUTPUT_PATH:-${BUILD_DIR}/openfortivpn}"
SOURCES_OUTPUT_DIR="${SOURCES_OUTPUT_DIR:-}"

for command in autoconf automake curl lipo make perl pkg-config shasum tar xcrun; do
    command -v "$command" >/dev/null || {
        echo "Required build command not found: $command" >&2
        exit 1
    }
done

mkdir -p "$BUILD_DIR" "$(dirname "$OUTPUT_PATH")"
DOWNLOAD_DIR="$BUILD_DIR/downloads"
mkdir -p "$DOWNLOAD_DIR"

fetch() {
    local url="$1"
    local sha256="$2"
    local destination="$3"

    if [[ ! -f "$destination" ]] || ! echo "$sha256  $destination" | shasum -a 256 --check --status; then
        rm -f "$destination"
        curl --fail --location --retry 3 --output "$destination" "$url"
    fi
    echo "$sha256  $destination" | shasum -a 256 --check --status || {
        echo "Checksum verification failed for $destination" >&2
        exit 1
    }
}

OPENFORTIVPN_ARCHIVE="$DOWNLOAD_DIR/openfortivpn-${OPENFORTIVPN_VERSION}.tar.gz"
OPENSSL_ARCHIVE="$DOWNLOAD_DIR/openssl-${OPENSSL_VERSION}.tar.gz"
fetch \
    "https://github.com/adrienverge/openfortivpn/archive/refs/tags/v${OPENFORTIVPN_VERSION}.tar.gz" \
    "$OPENFORTIVPN_SHA256" \
    "$OPENFORTIVPN_ARCHIVE"
fetch \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" \
    "$OPENSSL_SHA256" \
    "$OPENSSL_ARCHIVE"

if [[ -n "$SOURCES_OUTPUT_DIR" ]]; then
    mkdir -p "$SOURCES_OUTPUT_DIR"
    cp "$OPENFORTIVPN_ARCHIVE" "$SOURCES_OUTPUT_DIR/openfortivpn-${OPENFORTIVPN_VERSION}.tar.gz"
    cp "$OPENSSL_ARCHIVE" "$SOURCES_OUTPUT_DIR/openssl-${OPENSSL_VERSION}.tar.gz"
fi

binaries=()
for architecture in $ARCHITECTURES; do
    case "$architecture" in
        arm64)
            openssl_target="darwin64-arm64-cc"
            ;;
        x86_64)
            openssl_target="darwin64-x86_64-cc"
            ;;
        *)
            echo "Unsupported architecture: $architecture" >&2
            exit 1
            ;;
    esac

    architecture_dir="$BUILD_DIR/$architecture"
    openssl_source="$architecture_dir/openssl-source"
    openssl_prefix="$architecture_dir/openssl-prefix"
    openfortivpn_source="$architecture_dir/openfortivpn-source"
    rm -rf "$openssl_source" "$openssl_prefix" "$openfortivpn_source"
    mkdir -p "$architecture_dir" "$openssl_source" "$openfortivpn_source"

    tar -xzf "$OPENSSL_ARCHIVE" -C "$openssl_source" --strip-components=1
    (
        cd "$openssl_source"
        perl ./Configure \
            "$openssl_target" \
            no-apps \
            no-docs \
            no-shared \
            no-tests \
            "--prefix=$openssl_prefix" \
            "--openssldir=/etc/ssl" \
            "-arch $architecture" \
            "-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET"
        make -j"$(sysctl -n hw.logicalcpu)"
        make install_sw
    )

    tar -xzf "$OPENFORTIVPN_ARCHIVE" -C "$openfortivpn_source" --strip-components=1
    (
        cd "$openfortivpn_source"
        ./autogen.sh
        sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
        export CC="$(xcrun --find clang)"
        export CFLAGS="-O2 -arch $architecture -isysroot $sdk_path -mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET"
        export CPPFLAGS="-I$openssl_prefix/include"
        export LDFLAGS="-arch $architecture -isysroot $sdk_path -mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET -L$openssl_prefix/lib"
        export PKG_CONFIG_PATH="$openssl_prefix/lib/pkgconfig"
        ./configure \
            --disable-dependency-tracking \
            --disable-proc \
            --disable-resolvconf \
            --with-netstat=/usr/sbin/netstat \
            --with-pppd=/usr/sbin/pppd \
            --with-resolvconf=DISABLED
        make -j"$(sysctl -n hw.logicalcpu)"
    )

    binary="$openfortivpn_source/openfortivpn"
    test -x "$binary"
    if otool -L "$binary" | tail -n +2 | awk '{print $1}' | grep -Ev '^(/usr/lib/|/System/Library/)' >/dev/null; then
        echo "openfortivpn has a non-system dynamic dependency:" >&2
        otool -L "$binary" >&2
        exit 1
    fi
    binaries+=("$binary")
done

if [[ ${#binaries[@]} -eq 1 ]]; then
    cp "${binaries[0]}" "$OUTPUT_PATH"
else
    lipo -create "${binaries[@]}" -output "$OUTPUT_PATH"
fi
chmod 0555 "$OUTPUT_PATH"

for architecture in $ARCHITECTURES; do
    lipo "$OUTPUT_PATH" -verify_arch "$architecture"
done

actual_version="$($OUTPUT_PATH --version 2>&1 | head -n 1)"
if [[ "$actual_version" != "$OPENFORTIVPN_VERSION" ]]; then
    echo "Unexpected openfortivpn version: $actual_version" >&2
    exit 1
fi

printf 'Built %s\n' "$OUTPUT_PATH"
lipo -archs "$OUTPUT_PATH"
otool -L "$OUTPUT_PATH"
