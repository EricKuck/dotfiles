# imessage-bridge

macOS 15 VM on IRLBuild (Tart VM `imessage-bridge`) running Messages and
BlueBubbles Server with SIP disabled, for mautrix-imessage on KuckyNas.

IRLBuild forwards to it:

| IRLBuild port | Guest | For |
|---|---|---|
| 1234 | BlueBubbles | mautrix-imessage on KuckyNas |
| 2222 | SSH | `ssh -p 2222 eric@192.168.1.23` |
| 5901 | Screen Sharing | `vnc://192.168.1.23:5901` |

## First-time setup

1. On IRLBuild, build the VM **before** switching IRLBuild to the config with
   the port forwards (the build briefly allows SSH as `admin`/`admin`):
   `nix run path:.#imessage-vm-image`. It asks for eric's password in the VM
   and prints the guest's sops age recipient at the end.
2. Add that recipient to `.sops.yaml` with a rule for `secrets/imessage_bridge.yaml`
   (above the catch-all rule), then create the file with a random
   `bluebubbles-password` (e.g. `openssl rand -hex 32`). Put the same value
   in KuckyNas's secrets as `bluebubbles-password`.
3. Switch IRLBuild; the VM starts.
4. `imessage-vm-deploy` (from the repo on IRLBuild) applies this config.
5. Over Screen Sharing:
   - Sign into the Apple Account, and into Messages.
   - System Settings → Privacy & Security: give
     `/Applications/Nix Apps/BlueBubbles.app` Full Disk Access and
     Accessibility, then accept the Automation/Contacts prompts.
   - Check BlueBubbles shows the Private API as connected.
6. On the iPhone: Settings → Messages → Text Message Forwarding → imessage-bridge
   (for SMS), and make sure Send & Receive includes the phone number.
7. Set `enable = true` in `KuckyNas/matrix/imessage-bluebubbles.nix` and
   deploy KuckyNas.

## Later

- Config changes: `imessage-vm-deploy` from IRLBuild.
- macOS updates are off; install them by hand once BlueBubbles supports the
  new version. Never rebuild the VM to update it: a fresh VM means signing
  into iMessage again.
