
function @reset_testlib {
    docker network inspect ovpn-test >/dev/null 2>&1 || \
        docker network create --driver bridge ovpn-test

    @ovpn-serve-stop >/dev/null 2>&1 || true
}

function @assert_equals {
    if [ "$1" != "$2" ]; then
        echo "Error: '$1' is not the same as '$2'"
        exit 1
    fi
}

function @ls {
    ls -1 $1 | tr '\n' ' ' | xargs
}

function @assert_ls {
    FILES=`@ls "$1"`
    @assert_equals "$FILES" "$2"
}

function @assert_files_equals() {
    local file1=$1
    local file2=$2

    if ! cmp -s "$file1" "$file2"; then
        echo "Error: The files '$file1' and '$file2' are not equal."
        exit 1
    fi
}

@assert_files_not_equal() {
    local file1=$1
    local file2=$2

    if cmp -s "$file1" "$file2"; then
        echo "Error: The files '$file1' and '$file2' are equal."
        exit 1
    fi
}

@assert_exit_code() {
expected_exit_code=$1
    shift
    set +e # Disable 'set -e'
    "$@"
    actual_exit_code=$?
    set -e # Re-enable 'set -e'
    if [ "$actual_exit_code" != "$expected_exit_code" ]; then
        echo "Error: Command exited with code $actual_exit_code, but expected $expected_exit_code."
        exit 1
    fi
}

function @ovpn-setup {
    docker run --name ovpn-test-setup \
        --rm \
        -e OPENVPN_EXTERNAL_HOSTNAME=ovpn-test-serve \
        -v $(pwd)/server:/etc/openvpn/server \
        -v $(pwd)/clients:/etc/openvpn/clients \
        -v $(pwd)/tmp:/tmp \
        --cap-add NET_ADMIN \
        "$@" ovpn-test setup
}

function @ovpn-serve-start {
    echo "STARTING OPENVPN SERVER"
    docker run --name ovpn-test-serve \
        --rm \
        -e OPENVPN_EXTERNAL_HOSTNAME=ovpn-test-serve \
        --hostname=ovpn-test-serve \
        --network=ovpn-test \
        -v $(pwd)/server:/etc/openvpn/server \
        -v $(pwd)/clients:/etc/openvpn/clients \
        -v $(pwd)/tmp:/tmp \
        --cap-add NET_ADMIN \
        -p 1194:1194/udp \
        "$@" ovpn-test serve &
    sleep 5
}

function @ovpn-serve-stop {
    echo "STOPPING OPENVPN SERVER: `docker kill ovpn-test-serve`"
}

function @ovpn-client {
    echo "STARTING OPENVPN CLIENT"
    docker run --name ovpn-test-client \
        --network=ovpn-test \
        -v $(pwd)/clients:/etc/openvpn/clients \
        -v $(pwd)/tmp:/tmp \
        --rm \
        --entrypoint=openvpn \
        --device /dev/net/tun \
        --cap-add NET_ADMIN \
        ovpn-test --script-security 2 "$@"
}

function @ovpn-client-assert-error {
    @assert_exit_code 1 @ovpn-client --connect-retry-max 1 --hand-window 1 --connect-timeout 1 --up "/bin/sh -c 'pkill openvpn'" --config "$1"
}

function @ovpn-client-assert-connect {
    @assert_exit_code 0 @ovpn-client --connect-retry-max 1 --hand-window 1 --connect-timeout 1 --up "/bin/sh -c 'pkill openvpn'" --config "$1"
}

 @reset_testlib
