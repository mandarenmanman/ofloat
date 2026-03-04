#!/bin/bash
GW=$(docker network inspect bridge | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['IPAM']['Config'][0]['Gateway'])")
echo "Bridge gateway: $GW"

# Also check what Consul resolves for our services
echo "=== Consul services ==="
curl -s http://127.0.0.1:8500/v1/catalog/service/dapr-placement | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f\"{s['ServiceName']}: {s['ServiceAddress'] or s['Address']}:{s['ServicePort']}\") for s in d]"
curl -s http://127.0.0.1:8500/v1/catalog/service/redis | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f\"{s['ServiceName']}: {s['ServiceAddress'] or s['Address']}:{s['ServicePort']}\") for s in d]"
curl -s http://127.0.0.1:8500/v1/catalog/service/dufs | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f\"{s['ServiceName']}: {s['ServiceAddress'] or s['Address']}:{s['ServicePort']}\") for s in d]"
