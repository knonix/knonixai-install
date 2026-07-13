#!/usr/bin/env bash
# Build and push a customer-safe ghcr.io/knonix/knonixai image with the health
# auth fix baked in. Requires docker login to ghcr.io with write:packages.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${IMAGE:-ghcr.io/knonix/knonixai}"
BASE="${BASE_IMAGE:-${IMAGE}:latest}"
DATE_TAG="fixed-health-$(date -u +%Y%m%d)"
PUSH="${PUSH:-true}"

echo "==> Base: ${BASE}"
docker pull "${BASE}"

echo "==> Build fixed image"
docker build \
  --build-arg "BASE_IMAGE=${BASE}" \
  -f Dockerfile.fix-public-image \
  -t "${IMAGE}:${DATE_TAG}" \
  -t "${IMAGE}:latest" \
  .

echo "==> Verify patch inside image"
docker run --rm --entrypoint node "${IMAGE}:latest" -e '
const fs=require("fs");const path=require("path");
function walk(d,a=[]){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);if(e.isDirectory())walk(p,a);else if(e.name.endsWith(".js"))a.push(p);}return a;}
const OLD="authConfigured:!n||!!\"\".trim()&&!!\"\".trim()";
const NEW="process.env.NEXT_PUBLIC_SUPABASE_URL";
let bad=0, good=0;
for (const f of walk("/app/.next/server")) {
  const t=fs.readFileSync(f,"utf8");
  if (t.includes(OLD)) { console.error("STILL_BROKEN", f); bad++; }
  if (t.includes("authConfigured") && t.includes(NEW)) good++;
}
if (bad) process.exit(1);
console.log("ok good_chunks=", good);
'

if [[ "${PUSH}" == "true" ]]; then
  echo "==> Push ${IMAGE}:${DATE_TAG} and :latest"
  docker push "${IMAGE}:${DATE_TAG}"
  docker push "${IMAGE}:latest"
  echo "Published. Customers: docker pull ${IMAGE}:latest && re-run install or compose up -d"
else
  echo "PUSH=false — local tags only: ${IMAGE}:${DATE_TAG} ${IMAGE}:latest"
fi
