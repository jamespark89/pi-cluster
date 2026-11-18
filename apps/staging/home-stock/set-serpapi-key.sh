#!/usr/bin/env bash
# Sets the SerpApi key Home Stock uses for best prices (Google Shopping), without
# it showing on screen or in shell history, and makes the token the daily
# home-stock-offers job uses, if there isn't one yet.
#   bash set-serpapi-key.sh
set -euo pipefail

read -r -s -p "SerpApi API key (serpapi.com > Dashboard > Your Private API Key): " key
echo
key="${key//[[:space:]]/}"
if [[ ! "$key" =~ ^[A-Za-z0-9]{32,128}$ ]]; then
  echo "That doesn't look like a SerpApi key. Nothing changed." >&2
  exit 1
fi

# Checking the account doesn't use a search. SerpApi takes the key in the URL,
# so give it to curl on stdin (--config -) to keep it out of the process list.
account=$(printf 'url = "https://serpapi.com/account.json?api_key=%s"\n' "$key" | curl -fsS --config - 2>/dev/null) || {
  echo "SerpApi didn't accept that key. Nothing changed." >&2
  exit 1
}
left=$(printf '%s' "$account" | python3 -c 'import sys,json; a=json.load(sys.stdin); print(a.get("total_searches_left", a.get("plan_searches_left","?")))')
plan=$(printf '%s' "$account" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("plan_name","?"))')

token=$(kubectl -n home-stock get secret home-stock-env -o jsonpath='{.data.OFFERS_REFRESH_TOKEN}' | base64 -d 2>/dev/null || true)
[[ -n "$token" ]] || token=$(openssl rand -hex 32)

kubectl -n home-stock patch secret home-stock-env --type merge --patch-file /dev/stdin >/dev/null <<EOF
{"stringData":{"SERPAPI_API_KEY":"$key","OFFERS_REFRESH_TOKEN":"$token"}}
EOF
unset key token
echo "SerpApi key saved (plan: $plan, $left searches left this month)."
kubectl -n home-stock rollout restart deployment/home-stock
kubectl -n home-stock rollout status deployment/home-stock --timeout=180s
