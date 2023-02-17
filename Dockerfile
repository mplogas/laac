FROM ubuntu:latest

RUN mkdir /app
COPY run.sh /app/run.sh

RUN apt update \
 && apt install -y python3 python3-dev python3-pip python3-setuptools python3-pkg-resources python3-hidapi python3-usb i2c-tools python3-smbus libusb-1.0-0 gcc make udev libudev-dev inotify-tools --no-install-recommends \
 && python3 -m pip install -U wheel cython \
 && python3 -m pip install -U liquidctl \
 && apt remove --purge -y make gcc python3-dev libudev-dev python3-pip \
 && apt autoremove -y \
 && chmod 0700 /app/run.sh \
 && rm -rf /var/lib/apt/lists/*

 CMD [ "/app/run.sh" ]