ARG TEST_IMAGE
FROM ${TEST_IMAGE}

RUN if command -v apk >/dev/null; then \
      apk add --no-cache bash python3; \
    else \
      apt-get update && apt-get install -y --no-install-recommends bash python3 systemd systemd-sysv dbus; \
    fi
COPY Snell.sh /tmp/Snell.sh
RUN bash -c 'source /tmp/Snell.sh; install_required_packages' && rm /tmp/Snell.sh

ENV container=docker
