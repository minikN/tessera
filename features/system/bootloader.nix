{ lib, mkFeature, ... }:

mkFeature {
  name = "bootloader";
  enableByDefault = true;

  doc = {
    summary = "GRUB as the boot loader on UEFI systems.";
    description = ''
      Enabled by default on NixOS. Installs GRUB for UEFI and lets it update
      the EFI variables; other operating systems on the machine appear in the
      boot menu (os-prober). Disable it with `bootloader.enable = false;` to
      set up a different boot loader in the host's `nixos` block.
    '';
  };

  nixos = { ... }: {
    boot.loader = {
      grub = {
        enable = true;
        efiSupport = true;
        useOSProber = true;
        device = "nodev";
      };
      efi.canTouchEfiVariables = true;
    };
  };
}
