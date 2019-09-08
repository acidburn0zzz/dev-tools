# dev-tools
Tools and scripts to be used at development and maintenance.

## device-info
This program shows info about certain devices and environments in way that
it can be used in other programs and scripts when deciding what to do in certain cases
during EndeavourOS installation process.

I'm currently developing this program to include many kinds of hardware related infos.
All input is very welcome!

The options are (currently):

Option | Description
--- | ---
--wireless<br>--wifi | show info about the wireless LAN device
--display | show info about the display controller
--vga | show info about the VGA compatible driver (note that there may be more than one graphics card)
--cpu | show the name of the CPU type (e.g. GenuineIntel)
--virtualbox | echoes "yes" if running in VirtualBox VM, otherwise "no"

