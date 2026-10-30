# LaaC: liquidctl as a Container 

## Why

I have an NZXT Kraken X53 AiO liquid cooler and a Corsair Commander Pro (to control the various fans and add more temperature sensors) in my UnRaid server but weren't able to configure them properly. Running a dedicated Windows 10/11 VM with CAM and iCUE works, but doesn't really make sense. Something with a smaller footprint running on Linux, that can be containerized, would be ideal.

Luckily, the great developers of [liquidctl](https://github.com/liquidctl/liquidctl) released a tool that can control many liquid cooling AiO and fan controller solutions.
[avpnusr](https://github.com/avpnusr/liquidctl-docker) created a Docker image that allows controlling the Kraken AIO, but unfortunately not the Commander controller. So I started extending the script, but quickly realized that starting from scratch would allow me to go with a config file instead - because that's easier to back up and allows changing values on the fly. I went with YAML, it's easy to read (and write) for humans and [Stefan Farestam](https://stackoverflow.com/a/21189044) shared a simple, bash-based YAML parser that worked out-of-the-box. 

The shell script uses [inotify-tools](https://github.com/inotify-tools/inotify-tools) to watch the config file and upon arrival of the ```close_write``` event liquidctl will be reconfigured. I think, this could lead to interesting scenarios where external sources update the config file based on external temperature readings. What could possibly go wrong!?! 

## How

### create a YAML config file

1. The file needs to be named config.yaml
2. The type parameter corresponds with the ```--match <id>``` parameter of liquidctl
3. When using cooling, you need to define its type and pump speed. When using the controller you need to define its type.
4. The liquidctl Kraken guide describes pump temperature/duty pairs, color settings and fan settings for supported AiO coolings. This could be easily expanded for other AiOs (https://github.com/liquidctl/liquidctl/blob/main/docs/kraken-x3-z3-guide.md)
5. Similar to the Kraken guide, liquidctl offers a documentation to set up the Corsair Commander Pro (https://github.com/liquidctl/liquidctl/blob/main/docs/corsair-commander-guide.md). Programming the controller fan speeds follows a pattern similar to the AiO fan speed / pump speed, except that you can specify a temperature probe.
6. To control all fans with the same speed (```liquidctl --match <match> set sync speed <speed>```), define ```fan_sync_speed: '<speed>'``` instead of ```fan<x>_speed: '<speed>'``` as controller property.
7. Controller LED is not yet supported, but can be easily added.
8. Refer to the config.template.yaml in the repository

### container mount options

1. Run the container privileged (```--privileged```) and reduce log max size (e.g. ```--log-opt max-size=1m --log-opt max-file=1```). 
2. No network is required. 
3. Mount your water cooler or controller devices into the container, e.g. ```--device /sys/bus/usb/devices/1-12.2```
4. Mount your config file into the container. The script expects the file in the ```/app``` folder, e.g. ```-v ~/config.yaml:/app/config.yaml```

**container start**

```sh
docker run -d \
    --device /sys/bus/usb/devices/<your_usb_id> \
    --privileged \
    --log-opt max-size=1m --log-opt max-file=1 \
    -v <path_to>/config.yaml:/app/config.yaml \
    --restart=unless-stopped mplogas/laac:latest
```

## Monitoring

Need a quick look at what's going on thermally? A standby-safe dashboard ships in the image at `/app/monitor.sh`. It runs on demand only (it does **not** write to the container logs, so the config-reload history stays intact), loops until you press `Ctrl-C`, and refreshes every 10 seconds by default:

```sh
docker exec -it <container> /app/monitor.sh        # default 10s refresh
docker exec -it <container> /app/monitor.sh 30     # custom interval in seconds
```

It shows two things:

1. **Cooling / fans** via `liquidctl status` — liquid temp, pump RPM/duty, and each controller fan's RPM.
2. **Disk temperatures** via the host's `drivetemp` hwmon sensors.

For the disk temperatures to appear, load the module on the **host** (not the container): `modprobe drivetemp`. Because the container already runs `--privileged`, it can read the host's `/sys/class/hwmon/*` sensors and `/dev/sd*` devices.

**Spinning (spindle) disks are never woken by the monitor.** Before reading a disk's temperature, the script checks its power state with `hdparm -C` (a `CHECK POWER MODE` command that neither spins the drive up nor resets its spin-down timer). A disk in standby is reported as `STANDBY` and its temperature is skipped; only active/idle disks are read.

## Debug

I have made some poor attempts to help you and me debug your issues. use the `debug` tag to get the debug-log enabled version of the container. Or build it yourself using `Dockerfile.Debug`.
The container logs will be "slightly" more verbose but this could help understanding potential issues. (I hope) 