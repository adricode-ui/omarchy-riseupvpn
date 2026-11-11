# Riseup VPN for Omarchy

<img width="423" height="571" alt="screenshot-2026-11-11_08-37-21" src="https://github.com/user-attachments/assets/9c4c96f9-445b-4e99-8e84-ad000df0e5b9" />

Bar widget for [Omarchy](https://omarchy.org/): connect Riseup OpenVPN and
toggle its nftables kill switch from the shell.

Plugin id: `adri.vpn-killswitch`

**This is not a one-command install.** The plugin is only the bar UI and a
root helper. Riseup itself must already work as the systemd unit
`openvpn-client@riseup` before the toggles do anything. The official Riseup
GUI is broken; use the command-line configurator instead.

## What you get

- A bar icon for the tunnel (`󰖂`) plus a lock for the kill switch.
- A click opens a panel: VPN toggle, kill switch toggle, public IP.
- Connecting the VPN always turns the kill switch **on**.
- Disconnecting the VPN does **not** turn the kill switch off. If it stays
  on, the Internet is blocked and only the local network still works.
- An urgent lock (theme alert color) means: kill switch on, VPN down.

The lock is the intended fail-closed behavior, not a bug.

## Prerequisites

| Need | Where it comes from |
| --- | --- |
| Omarchy (Arch + Hyprland + Omarchy shell) | already installed |
| `systemd`, `nftables`, `polkit`, `jq`, `python`, `curl`, `iproute2` | already on Omarchy |
| OpenVPN client | pulled in by the configurator |
| Riseup config, client cert, `openvpn-client@riseup` | AUR, see below |

You also need a session where you can type a `sudo` password once, for
`setup`.

## 1. Do not use the official GUI

The AUR package [`riseup-vpn`](https://aur.archlinux.org/packages/riseup-vpn)
(Bitmask / LEAP) is the official client. On this machine it was installed
with:

```bash
yay -S riseup-vpn
```

That build took a long time. The GUI is bloated and broken (polkit-agent
errors, an autostart desktop file that does nothing under Hyprland). Remove
it:

```bash
sudo pacman -Rns riseup-vpn
```

Skip this package on a new machine. The steps below replace it.

## 2. Install the command-line configurator

Use [`riseup-vpn-configurator`](https://github.com/kmille/riseup-vpn-configurator)
from the AUR. It writes a real OpenVPN unit instead of shipping the GUI.

```bash
omarchy pkg aur add riseup-vpn-configurator
```

or:

```bash
yay -S riseup-vpn-configurator
```

That package also installs `openvpn` and `openvpn-reconnect` (needed so the
tunnel comes back after suspend).

## 3. Generate the OpenVPN config

```bash
sudo riseup-vpn-configurator -c
sudo riseup-vpn-configurator -u
sudo riseup-vpn-configurator -g
```

| Flag | What it does |
| --- | --- |
| `-c` | Check `/etc/riseup-vpn.yaml`, and write a default file if it is missing |
| `-u` | Fetch the gateway list and a client certificate (valid 90 days) |
| `-g` | Write `/etc/openvpn/client/riseup.conf` |

Optional: edit `/etc/riseup-vpn.yaml` (server, protocol, port, excluded
routes) then run `-g` again. The packaged default is
`vpn07-par.riseup.net`, UDP port 53, user/group `openvpn`.

The yaml and the OpenVPN certs are root-only. Do not copy them into this
plugin or into git.

## 4. Start Riseup at boot

These are the commands used on this machine, after the GUI was removed:

```bash
sudo systemctl enable --now openvpn-client@riseup
```

`enable` makes the unit start at boot. `--now` also starts it immediately.

If you would rather connect only from the bar, enable without starting:

```bash
sudo systemctl enable openvpn-client@riseup
```

Check:

```bash
systemctl is-enabled openvpn-client@riseup
sudo riseup-vpn-configurator -s
```

`enabled` is what you want. The plugin reads that as “starts at boot”.

If you run `enable --now` **before** plugin `setup`, the tunnel comes up
without the kill-switch drop-in. That is fine. `setup` adds the drop-in
afterwards; the next VPN start (or a connect from the panel) will arm the
kill switch.

## 5. Install the plugin

```bash
omarchy plugin add https://github.com/adricode-ui/omarchy-riseupvpn.git --enable
```

That clones the repo into `~/.config/omarchy/plugins/adri.vpn-killswitch/`
and offers to place the widget. The default section is **right** (next to
the network icon).

Then install the root helper, kill switch, polkit rule, and systemd drop-in:

```bash
sudo ~/.config/omarchy/plugins/adri.vpn-killswitch/bin/riseup-ctl setup
```

`setup` needs a terminal so you can type your password. It installs:

- `/usr/local/bin/riseup-ctl` (root-owned copy of the helper)
- `/usr/local/bin/riseup-killswitch` (nftables kill switch)
- `/etc/systemd/system/openvpn-client@riseup.service.d/killswitch.conf`
  (`ExecStartPost=/usr/local/bin/riseup-killswitch on`)
- `/usr/share/polkit-1/actions/org.quattro.riseup.policy`
- `/etc/polkit-1/rules.d/49-quattro-riseup.rules`

The polkit rule is passwordless only for the account that ran `setup`, and
only on the local foreground session. Each action is pinned to
`/usr/local/bin/riseup-ctl` and to one subcommand (`status`, `vpn-on`,
`vpn-off`, `ks-on`, `ks-off`). Extra arguments are ignored.

Until `setup` has been run, the icon still shows the VPN. The kill switch
stays “unknown”, and the panel tells you to install the helper.

After a plugin update, run `setup` again so the root copies match.

## 6. Use it

Left-click the bar icon.

| Control | Effect |
| --- | --- |
| VPN toggle | `systemctl start` / `stop` `openvpn-client@riseup` |
| Kill switch toggle | `/usr/local/bin/riseup-killswitch on` / `off` |
| Refresh IP | `curl` to `https://api.ipify.org` (then `api6.ipify.org`) |

Public IP is fetched only when the panel opens or when you refresh it. The
bar polls status every 3 seconds (`refreshIntervalSec` in `shell.json`,
range 2–30).

### Coupling

This matches the systemd drop-in. The plugin does not change it.

1. Turn VPN **on** → kill switch turns **on**, even if you had turned it off.
2. Turn VPN **off** → kill switch stays as it was. If it is still on, WAN
   traffic is dropped; LAN still works.
3. Tunnel without a kill switch: connect, then turn the kill switch **off**.
   The next connect will turn it back on.

### Kill switch exceptions

The nftables table `inet riseup_ks` drops outbound traffic except:

- `lo`
- `tun0`
- `ct state established,related`
- `192.168.0.0/16`
- `10.0.0.0/8`
- `fd00::/8`

Edit `/usr/local/bin/riseup-killswitch` if your LAN is different, then run
`setup` again or copy the script back yourself.

### Client certificate

Riseup client certs last **90 days**. When the tunnel starts failing with
auth errors:

```bash
sudo riseup-vpn-configurator -u
sudo riseup-vpn-configurator -g
```

Then reconnect from the panel (or `sudo systemctl restart openvpn-client@riseup`).

### Polkit cost

A program already running as the account that ran `setup` can flip the VPN
and the kill switch without asking for a password. Same compromise as the
Tor bar toggle. To be asked every time:

```bash
sudo rm /etc/polkit-1/rules.d/49-quattro-riseup.rules
```

## Updates

```bash
omarchy plugin update adri.vpn-killswitch
sudo ~/.config/omarchy/plugins/adri.vpn-killswitch/bin/riseup-ctl setup
```

## Remove

```bash
sudo /usr/local/bin/riseup-killswitch off
sudo systemctl disable --now openvpn-client@riseup
omarchy plugin remove adri.vpn-killswitch
```

Optional leftovers: `/usr/local/bin/riseup-ctl`, `/usr/local/bin/riseup-killswitch`,
the systemd drop-in, the polkit policy and rule, `/etc/riseup-vpn.yaml`,
and the AUR package `riseup-vpn-configurator`.

## License

MIT. See [LICENSE](LICENSE).
