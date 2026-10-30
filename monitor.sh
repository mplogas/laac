#! /bin/bash

## monitor.sh — on-demand, standby-safe temp/fan dashboard for laac.
## Usage: /app/monitor.sh [interval_seconds]   (default 10)
## Run it with:  docker exec -it <container> /app/monitor.sh
## Ctrl-C to quit.
##
## Disk temps are read via the host's drivetemp hwmon sensors (needs the
## drivetemp module loaded on the host + a privileged container). Before
## reading a disk's temperature we check its power state with `hdparm -C`
## (a CHECK POWER MODE command, which neither spins the drive up nor resets
## its spin-down timer). A disk in standby/sleeping is reported as STANDBY
## and its temperature is NOT read, so monitoring never wakes a sleeping
## drive.

INTERVAL="${1:-10}"

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
   echo "Invalid interval '$INTERVAL' — falling back to 10s."
   INTERVAL=10
fi

trap 'printf "\n"; exit 0' INT

## clear the screen, with a plain-ANSI fallback when TERM is unset
clear_screen() {
   clear 2>/dev/null || printf '\033[H\033[2J'
}

## liquidctl status for every mounted device (Kraken pump, Commander fans, ...)
print_cooling() {
   if ! command -v liquidctl >/dev/null 2>&1; then
      echo "  liquidctl not found"
      return
   fi
   local out
   out="$(liquidctl status 2>&1)"
   if [ -z "$out" ]; then
      echo "  no liquidctl devices found"
   else
      echo "$out" | sed 's/^/  /'
   fi
}

## resolve the /dev block name (e.g. sda) for a drivetemp hwmon directory
resolve_blockdev() {
   local h="$1" b
   for b in "$h"/device/block/*; do
      [ -e "$b" ] && { basename "$b"; return; }
   done
}

## power state via CHECK POWER MODE — safe, never wakes the drive.
## echoes: standby | active | unknown. Some drives (e.g. certain Seagate
## IronWolf) return a nonstandard code while awake that hdparm prints as
## "unknown", but the ATA standby code (0x00) is standard, so a spun-down
## drive is still reliably reported as "standby" here.
power_state() {
   local dev="$1" line
   line="$(hdparm -C "/dev/$dev" 2>/dev/null | grep -i 'drive state is')"
   case "$line" in
      *standby*|*sleeping*) echo "standby" ;;
      *active*|*idle*)      echo "active" ;;
      *)                    echo "unknown" ;;
   esac
}

## trim leading/trailing whitespace (sysfs model strings are space-padded)
trim() {
   local s="$1"
   s="${s#"${s%%[![:space:]]*}"}"
   s="${s%"${s##*[![:space:]]}"}"
   printf '%s' "$s"
}

print_disks() {
   local found=0 h model blk state temp_raw temp note guarded
   for h in /sys/class/hwmon/hwmon*; do
      [ -r "$h/name" ] || continue
      [ "$(cat "$h/name")" = "drivetemp" ] || continue
      found=1

      model="$(trim "$(cat "$h/device/model" 2>/dev/null)")"
      [ -z "$model" ] && model="?"
      blk="$(resolve_blockdev "$h")"

      if [ -n "$blk" ] && command -v hdparm >/dev/null 2>&1; then
         state="$(power_state "$blk")"
         guarded=1
      else
         ## no /dev mapping or no hdparm: standby can't be checked at all
         state="unknown"
         guarded=0
      fi

      ## Skip ONLY on a positive standby/sleeping reading. The standby code
      ## is reported reliably even by drives that return "unknown" while
      ## awake, so a spun-down drive is always caught here and never read.
      if [ "$state" = "standby" ]; then
         printf "  %-20s %-10s STANDBY (temp skipped)\n" "$model" "${blk:+/dev/$blk}"
         continue
      fi

      temp_raw="$(cat "$h/temp1_input" 2>/dev/null)"
      if [ -z "$temp_raw" ]; then
         printf "  %-20s %-10s n/a\n" "$model" "${blk:+/dev/$blk}"
         continue
      fi

      temp=$(( temp_raw / 1000 ))
      ## -128C is drivetemp's invalid-reading marker (e.g. after resume);
      ## anything absurdly high is bogus too.
      if [ "$temp" -le -128 ] || [ "$temp" -ge 200 ]; then
         printf "  %-20s %-10s n/a\n" "$model" "${blk:+/dev/$blk}"
         continue
      fi

      ## Flag only the genuinely unguarded case: hdparm couldn't run (no
      ## mapping / not installed), so standby was never checked. A drive
      ## that merely reports "unknown" while awake is still guarded — its
      ## standby state would have been caught above — so it reads clean.
      note=""
      [ "$guarded" -eq 0 ] && note="  (standby not checkable — read not guarded)"
      printf "  %-20s %-10s %d°C%s\n" "$model" "${blk:+/dev/$blk}" "$temp" "$note"
   done

   if [ "$found" -eq 0 ]; then
      echo "  no drivetemp sensors found (is the module loaded on the host?)"
   fi
}

while true; do
   clear_screen
   echo "laac monitor — $(date '+%Y-%m-%d %H:%M:%S')   (refresh ${INTERVAL}s, Ctrl-C to quit)"
   echo
   echo "Cooling / Fans:"
   print_cooling
   echo
   echo "Disks:"
   print_disks
   sleep "$INTERVAL"
done
