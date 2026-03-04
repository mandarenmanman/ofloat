#!/bin/bash
# Test if bridge container can reach host services via 172.17.0.1
echo "Testing 172.17.0.1:5555 (dufs)..."
docker run --rm --network bridge curlimages/curl:latest -s -o /dev/null -w "%{http_code}" http://172.17.0.1:5555/ 2>/dev/null || \
  docker run --rm --network bridge alpine:latest wget -q -O /dev/null http://172.17.0.1:5555/ 2>&1

echo "Testing 192.168.3.63:5555 (dufs via LAN)..."
docker run --rm --network bridge curlimages/curl:latest -s -o /dev/null -w "%{http_code}" http://192.168.3.63:5555/ 2>/dev/null || echo "failed"
