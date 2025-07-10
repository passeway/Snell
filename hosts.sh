#!/bin/bash
# 指定包含主机列表的逗号拼接的字符串
hostlist="$@"
IFS=',' read -ra hosts <<< "$hostlist"
for host in "${hosts[@]}"
do
  curl -s -o /dev/null -m 1 -H "Host:www.netflix.com" -w "$host\t%{http_code}\t%{time_total}\n" http://$host
done