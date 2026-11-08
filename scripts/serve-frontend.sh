#!/usr/bin/env bash
# Menjalankan server web lokal untuk frontend simulasi.
# Pemakaian: scripts/serve-frontend.sh [port]   (bawaan 5180)
# Port 8080 tidak dipakai sebagai bawaan karena sering sudah dipakai program Windows.
set -euo pipefail
cd "$(dirname "$0")/../frontend"
PORT="${1:-5180}"
while ss -ltnH "sport = :$PORT" | grep -q .; do
  echo "Port $PORT sedang dipakai, mencoba $((PORT + 1))"
  PORT=$((PORT + 1))
done
[ -f config.js ] || { echo "frontend/config.js belum ada. Jalankan dulu: scripts/deploy.sh anvil|besu" >&2; exit 1; }
echo "Buka di browser Windows: http://localhost:$PORT"
echo "Jika halaman tidak terbuka, port itu mungkin dipakai program Windows. Coba: $0 8090"
echo "Tekan Ctrl+C untuk berhenti."
exec python3 -m http.server "$PORT" --bind 127.0.0.1
