# EchoVR-GameServer-Docker

## Prerequisites
- The Echo VR binaries for the pre-fairwell version (CL: 631547)
- The `pnsradgameserver.dll` library file inside the `bin/win10/` folder of the EchoVR instalation.
- A valid `config.json` inside the `_local` folder of the EchoVR instalation.
- Change the `retries` value in the `netconfig_dedicatedserver.json` and `netconfig_client.json` files inside the `sourcedb/rad15/json/r14/config/` folder of the EchoVR folder if you intended to run more than 3 servers.

## Quickstart
- Modify the `Ssettings.json` file and set the proper ip and port for the Relay server in the `RelayIP` and proper echo launch argument in `EchoArgs`.
- Use `docker build . -t echovr-gameserver-docker --no-cache` to build the image.
- To start the container, use `docker run --mount 'type=bind,src=/path/to/r15NetDedicated,dst=/ready-at-dawn-echo-arena' --net=host -d --restart unless-stopped echovr-gameserver-docker` where the `src=` points to the root of the EchoVR folder.
- If you need to check the echo log, you can run `sudo docker exec -it [docker id] tail -f /root/tmplog`, replacing `[docker id]` with the id of the running container.


## Configuration
- Most of the configuration is in the `Ssettings.json`.
- If you need to make more advanced changes, look at the `monitor.sh` script
