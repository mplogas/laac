#! /bin/bash

## source: https://stackoverflow.com/a/21189044
function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
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

function configure_liquidctl {
   liquidctl initialize all

   ### AIO cooling (required)
   liquidctl --match $cooling_type list
   liquidctl --match $cooling_type set pump speed $cooling_pump_speed

   if [ ! -z "$cooling_fan_speed" ]; then
      echo "cooling fan: $cooling_fan_speed"
      liquidctl --match $cooling_type set fan speed $cooling_fan_speed
   fi

   if [ ! -z "$cooling_color" ]; then
      echo "cooling color: $cooling_color"
      liquidctl --match $cooling_type $cooling_color
   fi


   ## controller (optional): commander pro or alike
   if [ ! -z "$controller_type" ]; then
      liquidctl --match $controller_type list

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
}

eval $(parse_yaml /app/config.yaml)
configure_liquidctl

inotifywait -q -m -e close_write /app/config.yaml |
while read -r filename event; do
  echo "file changed"
  configure_liquidctl
done



