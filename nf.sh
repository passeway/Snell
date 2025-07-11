#!/bin/bash

curlArgs="$useNIC $usePROXY $xForward $resolve $dns --max-time 10"
UA_BROWSER="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
UA_SEC_CH_UA='"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"'
UA_ANDROID="Mozilla/5.0 (Linux; Android 10; Pixel 4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36"

Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Suffix="\033[0m"

echo -n -e "\r *Netflix解锁检测  By nfdns.top \n"
# LEGO Ninjago
 result1=$(curl $curlArgs -4 --user-agent "${UA_Browser}" -fsLI -X GET --write-out %{http_code} --output /dev/null --max-time 10 --tlsv1.3 "https://www.netflix.com/title/81280792"  2>&1)
  echo -n -e "\r------------------\n"  
# Breaking bad
 result2=$(curl $curlArgs -4 --user-agent "${UA_Browser}" -fsLI -X GET --write-out %{http_code} --output /dev/null --max-time 10 --tlsv1.3 "https://www.netflix.com/title/70143836" 2>&1)

    if [ "${result1}" == '000' ] || [ "$result2" == '000' ]; then
        echo -n -e "\r ${Font_Red}Failed (Network Connection)${Font_Suffix}\n"
    fi
    if [ "$result1" == '404' ] && [ "$result2" == '404' ]; then
        echo -n -e "\r ${Font_Yellow}您目前仅自制${Font_Suffix}\n"
    fi
    if [ "$result1" == '403' ] || [ "$result2" == '403' ]; then
        echo -n -e "\r ${Font_Red}您目前不支持解锁${Font_Suffix}\n"
    fi
    if [ "$result1" == '200' ] || [ "$result2" == '200' ]; then
         regiontmp=$(curl $curlArgs -4 -fSsI -X GET --max-time 10 --write-out %{redirect_url} --output /dev/null --tlsv1.3 "https://www.netflix.com/login" 2>&1 )
         region=$(echo $regiontmp | cut -d '/' -f4 | cut -d '-' -f1 | tr [:lower:] [:upper:])
    if [[ ! -n "$region" ]]; then
        region="US"
   	fi
        echo -n -e "\r ${Font_Green}您目前完整解锁非自制剧 || (解锁地区: ${region})${Font_Suffix}\n"
    fi
