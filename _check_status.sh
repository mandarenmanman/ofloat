#!/bin/bash
# Check latest allocation for spin-js-app
curl -s http://localhost:4646/v1/job/spin-js-app/allocations | python3 -c "
import sys, json
allocs = json.load(sys.stdin)
allocs.sort(key=lambda a: a['CreateTime'], reverse=True)
for a in allocs[:3]:
    print(f\"ID: {a['ID'][:8]}  Status: {a['ClientStatus']}  Desc: {a.get('ClientDescription','')}  Ver: {a['JobVersion']}\")
"
