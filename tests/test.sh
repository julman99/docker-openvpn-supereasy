#!/bin/bash
source testlib.sh
set -e
docker build ../ -t ovpn-test --platform linux/amd64

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

test-client-generation
test-client-connect-revoke
