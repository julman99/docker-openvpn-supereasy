#!/bin/bash
script_dir=$(dirname "$(readlink -f "$0")")
pushd "$script_dir"

source testlib.sh
set -e
docker build ../ -t ovpn-test

MAIN_SERVER_DIR=$HOME/.openvpn-supereasy

function reset_openvpn {
    @reset_testlib

    mkdir -p "$MAIN_SERVER_DIR"
    if [ ! -d "$MAIN_SERVER_DIR/server" ]; then
        pushd "$MAIN_SERVER_DIR"
        mkdir -p server
        mkdir -p clients
        mkdir -p tmp
        @ovpn-setup -e OPENVPN_CLIENTS=" "
    fi

    pushd `mktemp -d`
    cp -vr "$MAIN_SERVER_DIR/server" server
    mkdir tmp
    mkdir clients
}

function test-client-generation() {
    reset_openvpn

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2"
    @assert_ls "clients" "test1.ovpn test2.ovpn"

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2"
    @assert_ls "clients" "test1.ovpn test2.ovpn"

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2 test3"
    @assert_ls "clients" "test1.ovpn test2.ovpn test3.ovpn"
    cp clients/test3.ovpn tmp/

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2 test4"
    @assert_ls "clients" "test1.ovpn test2.ovpn test4.ovpn"
}

function test-client-connect-revoke() {
    reset_openvpn

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2 test3"
    @assert_ls "clients" "test1.ovpn test2.ovpn test3.ovpn"
    cp clients/test3.ovpn tmp/

    @ovpn-serve-start -e OPENVPN_CLIENTS="test1 test2"
    @ovpn-client-assert-error /tmp/test3.ovpn
    @ovpn-client-assert-connect /etc/openvpn/clients/test1.ovpn
    @ovpn-serve-stop
}

function test-client-revoke-crl-generation() {
    reset_openvpn

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2 test3"

    local test2_serial=`openssl x509 -in server/easy-rsa/pki/issued/test2.crt -noout -serial | cut -d'=' -f2`
    local test3_serial=`openssl x509 -in server/easy-rsa/pki/issued/test3.crt -noout -serial | cut -d'=' -f2`

    @ovpn-setup -e OPENVPN_CLIENTS="test1 test2"
    #ensure test3 is in the revoke list
    @assert_equals "`openssl crl -text -noout -in server/crl.pem | grep $test3_serial | cut -d':' -f2 | xargs`" "$test3_serial"

    @ovpn-setup -e OPENVPN_CLIENTS="test1"
    #ensure test3 is in the revoke list
    @assert_equals "`openssl crl -text -noout -in server/crl.pem | grep $test3_serial | cut -d':' -f2 | xargs`" "$test3_serial"
    #ensure test2 is in the revoke list
    @assert_equals "`openssl crl -text -noout -in server/crl.pem | grep $test2_serial | cut -d':' -f2 | xargs`" "$test2_serial"
}


function test-cidr-validation() {
    reset_openvpn

    #udp
    local output=$(@ovpn-setup -e OPENVPN_PORT_UDP=1194 -e OPENVPN_NETWORK_UDP="s")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    local output=$(@ovpn-setup -e OPENVPN_PORT_UDP=1194 -e OPENVPN_NETWORK_UDP="500.0.0.0/24")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    local output=$(@ovpn-setup -e OPENVPN_PORT_UDP=1194 -e OPENVPN_NETWORK_UDP="10.0.0.0/34")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    local output=$(@ovpn-setup -e OPENVPN_PORT_UDP=1194 -e OPENVPN_NETWORK_UDP="")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    #tcp
    local output=$(@ovpn-setup -e OPENVPN_PORT_TCP=443 -e OPENVPN_NETWORK_TCP="s")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    local output=$(@ovpn-setup -e OPENVPN_PORT_TCP=443 -e OPENVPN_NETWORK_TCP="500.0.0.0/24")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    local output=$(@ovpn-setup -e OPENVPN_PORT_TCP=443 -e OPENVPN_NETWORK_TCP="10.0.0.0/34")
    @assert_equals "Error: Invalid CIDR notation." "$output"

    local output=$(@ovpn-setup -e OPENVPN_PORT_TCP=443 -e OPENVPN_NETWORK_TCP="")
    @assert_equals "Error: Invalid CIDR notation." "$output"
}

function test-disabled-protocol-network-validation() {
    reset_openvpn

    @ovpn-setup \
        -e OPENVPN_CLIENTS="disabledtcp" \
        -e OPENVPN_PORT_TCP=off \
        -e OPENVPN_NETWORK_TCP="" \
        -e OPENVPN_PORT_UDP=1194 \
        -e OPENVPN_NETWORK_UDP=10.8.0.0/24
    @assert_ls "clients" "disabledtcp.ovpn"

    reset_openvpn

    @ovpn-setup \
        -e OPENVPN_CLIENTS="disabledudp" \
        -e OPENVPN_PORT_UDP=off \
        -e OPENVPN_NETWORK_UDP="" \
        -e OPENVPN_PORT_TCP=443 \
        -e OPENVPN_NETWORK_TCP=10.9.0.0/24
    @assert_ls "clients" "disabledudp.ovpn"
}

function test-openvpn-startup-failure-does-not-hang() {
    reset_openvpn

    @assert_serve_startup_failure_exits ovpn-test-startup-failure \
        -e OPENVPN_CLIENTS="startupfailure" \
        -e OPENVPN_PORT_UDP=99999 \
        -e OPENVPN_PORT_TCP=off \
        -e OPENVPN_TUN_MTU=1420
}

function test-env-argument-validation() {
    reset_openvpn

    local output=$(@ovpn-setup -e OPENVPN_CLIENTS="test1" -e OPENVPN_TUN_MTU="1420 --verb 11")
    @assert_equals "Error: OPENVPN_TUN_MTU must be a number." "$output"

    local output=$(@ovpn-setup -e OPENVPN_CLIENTS="test1" -e OPENVPN_MSSFIX="1380 --client-connect /tmp/hook")
    @assert_equals "Error: OPENVPN_MSSFIX must be a number." "$output"

    local output=$(@ovpn-setup -e OPENVPN_CLIENTS="test1" -e OPENVPN_CIPHER="AES-256-GCM --verb 11")
    @assert_equals "Error: Invalid OPENVPN_CIPHER." "$output"

    local output=$(@ovpn-setup -e OPENVPN_CLIENTS="good --bad")
    @assert_equals "Error: Invalid OPENVPN_CLIENTS entry: --bad" "$output"
}

test-client-generation
test-client-connect-revoke
test-client-revoke-crl-generation
test-cidr-validation
test-disabled-protocol-network-validation
test-openvpn-startup-failure-does-not-hang
test-env-argument-validation

echo 'Success! All tests passed'
