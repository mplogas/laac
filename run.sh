#! /bin/bash

## source: https://stackoverflow.com/a/21189044
## extended to ignore trailing "# comments": a quoted value ends at its own
## closing quote ('#' inside quotes is kept), an unquoted value ends at the
## first '#' (quote the value if it needs a literal '#')
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s\"\([^\"]*\)\"$s\(#.*\)\{0,1\}\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s'\([^']*\)'$s\(#.*\)\{0,1\}\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\([^#]*[^#[:space:]]\)\{0,1\}$s\(#.*\)\{0,1\}\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}


function debug_variables {
   # todo: test printenv/env and consider grepping by prefix
   # https://stackoverflow.com/questions/1305237/how-to-list-variables-declared-in-script-in-bash
   echo "cooling type: $cooling_type"
   echo "cooling pump speed: $cooling_pump_speed"
   echo "cooling fan speed: $cooling_fan_speed"
   echo "cooling color: $cooling_color"
   echo "controller type: $controller_type"
   echo "controller fan sync: $controller_fan_sync_speed"
   echo "controller fan 1: $controller_fan1_speed"
   echo "controller fan 2: $controller_fan2_speed"
   echo "controller fan 3: $controller_fan3_speed"
   echo "controller fan 4: $controller_fan4_speed"
   echo "controller fan 5: $controller_fan5_speed"
   echo "controller fan 6: $controller_fan6_speed"
}

## bandaid, improve with todo
function unset_optional_variables {
   echo "unsetting all variables"
   unset cooling_type
   unset cooling_pump_speed
   unset cooling_fan_speed
   unset cooling_color
   unset controller_type
   unset controller_fan_sync_speed
   unset controller_fan1_speed
   unset controller_fan2_speed
   unset controller_fan3_speed
   unset controller_fan4_speed
   unset controller_fan5_speed
   unset controller_fan6_speed
}

function configure_liquidctl {
   liquidctl initialize all

   ### AIO cooling (optional now, but requires pump speed when used)   
   if [ ! -z "$cooling_type" ]; then
      liquidctl --match $cooling_type list

      echo "cooling pump: $cooling_pump_speed"
      liquidctl --match $cooling_type set pump speed $cooling_pump_speed

      if [ ! -z "$cooling_fan_speed" ]; then
         echo "cooling fan: $cooling_fan_speed"
         liquidctl --match $cooling_type set fan speed $cooling_fan_speed
      fi

      if [ ! -z "$cooling_color" ]; then
         echo "cooling color: $cooling_color"
         liquidctl --match $cooling_type $cooling_color
      fi
   fi

   ## controller (optional)
   if [ ! -z "$controller_type" ]; then
      liquidctl --match $controller_type list

      if [ ! -z "$controller_fan_sync_speed" ]; then         
         echo "controller sync fan: $controller_fan_sync_speed"
         liquidctl --match $controller_type set sync speed $controller_fan_sync_speed
      else 

         if [ ! -z "$controller_fan1_speed" ]; then
            echo "controller fan1: $controller_fan1_speed"
            liquidctl --match $controller_type set fan1 speed $controller_fan1_speed
         fi

         if [ ! -z "$controller_fan2_speed" ]; then
            echo "controller fan2: $controller_fan2_speed"
            liquidctl --match $controller_type set fan2 speed $controller_fan2_speed
         fi

         if [ ! -z "$controller_fan3_speed" ]; then
            echo "controller fan3: $controller_fan3_speed"
            liquidctl --match $controller_type set fan3 speed $controller_fan3_speed
         fi

         if [ ! -z "$controller_fan4_speed" ]; then
            echo "controller fan4: $controller_fan4_speed"
            liquidctl --match $controller_type set fan4 speed $controller_fan4_speed
         fi

         if [ ! -z "$controller_fan5_speed" ]; then
            echo "controller fan5: $controller_fan5_speed"
            liquidctl --match $controller_type set fan5 speed $controller_fan5_speed
         fi

         if [ ! -z "$controller_fan6_speed" ]; then
            echo "controller fan6: $controller_fan6_speed"
            liquidctl --match $controller_type set fan6 speed $controller_fan6_speed
         fi
      fi
   fi
}


function reload_config {
   echo "file changed"
   if [ ! -z "$SCRIPT_DEBUG" ]; then
      echo "cached:"
      debug_variables
   fi

   unset_optional_variables

   if [ ! -z "$SCRIPT_DEBUG" ]; then
      echo "cleared:"
      debug_variables
   fi

   eval $(parse_yaml "$config_file")

   if [ ! -z "$SCRIPT_DEBUG" ]; then
      echo "reload:"
      debug_variables
   fi

   configure_liquidctl
}


## preferred: config.yaml inside a directory mounted to /config
## legacy:    config.yaml mounted as a single file to /app/config.yaml
config_dir=/config
if [ -f "$config_dir/config.yaml" ]; then
   config_file="$config_dir/config.yaml"
else
   config_file=/app/config.yaml
fi
echo "using config: $config_file"

eval $(parse_yaml "$config_file")
if [ ! -z "$SCRIPT_DEBUG" ]; then
   echo "initial:"
   debug_variables
fi
configure_liquidctl

if [ "$config_file" == "$config_dir/config.yaml" ]; then
   ## watching the directory catches in-place writes (close_write) as well as
   ## editors that save by writing a temp file and renaming it (moved_to)
   inotifywait -q -m -e close_write -e moved_to --format '%f' "$config_dir" |
   while read -r changed; do
      [ "$changed" == "config.yaml" ] && reload_config
   done
else
   ## a single-file bind mount is pinned to the file's inode. editors that save
   ## via rename create a new inode on the host, which never reaches the
   ## container: no more events, stale content. the old inode's link count
   ## dropping to 0 (attrib event) is the only trace, so make it loud.
   inotifywait -q -m -e close_write -e attrib --format '%e' "$config_file" |
   while read -r event; do
      if [ "$(stat -c %h "$config_file")" == "0" ]; then
         echo "WARNING: $config_file was replaced on the host (editor saved via rename)."
         echo "WARNING: this container can no longer see config changes. restart it to apply the new config,"
         echo "WARNING: or mount the config directory to /config instead (see README)."
      elif [[ "$event" == CLOSE_WRITE* ]]; then
         reload_config
      fi
   done
fi



