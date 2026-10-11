ARG TEST_IMAGE
FROM ${TEST_IMAGE}

# dnf: 镜像过慢时切换下一个；保留元数据缓存供下一步安装依赖复用（镜像用后即弃）。

RUN if command -v apk >/dev/null; then \
      apk add --no-cache bash python3; \
    elif command -v dnf >/dev/null; then \
      printf '%s\n' minrate=200k timeout=20 retries=10 max_parallel_downloads=10 >> /etc/dnf/dnf.conf && \
      dnf -y install bash python3 systemd procps-ng && \
      { python3 -c 'import sys; sys.exit(sys.version_info < (3, 7))' || \
        { dnf -y install python3.11 && ln -sf /usr/bin/python3.11 /usr/local/bin/python3; }; }; \
    else \
      apt-get update && apt-get install -y --no-install-recommends bash python3 systemd systemd-sysv dbus; \
    fi
COPY Snell.sh /tmp/Snell.sh
RUN bash -c 'source /tmp/Snell.sh; install_required_packages' && rm /tmp/Snell.sh

ENV container=docker
