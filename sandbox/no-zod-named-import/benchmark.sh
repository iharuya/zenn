#!/bin/bash

set -e

echo "=== Zod Import Method Benchmark ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# esbuildのパス
ESBUILD="./node_modules/.bin/esbuild"

# ビルド関数
build_and_measure() {
    local name=$1
    local entry=$2
    local output=$3

    echo "Building: $name"

    # ビルド時間計測（5回実行して平均）
    local total_time=0
    for i in {1..5}; do
        start=$(date +%s%N)
        $ESBUILD "$entry" --bundle --minify --outfile="$output" --format=esm --platform=node 2>/dev/null
        end=$(date +%s%N)
        elapsed=$(( (end - start) / 1000000 ))
        total_time=$((total_time + elapsed))
    done
    avg_time=$((total_time / 5))

    # ファイルサイズ取得
    size=$(stat --printf="%s" "$output")
    size_kb=$(echo "scale=2; $size / 1024" | bc)

    # gzip後のサイズ
    gzip -c "$output" > "${output}.gz"
    gzip_size=$(stat --printf="%s" "${output}.gz")
    gzip_size_kb=$(echo "scale=2; $gzip_size / 1024" | bc)
    rm "${output}.gz"

    echo "  Size: ${size_kb} KB (${gzip_size_kb} KB gzipped)"
    echo "  Build time (avg of 5): ${avg_time} ms"
    echo ""
}

echo "--- Results ---"
echo ""

build_and_measure "import { z } from 'zod'" \
    "named-import/index.ts" \
    "dist/named-import.js"

build_and_measure "import * as z from 'zod'" \
    "namespace-import/index.ts" \
    "dist/namespace-import.js"

build_and_measure "import * as z from 'zod/mini'" \
    "mini-import/index.ts" \
    "dist/mini-import.js"

echo "--- Summary ---"
echo ""
echo "Output files in dist/:"
ls -lh dist/*.js | awk '{print "  " $9 ": " $5}'
