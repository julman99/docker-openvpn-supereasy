FROM alpine
RUN  apk add --no-cache openvpn easy-rsa iptables bash

ENV EASYRSA_BATCH=yes \
    OPENVPN_PORT_UDP=1194 \
    OPENVPN_PORT_TCP=off \
    OPENVPN_DNS=1.1.1.1 \
    OPENVPN_PING=10 \
    OPENVPN_PING_RESTART=60

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT /start.sh
