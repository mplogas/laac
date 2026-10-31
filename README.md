# LaaC: liquidctl as a Container

LaaC runs [liquidctl](https://github.com/liquidctl/liquidctl) in a container and configures AIO coolers and fan controllers from a YAML file. It applies the file on startup and again every time you save it.

It was built for an Unraid server with an NZXT Kraken X53 and a Corsair Commander Pro, as a lighter alternative to a Windows VM running CAM/iCUE.

**Tested hardware:** NZXT Kraken X53, Corsair Commander Pro. Other devices supported by liquidctl should work as long as their commands fit the config keys below.

## Quick start

1. Create a folder with a `config.yaml` in it (see [Configuration](#configuration)), e.g. `/mnt/appdata/laac/config.yaml`.
2. Start the container with that folder mounted to `/config`:

   ```sh
   docker run -d --name laac \
       --privileged \
       --network none \
       --log-opt max-size=1m --log-opt max-file=1 \
       -v /mnt/appdata/laac:/config \
       --restart=unless-stopped \
       mplogas/laac:latest
   ```

3. Check the logs (`docker logs laac`). The first line should be `using config: /config/config.yaml`, followed by the devices liquidctl found and the commands it ran.

## Configuration

### Example

```yaml
cooling:
  type: 'kraken'                                   # liquidctl --match kraken
  pump_speed: '20 20 30 35 35 60 40 80 45 100'     # liquid temp / pump duty % pairs
  color: 'set sync color off'                      # raw liquidctl arguments
controller:
  type: 'commander'                                # liquidctl --match commander
  # fan_sync_speed: '75'                           # all fans at once, overrides fanN_speed
  fan1_speed: '20 0 30 400 35 900 40 1200 45 1500 --temperature-sensor 2'
  fan2_speed: '20 0 30 400 35 900 40 1200 45 1500 --temperature-sensor 2'
  fan3_speed: 50                                   # fixed duty %
```

A complete example is in [config.template.yaml](config.template.yaml).

### Keys

Each key turns into exactly one liquidctl command. On startup and on every reload, the script first runs `liquidctl initialize all`, then the commands below.

| Key | liquidctl command | Notes |
|---|---|---|
| `cooling.type` | `liquidctl --match <type> list` | Enables the cooling section. Matched against the device description, e.g. `kraken`. |
| `cooling.pump_speed` | `liquidctl --match <type> set pump speed <value>` | Required when `cooling.type` is set. |
| `cooling.fan_speed` | `liquidctl --match <type> set fan speed <value>` | Only for coolers with a fan channel (Kraken Z and 2023 models). The Kraken X series has none. |
| `cooling.color` | `liquidctl --match <type> <value>` | The value is passed as raw arguments, so write the whole command, e.g. `set sync color off`. |
| `controller.type` | `liquidctl --match <type> list` | Enables the controller section, e.g. `commander`. |
| `controller.fan_sync_speed` | `liquidctl --match <type> set sync speed <value>` | Sets all fans. When present, `fanN_speed` keys are ignored. |
| `controller.fan1_speed` ... `fan6_speed` | `liquidctl --match <type> set fanN speed <value>` | One key per fan header. |

### Speed values

- **Fixed duty:** a single number, e.g. `50`.
- **Kraken curve:** pairs of liquid temperature (C) and duty (%), e.g. `'20 20 30 35 35 60 40 80 45 100'`. See the [Kraken guide](https://github.com/liquidctl/liquidctl/blob/main/docs/kraken-x3-z3-guide.md).
- **Commander Pro curve:** pairs of temperature (C) and RPM, plus `--temperature-sensor N` to pick the probe, e.g. `'20 0 30 400 35 900 --temperature-sensor 2'`. See the [Commander guide](https://github.com/liquidctl/liquidctl/blob/main/docs/corsair-commander-guide.md).

### Rules worth knowing

- Comments work on their own line and after a value (`fan1_speed: 20  # quiet`). An unquoted value ends at the first `#`, so quote the value if it needs a literal `#`.
- Fans you don't list keep whatever speed they were last set to (for example by an earlier `fan_sync_speed`). Removing a key does not reset the fan.
- Controller LEDs are not supported yet.

### Live reload

The script watches the `/config` folder. When `config.yaml` is saved, either written in place or renamed into place by the editor, the log shows `file changed` and the whole file is applied again.

## Running the container

### Docker compose

```yaml
services:
  laac:
    image: mplogas/laac:latest
    container_name: laac
    restart: unless-stopped
    network_mode: none
    privileged: true
    logging:
      options:
        max-size: "1m"
        max-file: "1"
    volumes:
      - /mnt/appdata/laac:/config
```

### Mounting the config

- **Mount a folder to `/config`.** This is the setup that reloads reliably.
- **Don't mount anything over `/app`.** The image keeps `run.sh` and `monitor.sh` there, and a mount replaces the whole folder.
- **Mounting only the file still works** (`-v <path>/config.yaml:/app/config.yaml`), but a single-file mount is tied to that exact file. Many editors save by writing a new file and renaming it over the old one, and from then on the container doesn't see any change until it is restarted. The log shows a `WARNING` when that happens.
- `--privileged` is needed for USB access to the devices. No network is needed.

### Unraid

Map the **pool path** (`/mnt/<pool>/...`), not the user share (`/mnt/user/...`). `/mnt/user` is a FUSE layer on top of the pools: the container still reads the new content through it, but a change made directly on the pool path doesn't trigger a reload.

### Image tags

| Tag | Built from | Notes |
|---|---|---|
| `latest` | `master` | Release version. |
| `dev` | `dev` branch or a manual workflow run | May contain unreleased changes. |
| `debug` | `master` | `SCRIPT_DEBUG=true`, ships `config.template.yaml` as `/app/config.yaml`, includes vim. |

## Monitoring

Need a quick look at what's going on thermally? A standby-safe dashboard ships in the image at `/app/monitor.sh`. It runs on demand only (it does **not** write to the container logs, so the config-reload history stays intact), loops until you press `Ctrl-C`, and refreshes every 10 seconds by default:

```sh
docker exec -it <container> /app/monitor.sh        # default 10s refresh
docker exec -it <container> /app/monitor.sh 30     # custom interval in seconds
```

It shows two things:

1. **Cooling / fans** via `liquidctl status`: liquid temp, pump RPM/duty, and each controller fan's RPM.
2. **Disk temperatures** via the host's `drivetemp` hwmon sensors.

For the disk temperatures to appear, load the module on the **host** (not the container): `modprobe drivetemp`. Because the container already runs `--privileged`, it can read the host's `/sys/class/hwmon/*` sensors and `/dev/sd*` devices.

**Spinning (spindle) disks are never woken by the monitor.** Before reading a disk's temperature, the script checks its power state with `hdparm -C` (a `CHECK POWER MODE` command that neither spins the drive up nor resets its spin-down timer). A disk in standby is reported as `STANDBY` and its temperature is skipped; only active/idle disks are read.

## Troubleshooting

**I saved the config, but the log shows no `file changed`.**
- Check the first log line. `using config: /app/config.yaml` means `/config` isn't mounted, so you're on the single-file fallback (see [Mounting the config](#mounting-the-config)).
- On Unraid, make sure the host path you mounted is the one you edit (pool path vs `/mnt/user`, see [Unraid](#unraid)).
- To check the watcher itself, rewrite the file from inside the container:
  `docker exec <container> sh -c 'cp /config/config.yaml /tmp/c && cat /tmp/c > /config/config.yaml'`.
  If that reloads, the watcher works and your edits arrive through a path the container can't watch.

**The log shows liquidctl's `Usage:` text.**
The command printed just above it got a value liquidctl can't parse: an empty value (e.g. a missing `pump_speed`), an odd number of curve values, or leftover text.

**`ERROR: ...: unexpected error: KeyError('fan')`**
The device has no channel with that name. For example, the Kraken X series has no `fan` channel, so remove `cooling.fan_speed`.

**A fan doesn't follow the config.**
- It isn't listed, so it keeps its last speed.
- `fan_sync_speed` is set, which overrides all `fanN_speed` keys.
- The `list` output at startup shows `Fan N control mode N/A`: nothing is detected on that header.

**The container doesn't start, or runs an old script.**
Something is mounted over `/app`. Mount your folder to `/config` instead.

**I need more detail in the logs.**
Set `SCRIPT_DEBUG=true` (`-e SCRIPT_DEBUG=true`) or use the `debug` tag. The script then prints all parsed values before and after every reload.

## Credits

- [liquidctl](https://github.com/liquidctl/liquidctl) does all the device work.
- [avpnusr/liquidctl-docker](https://github.com/avpnusr/liquidctl-docker) was the starting point for running liquidctl in a container.
- The YAML parser is based on [Stefan Farestam's bash parser](https://stackoverflow.com/a/21189044).
- Config watching uses [inotify-tools](https://github.com/inotify-tools/inotify-tools).

## License

[MIT](LICENSE.md)
