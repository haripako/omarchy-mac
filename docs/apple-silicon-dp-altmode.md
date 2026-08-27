# Apple Silicon: external DisplayPort over USB-C

Plugging an external monitor into an Apple Silicon Mac running Asahi and getting
nothing at all is expected today, not a fault. This documents why, so the
question can be answered in one line instead of an afternoon of cable swapping.

Observed on a MacBook Pro 13" M1 (j293) on Asahi Alarm with `linux-asahi` 7.1.6.

## Symptoms

- An external monitor over USB-C stays dark. No connector appears, or one
  appears and never leaves `disconnected`.
- The cable and the monitor are fine and work on other machines.
- `lsusb` shows a "USB Billboard Device" for the monitor, which reads like a
  failure but is not — see below.
- SuperSpeed disappears while the monitor is attached, which also reads like a
  bad cable and also is not.

## Why nothing happens

Apple Silicon has two display controllers. The internal panel is driven by
`dcp`; anything external goes through a second one, `dcpext`. **No t8103 device
tree enables `dcpext`**, not even in `asahi-wip-7.2`, so there is no controller
for an external display to attach to. Asahi marks DisplayPort alt mode on M1 as
work in progress.

That is the whole answer for a stock install. Everything below it in the chain
works and is already merged: the Type-C PHY does DP mode, the display crossbar
is wired, and the cd321x driver registers the port altmodes, switches the mux
and reads DisplayPort status out of the controller.

What makes this expensive to diagnose is that every layer fails *silently*.
There is no error in `dmesg`, nothing in the compositor log, and each failure
looks exactly like the one before it from userspace.

## Two things that look like faults and are not

**The USB Billboard Device.** A monitor that exposes a USB hub will enumerate a
Billboard device. Its presence says nothing about whether alt mode succeeded.

**SuperSpeed disappearing.** With DisplayPort pin assignment C, all four
high-speed lanes carry DisplayPort and USB drops to 2.0. Losing SuperSpeed while
a monitor is attached is what success looks like, not a bad cable.

## The port matters, and its number does not

Not every USB-C port has DisplayPort wired to a display-capable PHY. On j293
only one of the two does — the lower one on the left edge, furthest from the
hinge, which the device tree labels `USB-C Left-front` at i2c address `0-003f`.

The `portN` index under `/sys/class/typec` is assigned in i2c probe order and
**is not stable across boots**: the same physical port was observed as `port1`
on one boot and `port0` on the next. Anything that resolves a port must do it by
i2c address, never by the number.

## Checking a machine

```bash
omarchy debug dp-altmode
```

walks the chain in order and stops at the first thing that is not in place:
whether `dcpext` is enabled, which port carries DisplayPort, where the cable
actually is, and what DRM ended up with.

```bash
omarchy-hw-dp-altmode
```

returns true when external DisplayPort output is actually wired up — both that a
USB-C connector carries the `displayport` phandle and that the node it names is
enabled. Either half alone is a half-configured machine, which is why the check
requires both.

## Enabling it

Out of scope for this repository at present. Making external DisplayPort work on
M1 needs a patched device tree plus two out-of-tree kernel modules, and a kernel
update silently reverts all of it, so it is not something to turn on by default
in a distribution that updates kernels unattended.

A working implementation, the evidence behind it, and the one unresolved bug are
written up at https://github.com/haripako/dp-altmode. The kernel-side fix it
depends on is being sent to AsahiLinux/linux separately; once DisplayPort alt
mode lands upstream, none of this is needed.
