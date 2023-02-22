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
3. Cooling type and Cooling pump speed are the only required parameters. However, when using the controller its type must be specified.
4. The liquidctl Kraken guide describes pump temperature/duty pairs, color settings and fan settings for supported AiO coolings. This could be easily expanded for other AiOs (https://github.com/liquidctl/liquidctl/blob/main/docs/kraken-x3-z3-guide.md)
5. Similar to the Kraken guide, liquidctl offers a documentation to set up the Corsair Commander Pro (https://github.com/liquidctl/liquidctl/blob/main/docs/corsair-commander-guide.md). Programming the controller fan speeds follows a pattern similar to the AiO fan speed / pump speed, except that you can specify a temperature probe.
6. To control all fans with the same speed (```liquidctl --match <match> set sync speed <speed>```), define ```fan_sync_speed: '<speed>'``` instead of ```fan<x>_speed: '<speed>'``` as controller property.
7. Controller LED is not yet supported, but can be easily added.

**sample config.yaml**

```yaml
cooling:
    type: 'kraken'
    pump_speed: '20 20 30 35 35 60 40 80 45 100'
    fan_speed: '20 0 30 20 30 40 35 60 40 75 50 100'
    color: 'set sync color off'
controller:
    type: 'commander'
    fan1_speed: '20 0 30 400 35 900 40 1200 45 1500 --temperature-sensor 2'
    fan2_speed: '20 0 30 400 35 900 40 1200 45 1500 --temperature-sensor 2'
    fan3_speed: '25 0 30 500 35 800 40 1000 45 1500 --temperature-sensor 1'
    fan4_speed: '25 0 30 500 35 1000 40 1500 --temperature-sensor 4'
    fan5_speed: '25 0 30 500 35 1000 40 1500 --temperature-sensor 4'
    fan6_speed: '25 0 30 500 35 1000 40 1500 --temperature-sensor 3'
```


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

