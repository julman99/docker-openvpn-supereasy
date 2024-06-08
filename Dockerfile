FROM alpine:3.20
RUN  apk add --no-cache \
    openvpn=2.6.10-r0 \
    easy-rsa \
    iptables \
    bash

ENV EASYRSA_BATCH=yes \
    OPENVPN_PORT_UDP=1194 \
    OPENVPN_PORT_TCP=off \
    OPENVPN_DNS=1.1.1.1 \
    OPENVPN_PING=10 \
    OPENVPN_PING_RESTART=60 \
    OPENVPN_CIPHER="" \
    OPENVPN_FASTIO=0 \
    OPENVPN_NETWORK_UDP="10.8.0.0/24" \
    OPENVPN_NETWORK_TCP="10.9.0.0/24" \
    OPENVPN_ROUTE_DEV="eth0" \
    OPENVPN_TUN_MTU="1420"


RUN mkdir -p /dev/net

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
