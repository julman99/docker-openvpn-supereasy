# OpenVPN SuperEasy

Run an OpenVPN server with just one docker command. No need to setup certs, ca etc. No need to run any command to create a client config file. Just run the container, specify how many clients you want and it will do everything by itself

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
    - TZ=America/New_York   #optional timezone
  volumes:
    - <path-to-server-config>:/etc/openvpn/server
    - <path-for-ovpn-client-files>:/etc/openvpn/clients
  ports:
    - 1194:1194/udp
    - 443:443/tcp
  restart: unless-stopped
```

# UDP and TCP

The container can spin up OpenVPN in udp and/or tcp mode. For this just specify the ports. If you don't want either udp or tcp just type `off`.

# Client .ovpn files

You can specify an arbitrary number of clients in the variable `OPENVPN_CLIENTS`. This is a space separated list. The container will automatically generate a .ovpn file for each client and put it in the volume mounted at `/etc/openvpn/clients`. If you delete a client from the list the server *will still accept* connections from that client. At the moment there is no way to blacklist a client.

The `.ovpn` files are re-generated every time the container starts. This allows to change parameters such as the server port, protocol, dns etc and still have the .opvpn file updated. The cert/key combination for each client will not change even if the `.ovpn` file is re-generated.
