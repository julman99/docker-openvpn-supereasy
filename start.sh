#!/bin/bash

set -e

EASY_RSA_PATH="/etc/openvpn/server/easy-rsa"
READY_FILE="/etc/openvpn/server/.ready"
CRL_BLACKLIST_DIR="/etc/openvpn/server/crl-blacklist"

function assert_variable {
    var_name="$1"
    var_value="${!var_name}"
    if [ -z "$var_value" ]; then
        echo "Error: $var_name is not set"
        exit 3
    fi
}

assert_cidr() {
    local cidr="$1"

    # Check if the CIDR has a mask, add /24 if not
    if [[ ! $cidr =~ / ]]; then
        cidr="$cidr/24"
    fi

    # Inline is_valid_cidr logic
    if [[ $cidr =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
        local ip="${cidr%/*}"
        local mask="${cidr#*/}"

        # Validate IP address
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IFS='.' read -r -a octets <<< "$ip"
            for octet in "${octets[@]}"; do
                if ((octet < 0 || octet > 255)); then
                    echo "Error: Invalid CIDR notation."
                    exit 1
                fi
            done
        else
            echo "Error: Invalid CIDR notation."
            exit 1
        fi

        # Validate mask
        if ! ((mask >= 0 && mask <= 32)); then
            echo "Error: Invalid CIDR notation."
            exit 1
        fi
    else
        echo "Error: Invalid CIDR notation."
        exit 1
    fi

    # Check if the mask is less than /16
    if ((mask < 16)); then
        echo "Error: CIDR mask is less than /16."
        exit 1
    fi
}

wait_for_tun() {
  local TUN_DEVICE=$1
  while ! ip link show "$TUN_DEVICE" > /dev/null 2>&1; do
    echo "Waiting for $TUN_DEVICE to be created..."
    sleep 1
  done
  echo "$TUN_DEVICE exists!"
}

function initialize {
    echo "Initializing openvpn for the first time"

    mkdir -p /etc/openvpn/server
    mkdir -p "$EASY_RSA_PATH"

    rm -rf /etc/openvpn/server/*
    rm -rf "$EASY_RSA_PATH"

    EASYRSA_REQ_CN="$OPENVPN_EXTERNAL_HOSTNAME"

    cp -r /usr/share/easy-rsa "$EASY_RSA_PATH"
    cd "$EASY_RSA_PATH"
    ./easyrsa init-pki
    openssl rand -writerand "$EASY_RSA_PATH/pki/.rnd"
    ./easyrsa build-ca nopass
    ./easyrsa gen-dh
    ./easyrsa build-server-full server nopass
    openvpn --genkey --secret "$EASY_RSA_PATH/pki/ta.key"
    ./easyrsa gen-crl
    cd "$EASY_RSA_PATH/pki"
    cp -rp ca.crt dh.pem ta.key crl.pem issued private /etc/openvpn/server/
    touch "$READY_FILE"
}

function create_client {
    client="$1"

    mkdir -p /etc/openvpn/clients
    client_file="/etc/openvpn/clients/$client.ovpn"
    if [ ! -f "./pki/private/$client.key" ]; then
        echo "Creating certificate and keys for client $client"
        ./easyrsa build-client-full "$client" nopass
    else
        echo "Skipping certificate and key generation for client $client"
    fi
    echo "" > "$client_file"
    echo "client" >> "$client_file"
    echo "dev tun" >> "$client_file"
    echo "nobind" >> "$client_file"
    echo "key-direction 1" >> "$client_file"
    echo "auth SHA256" >> "$client_file"
    echo "resolv-retry infinite" >> "$client_file"
    echo "persist-key" >> "$client_file"
    echo "persist-tun" >> "$client_file"
    echo "mute-replay-warnings" >> "$client_file"
    echo "remote-cert-tls server" >> "$client_file"
    echo "verb 3" >> "$client_file"

    echo "<key>" >> "$client_file"
    cat "./pki/private/$client.key" >> "$client_file"
    echo "</key>" >> "$client_file"

    echo "<cert>" >> "$client_file"
    cat "./pki/issued/$client.crt" >> "$client_file"
    echo "</cert>" >> "$client_file"

    echo "<ca>" >> "$client_file"
    cat /etc/openvpn/server/ca.crt >> "$client_file"
    echo "</ca>" >> "$client_file"

    echo "<tls-auth>" >> "$client_file"
    cat /etc/openvpn/server/ta.key >> "$client_file"
    echo "</tls-auth>" >> "$client_file"

    if [ ! -z "$OPENVPN_PORT_UDP" ]; then
        echo "<connection>" >> "$client_file"
        echo "proto udp" >> "$client_file"
        echo "remote $OPENVPN_EXTERNAL_HOSTNAME $OPENVPN_PORT_UDP" >> "$client_file"
        echo "</connection>" >> "$client_file"
    fi
    if [ ! -z "$OPENVPN_PORT_TCP" ]; then
        echo "<connection>" >> "$client_file"
        echo "proto tcp" >> "$client_file"
        echo "remote $OPENVPN_EXTERNAL_HOSTNAME $OPENVPN_PORT_TCP" >> "$client_file"
        echo "</connection>" >> "$client_file"
    fi
}

function create_clients {
    mkdir -p /etc/openvpn/clients
    find /etc/openvpn/clients -name "*.ovpn" | xargs -r rm
    cd "$EASY_RSA_PATH"
    for client in $OPENVPN_CLIENTS; do
        create_client "$client"
    done
}

function blacklist_unlisted_clients {
    mkdir -p "$CRL_BLACKLIST_DIR"
    cd "$EASY_RSA_PATH"
    touch pki/crl.pem
    for cert_file in $(ls pki/issued/*.crt); do
        client_name=$(basename "$cert_file" .crt)
        if [[ ! " $OPENVPN_CLIENTS " =~ " $client_name " && "$client_name" != "server" ]]; then
            echo "Blacklisting client $client_name found on file $cert_file"
            ./easyrsa revoke "$client_name"
            ./easyrsa --days=3650 gen-crl
        fi
    done
    cp -f pki/crl.pem /etc/openvpn/server/crl.pem
}

function run_openvpn {
    local port="$1"
    local proto="$2"
    local tun="$3"
    local net="$4"
    local net_ip=$(ipcalc -n "$net" | grep 'NETWORK' | awk -F '=' '{print $2}')
    local net_mask=$(ipcalc -n -m "$net" | grep 'NETMASK' | awk -F '=' '{print $2}')
    openvpn \
        --server "$net_ip" "$net_mask" \
        --dev "$tun" \
        --dev-type "tun" \
        --mode server \
        --local 0.0.0.0 \
        --port "$port" \
        --proto "$proto" \
        --keepalive "$OPENVPN_PING" "$OPENVPN_PING_RESTART" \
        --bind \
        --dh /etc/openvpn/server/dh.pem \
        --ca /etc/openvpn/server/ca.crt \
        --cert /etc/openvpn/server/issued/server.crt \
        --key /etc/openvpn/server/private/server.key \
        --tls-auth /etc/openvpn/server/ta.key \
        --key-direction 0 \
        --auth SHA256 \
        --crl-verify /etc/openvpn/server/crl.pem \
        $OPENVPN_CIPHER \
        --persist-tun \
        --persist-key \
        --topology subnet \
        --push "redirect-gateway def1" \
        --push "block-outside-dns" \
        --push "topology subnet" \
        --push "dhcp-option DNS $OPENVPN_DNS" \
        --sndbuf 524288 \
        --rcvbuf 524288 \
        --push "sndbuf 524288" \
        --push "rcvbuf 524288" \
        --tun-mtu $OPENVPN_TUN_MTU \
        $OPENVPN_FASTIO
}

function start {
    echo "Creating tun devices..."

    mkdir -p /dev/net
    if [ ! -c /dev/net/tun ]; then
        mknod /dev/net/tun c 10 200
    fi

    if [ ! -z "$OPENVPN_PORT_UDP" ]; then
        echo "Starting openvpn with udp..."
        run_openvpn "$OPENVPN_PORT_UDP" "udp" "ovpnsetun0" "$OPENVPN_NETWORK_UDP" &
        wait_for_tun "ovpnsetun0"

        iptables -t nat -A POSTROUTING -s "$OPENVPN_NETWORK_UDP" -o "$OPENVPN_ROUTE_DEV" -j MASQUERADE
    fi
    if [ ! -z "$OPENVPN_PORT_TCP" ]; then
        echo "Starting openvpn with tcp..."
        run_openvpn "$OPENVPN_PORT_TCP" "tcp" "ovpnsetun1" "$OPENVPN_NETWORK_TCP" &
        wait_for_tun "ovpnsetun1"

        iptables -t nat -A POSTROUTING -s "$OPENVPN_NETWORK_TCP" -o "$OPENVPN_ROUTE_DEV" -j MASQUERADE
    fi

    wait -n
}

if [ "$OPENVPN_PORT_UDP" == "off" ]; then
    OPENVPN_PORT_UDP=""
fi
if [ "$OPENVPN_PORT_TCP" == "off" ]; then
    OPENVPN_PORT_TCP=""
fi
if [ -z "$OPENVPN_PORT_UDP" ] && [ -z "$OPENVPN_PORT_TCP" ]; then
    echo "Error: OPENVPN_PORT_UDP and/or OPENVPN_PORT_TCP must be set"
    exit 2
fi
if [ "$OPENVPN_CIPHER" != "" ]; then
    OPENVPN_CIPHER="--data-ciphers $OPENVPN_CIPHER --cipher $OPENVPN_CIPHER"
fi
if [ "$OPENVPN_FASTIO" == "true" ] || [ "$OPENVPN_FASTIO" == "1" ]; then
    echo "Notice: --fast-io is enabled"
    OPENVPN_FASTIO="--fast-io"
else
    OPENVPN_FASTIO=""
fi

# Check if the CIDR has a mask, add /24 if not
if [[ ! $OPENVPN_NETWORK_UDP =~ / ]]; then
    OPENVPN_NETWORK_UDP="$OPENVPN_NETWORK_UDP/24"
fi
if [[ ! $OPENVPN_NETWORK_TCP =~ / ]]; then
    OPENVPN_NETWORK_TCP="$OPENVPN_NETWORK_TCP/24"
fi

# Validate the CIDR
assert_cidr $OPENVPN_NETWORK_UDP
assert_cidr $OPENVPN_NETWORK_TCP

assert_variable "OPENVPN_EXTERNAL_HOSTNAME"
assert_variable "OPENVPN_CLIENTS"

if [ ! -f "$READY_FILE" ]; then
    initialize
else
    echo "Existing configuration detected... skipping openvpn initialization"
fi

COMMAND=${1:-serve}

case "$COMMAND" in
    "serve")
        create_clients
        blacklist_unlisted_clients
        start
        ;;
    "setup")
        create_clients
        blacklist_unlisted_clients
        ;;
    *)
        echo "Error: Invalid command. Use 'serve' or 'prepare'."
        exit 1
        ;;
esac
