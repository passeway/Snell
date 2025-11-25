#!/usr/bin/env bash
set -euo pipefail

IP_MODE="-4"
MAX_TRIES=20
WAIT_AFTER_SWITCH=8
CHANGE_API="https://api.pqs.pw/ipch/xxx"

Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[36m"
Font_Suffix="\033[0m"

UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
LIGHT_COOKIE='nfvdid=BQFmAAEBEM9xQ2H4cdmc3U2adN...; OptanonConsent=isGpcEnabled=0'

check_html() {
    local ID="$1"
    curl ${IP_MODE} -fsL \
        -H "accept-language: en-US,en;q=0.9" \
        -H "user-agent: ${UA_BROWSER}" \
        -b "${LIGHT_COOKIE}" \
        "https://www.netflix.com/title/${ID}"
}

test_netflix_once() {
    local r1=$(check_html "81280792")
    local r2=$(check_html "70143836")
    if [[ -z "$r1" || -z "$r2" ]]; then
        echo "STATUS=NETWORK_FAIL"
        echo -e " Netflix:\t${Font_Red}[Network Error]${Font_Suffix}"
        return
    fi


    if echo "$r1$r2" | grep -q "Oh no"; then
        echo "STATUS=ORIGINALS"
        echo -e " Netflix:\t${Font_Yellow}[Originals Only]${Font_Suffix}"
        return
    fi

    if echo "$r1" | grep -q '"countryName"' || echo "$r2" | grep -q '"countryName"'; then
        local region=$(echo "$r1" | grep -oP '"countryName":"\K[^"]+' | head -n1)
        [[ -z "$region" ]] && region="Unknown"

        echo "STATUS=UNLOCK REGION=${region}"
        echo -e " Netflix:\t${Font_Green}[Unlocked] Region: ${region}${Font_Suffix}"
        return
    fi

    echo "STATUS=FAILED"
    echo -e " Netflix:\t${Font_Red}[Failed]${Font_Suffix}"
}


switch_ip() {
    echo -e "${Font_Blue}[Switching IP via PQS]${Font_Suffix}"
    local code=$(curl -s -o /dev/null -w "%{http_code}" "${CHANGE_API}")
    echo " API Code: ${code}"
    [[ "$code" == "200" ]]
}

main() {
    for ((i=1; i<=MAX_TRIES; i++)); do

        echo "== Attempt ${i}/${MAX_TRIES} =="

        out=$(test_netflix_once)
        echo "$out" | sed 's/^/  /'

        local status=$(echo "$out" | grep -o 'STATUS=[A-Z_]*' | cut -d= -f2)

        case "$status" in
            UNLOCK)
                echo -e "${Font_Green}[OK] Netflix Fully Unlocked${Font_Suffix}"
                exit 0
                ;;
            ORIGINALS)
                echo -e "${Font_Blue}[INFO] Found Originals Only → Switch IP${Font_Suffix}"
                switch_ip && sleep "$WAIT_AFTER_SWITCH"
                ;;
            NETWORK_FAIL)
                echo -e "${Font_Yellow}[WARN] Network issue, retry...${Font_Suffix}"
                sleep "$WAIT_AFTER_SWITCH"
                ;;
            FAILED|"")
                echo -e "${Font_Yellow}[WARN] Failed / Unknown, retry...${Font_Suffix}"
                sleep "$WAIT_AFTER_SWITCH"
                ;;
        esac
    done

    echo -e "${Font_Red}[ERROR] Max Attempts Reached${Font_Suffix}"
    exit 2
}

main