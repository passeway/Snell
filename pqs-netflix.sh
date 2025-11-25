#!/usr/bin/env bash

set -euo pipefail

IP_MODE="-4"
MAX_TRIES=10
WAIT_AFTER_SWITCH=8
CHANGE_API="https://api.pqs.pw/ipch/xxx"  # PQS 更换 IP API URL

Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[36m"
Font_Suffix="\033[0m"

UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
ACCEPT_HDR='text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'
TITLE1="81280792"   # LEGO Ninjago
TITLE2="70143836"   # Breaking Bad
TIMEOUT=10
RETRY=1

usage() {
  echo "Usage: $0 [-4|-6] [--max N] [--wait SECONDS]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -4) IP_MODE="-4"; shift ;;
    -6) IP_MODE="-6"; shift ;;
    --max) MAX_TRIES="$2"; shift 2 ;;
    --wait) WAIT_AFTER_SWITCH="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done


curl_fetch() {
  local url="$1"
  curl ${IP_MODE} -fsL --max-time "${TIMEOUT}" --retry "${RETRY}" \
    -H "accept: ${ACCEPT_HDR}" \
    -H "accept-language: en-US,en;q=0.9" \
    -H 'priority: u=0, i' \
    -H 'sec-ch-ua: "Microsoft Edge";v="135", "Not-A.Brand";v="8", "Chromium";v="135"' \
    -H 'sec-ch-ua-mobile: ?0' \
    -H 'sec-ch-ua-platform: "Windows"' \
    -H 'sec-ch-ua-platform-version: "15.0.0"' \
    -H 'sec-fetch-dest: document' \
    -H 'sec-fetch-mode: navigate' \
    -H 'sec-fetch-site: none' \
    -H 'sec-fetch-user: ?1' \
    -H 'upgrade-insecure-requests: 1' \
    --user-agent "${UA_BROWSER}" \
    "$url"
}

extract_region() {
  local html="$1"
  local region
  region=$(echo "$html" | grep -o 'data-country="[A-Z][A-Z]"' | sed 's/.*="\([A-Z][A-Z]\)".*/\1/' | head -n1)
  [[ -n "$region" ]] && { echo "$region"; return; }
  echo "US"
}

test_netflix_once() {
  local url1="https://www.netflix.com/title/${TITLE1}"
  local url2="https://www.netflix.com/title/${TITLE2}"
  local r1 r2
  r1="$(curl_fetch "$url1" || true)"
  r2="$(curl_fetch "$url2" || true)"

  if [[ -z "$r1" || -z "$r2" ]]; then
    echo -e " Netflix:\t\t\t${Font_Red}[ERROR] Failed (Network Connection)${Font_Suffix}"
    echo "STATUS=NETWORK_FAIL"
    return 1
  fi

  local m1 m2
  m1="$(echo "$r1" | grep -F 'Oh no!' || true)"
  m2="$(echo "$r2" | grep -F 'Oh no!' || true)"

  if [[ -n "$m1" && -n "$m2" ]]; then
    echo -e " Netflix:\t\t\t${Font_Yellow}[WARN] Originals Only${Font_Suffix}"
    echo "STATUS=ORIGINALS"
    return 0
  fi

  if [[ -z "$m1" || -z "$m2" ]]; then
    local region
    region="$(extract_region "$r1")"
    echo -e " Netflix:\t\t\t${Font_Green}[OK] Unlocked (Region: ${region})${Font_Suffix}"
    echo "STATUS=UNLOCK REGION=${region}"
    return 0
  fi

  echo -e " Netflix:\t\t\t${Font_Red}[ERROR] Unknown Failure${Font_Suffix}"
  echo "STATUS=FAILED"
  return 0
}

switch_ip() {
  echo -e "${Font_Blue}[INFO] Switching IP via: ${CHANGE_API}${Font_Suffix}"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "${CHANGE_API}" || echo "000")
  echo " Switch API HTTP: ${code}"
  [[ "$code" == "200" ]] || return 1
  return 0
}

main() {
  for ((i=1; i<=MAX_TRIES; i++)); do
    echo "== Attempt ${i}/${MAX_TRIES} =="

    out="$(test_netflix_once || true)"
    echo "$out" | sed 's/^/  /'

    status=$(echo "$out" | grep -o 'STATUS=[A-Z_]*' | head -n1 | cut -d= -f2)

    if [[ "$status" == "UNLOCK" ]]; then
      echo -e "${Font_Green}[OK] Done: Netflix Fully Unlocked.${Font_Suffix}"
      exit 0
    fi

    if [[ "$status" == "NETWORK_FAIL" ]]; then
      echo -e "${Font_Yellow}[WARN] Network issue detected, skipping IP switch.${Font_Suffix}"
      sleep "${WAIT_AFTER_SWITCH}"
      continue
    fi

    if [[ "$status" == "FAILED" || -z "$status" ]]; then
      echo -e "${Font_Yellow}[WARN] Test failed or unknown status, retrying after wait...${Font_Suffix}"
      sleep "${WAIT_AFTER_SWITCH}"
      continue
    fi

    if [[ "$status" == "ORIGINALS" ]]; then
      echo -e "${Font_Blue}[INFO] Detected Originals-only region, switching IP...${Font_Suffix}"
      if switch_ip; then
        echo -e "${Font_Green}[OK] IP switched. Waiting ${WAIT_AFTER_SWITCH}s...${Font_Suffix}"
        sleep "${WAIT_AFTER_SWITCH}"
        continue
      else
        echo -e "${Font_Red}[ERROR] IP switch API failed. Waiting ${WAIT_AFTER_SWITCH}s before retry...${Font_Suffix}"
        sleep "${WAIT_AFTER_SWITCH}"
        continue
      fi
    fi
  done

  echo -e "${Font_Red}[ERROR] Reached max attempts (${MAX_TRIES}) without full unlock.${Font_Suffix}"
  exit 2
}

main
