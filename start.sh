#!/bin/bash

set -e

EASY_RSA_PATH=/etc/openvpn/server/easy-rsa
READY_FILE="/etc/openvpn/server/.ready"

function assert_variable {
    var_name="$1"
    var_value=${!var_name};
    if [ -z "$var_value" ]; then
        echo "Error: $var_name is not set"
        exit 3
    fi
}

function initialize {
    # Openvpn init
    echo "Initializing openvpn for the first time"

    mkdir -p /etc/openvpn/server
    mkdir -p $EASY_RSA_PATH

    #Clean just in case
    rm -rf /etc/openvpn/server/*
    rm -rf $EASY_RSA_PATH

    EASYRSA_REQ_CN="$OPENVPN_EXTERNAL_HOSTNAME"

    cp -r /usr/share/easy-rsa $EASY_RSA_PATH
    cd $EASY_RSA_PATH
    ./easyrsa init-pki
    openssl rand -writerand $EASY_RSA_PATH/pki/.rnd
    ./easyrsa build-ca nopass
    ./easyrsa gen-dh
    ./easyrsa build-server-full server nopass
    openvpn --genkey --secret $EASY_RSA_PATH/pki/ta.key
    ./easyrsa gen-crl
    cd $EASY_RSA_PATH/pki
    cp -rp ca.crt dh.pem ta.key crl.pem issued private  /etc/openvpn/server/
    touch /etc/openvpn/server/.ready
}

function create_client {
    client="$1"
    port="$2"
    proto="$3"

    mkdir -p /etc/openvpn/clients
    client_file="/etc/openvpn/clients/$client.$proto.ovpn"
    if [ ! -f "./pki/private/$client.key" ]; then
        echo "Creating certificate and keys for client $client"
        ./easyrsa build-client-full $client nopass
    else
        echo "Skipping certificate and key generation for client $client"
    fi
    echo "" > "$client_file"
    echo "client" >> "$client_file"
    echo "dev tun" >> "$client_file"
    echo "proto $proto" >> "$client_file"
    echo "remote $OPENVPN_EXTERNAL_HOSTNAME $port" >> "$client_file"
    echo "resolv-retry infinite" >> "$client_file"
    echo "nobind" >> "$client_file"
    echo "persist-key" >> "$client_file"
    echo "persist-tun" >> "$client_file"
    echo "mute-replay-warnings" >> "$client_file"
    echo "remote-cert-tls server" >> "$client_file"
    echo "cipher $OPENVPN_CIPHER" >> "$client_file"
    echo "verb 3" >> "$client_file"
    echo "remote-cert-tls server" >> "$client_file"

    echo "<key>" >> "$client_file"
    cat ./pki/private/$client.key >> "$client_file"
    echo "</key>" >> "$client_file"

    echo "<cert>" >> "$client_file"
    cat ./pki/issued/$client.crt >> "$client_file"
    echo "</cert>" >> "$client_file"

    echo "<ca>" >> "$client_file"
    cat /etc/openvpn/server/ca.crt >> "$client_file"
    echo "</ca>" >> "$client_file"

    echo "<tls-auth>" >> "$client_file"
    cat /etc/openvpn/server/ta.key >> "$client_file"
    echo "</tls-auth>" >> "$client_file"
}

function create_clients {
    cd $EASY_RSA_PATH
    for client in $OPENVPN_CLIENTS; do
        if [ ! -z $OPENVPN_PORT_UDP ]; then
            create_client $client $OPENVPN_PORT_UDP "udp"
        fi
        if [ ! -z $OPENVPN_PORT_TCP ]; then
            create_client $client $OPENVPN_PORT_TCP "tcp"
        fi
    done
}

function run_openvpn {
    port="$1"
    proto="$2"
    tun="$3"
    net="$4"

    openvpn \
        --server $net 255.255.255.0\
        --dev $tun \
        --mode server \
        --local 0.0.0.0 \
        --port $port \
        --proto $proto \
        --keepalive 10 60 \
        --bind \
        --dh /etc/openvpn/server/dh.pem \
        --ca /etc/openvpn/server/ca.crt \
        --cert /etc/openvpn/server/issued/server.crt \
        --key /etc/openvpn/server/private/server.key \
        --tls-auth /etc/openvpn/server/ta.key \
        --data-ciphers AES-256-CBC:AES-128-CBC:AES-256-GCM:AES-128-GCM \
        --persist-tun \
        --persist-key \
        --topology subnet \
        --push "redirect-gateway def1" \
        --push "block-outside-dns" \
        --push "topology subnet" \
        --push "ping $OPENVPN_PING" \
        --push "ping-restart $OPENVPN_PING_RESTART" \
        --push "dhcp-option DNS $OPENVPN_DNS" \
        --tun-mtu 1500 \
        --mssfix 1450 \
        --push "tun-mtu 1500" \
        --push "mssfix 1450" \
        --sndbuf 524288 \
        --rcvbuf 524288 \
        --push "sndbuf 524288" \
        --push "rcvbuf 524288" \
        $OPENVPN_FASTIO
}

function start {
    echo "Creating tun devices..."

    mkdir -p /dev/net
    if [ ! -c /dev/net/tun ]; then
        mknod /dev/net/tun c 10 200
    fi

    if [ ! -z $OPENVPN_PORT_UDP ]; then
        echo "Starting openvpn with udp..."
        iptables -t nat -A POSTROUTING -s '10.8.0.0/24' -o eth0 -j MASQUERADE
        run_openvpn $OPENVPN_PORT_UDP "udp" "tun0" "10.8.0.0" &
    fi
    if [ ! -z $OPENVPN_PORT_TCP ]; then
        echo "Starting openvpn with tcp..."
        iptables -t nat -A POSTROUTING -s '10.9.0.0/24' -o eth0 -j MASQUERADE
        run_openvpn $OPENVPN_PORT_TCP "tcp" "tun1" "10.9.0.0" &
    fi

    wait -n
}

if [ "$OPENVPN_PORT_UDP" == "off" ];then
    OPENVPN_PORT_UDP=
fi
if [ "$OPENVPN_PORT_TCP" == "off" ];then
    OPENVPN_PORT_TCP=
fi
if [ -z $OPENVPN_PORT_UDP ] && [ -z $OPENVPN_PORT_TCP ]; then
    echo "Error: OPENVPN_PORT_UDP and/or OPENVPN_PORT_TCP must be set"
    exit 2
fi
if [ "$OPENVPN_CIPHER" == "" ];then
    OPENVPN_CIPHER="AES-256-GCM"
fi
if [ "$OPENVPN_FASTIO" == "true" ] || [ "$OPENVPN_FASTIO" == "1" ];then
    echo "Notice: --fast-io is enabled"
    OPENVPN_FASTIO="--fast-io"
else
    OPENVPN_FASTIO=""
fi

assert_variable "OPENVPN_EXTERNAL_HOSTNAME"
assert_variable "OPENVPN_CLIENTS"

if [ ! -f "$READY_FILE" ]; then
    initialize
else
    echo "Existing configuration detected... skipping openvpn initialization"
fi


create_clients
start
