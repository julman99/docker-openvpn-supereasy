# OpenVPN SuperEasy

Run an OpenVPN server with just one docker command. No need to setup certs, ca etc. No need to run any command to create a client config file. Just run the container, specify how many clients you want and it will do everything by itself.

OpenVPN and the clients are pre-confured with a secure set of parameters that will work for most of the cases where no advance settings are needed.

# Docker Compose file

```
openvpn-supereasy:
  image: julman99/openvpn-supereasy
  container_name: openvpn-supereasy
  cap_add:
    - NET_ADMIN
  environment:
    - OPENVPN_EXTERNAL_HOSTNAME=some.domain
    - OPENVPN_PORT_UDP=1194 #or 'off' if no udp support is desired
    - OPENVPN_PORT_TCP=443  #or 'off' if no tcp support is desired
    - OPENVPN_DNS=1.1.1.1   #DNS to be used by clients when routed through this vpn
    - OPENVPN_CLIENTS=client1 client2 client3
    - OPENVPN_PING=10 #optional, ping interval to keep connections alive
    - OPENVPN_PING_RESTART=60 #optional, restart connection if no ping has been sucessful for the specified time
    - OPENVPN_CIPHER=some.cipher #optional, one of AES-256-GCM, AES-128-GCM, AES-256-CBC or AES-128-CBC. If ommited OpenVPN tries to negotiate the most secure cipher supported by both server and client
    - OPENVPN_FASTIO=0 #optional, enable fastio on the server
    - OPENVPN_NETWORK_UDP=0 #optional, network that will be used for clients conneting through udp. Defaults to 10.8.0.0/24
    - OPENVPN_NETWORK_TCP=0 #optional, network that will be used for clients conneting through tcp. Defaults to 10.9.0.0/24
    - OPENVPN_ROUTE_DEV=0 #optional, device to route traffic, this parameter is useful when running openvpn with host networking
    - OPENVPN_TUN_MTU=0 #optional, change mtu size. Defaults to 1420
    - TZ=America/New_York   #optional timezone
  volumes:
    - <path-to-server-config>:/etc/openvpn/server
    - <path-for-ovpn-client-files>:/etc/openvpn/clients
  ports:
    - 1194:1194/udp
    - 443:443/tcp
  restart: unless-stopped
```

# Client .ovpn files

You can specify an arbitrary number of clients in the variable `OPENVPN_CLIENTS`. This is a space separated list. The container will automatically generate a `.ovpn` file for each client and put it in the volume mounted at `/etc/openvpn/clients`. If you delete a client from the list the server will add that client to the revoked list so it cannot connect ever again. If you add the same client name again after revoking, it will be generated from scratch, meaning the old `.ovpn` file will not work for that client.

The `.ovpn` files are re-generated every time the container starts. This allows to change parameters such as the server port, protocol, dns etc and still have the .opvpn file updated. The cert/key combination for each client will not change even if the `.ovpn` file is re-generated.

# UDP and TCP

The container can spin up OpenVPN in udp and/or tcp mode. For this just specify the ports. If you don't want either udp or tcp just type `off`.

If both UDP and TCP are turned on, the client files will contain the connection information for both, first UDP and then TCP.
