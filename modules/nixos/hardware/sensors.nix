{
  config,
  pkgs,
  ...
}: {
  hardware = {
    usb-modeswitch.enable = true;
    sensor.iio.enable = true;
    i2c.enable = true;
    steam-hardware.enable = true;
    bolt.enable = true;
  };
}
