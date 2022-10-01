FROM ubuntu:20.04
RUN apt-get update && \
    apt-get install -y openvpn easy-rsa iptables

ENV EASYRSA_BATCH=yes
ENV OPENVPN_PORT_UDP=1194
ENV OPENVPN_PORT_TCP=off
ENV OPENVPN_DNS=1.1.1.1
ENV OPENVPN_PING=10
ENV OPENVPN_PING_RESTART=60

COPY start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT /start.sh
