{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  definition = ./win11.xml;
  uuid = builtins.elemAt (builtins.match ".*<uuid>([^<]+)</uuid>.*" (builtins.readFile definition)) 0;
  virsh = "${lib.getBin pkgs.libvirt}/bin/virsh -c qemu:///system";
in
{
  imports = [ inputs.nixvirt.nixosModules.default ];

  # Set by windows_vm.star; do not predicate on libvirtd.enable because
  # enabling NixVirt itself contributes to that option.
  config = lib.mkIf config.virtualisation.spiceUSBRedirection.enable {
    virtualisation.libvirt = {
      enable = true;
      # Keep the host's libvirt build; NixVirt uses it for its Python bindings too.
      package = pkgs.libvirt;
      verbose = true;
      connections."qemu:///system" = {
        domains = [
          {
            inherit definition;
            active = null;
            restart = false;
          }
        ];
        networks = null;
        pools = null;
      };
    };

    # NixVirt 0.6 prunes unlisted domains. Refuse to run if any other VM exists.
    systemd.services.nixvirt = {
      serviceConfig.RemainAfterExit = true;
      preStart = ''
        domains=$(${virsh} list --all --uuid)
        for domain in $domains; do
          if [ "$domain" != ${lib.escapeShellArg uuid} ] || [ "$(${virsh} domname "$domain")" != win11 ]; then
            echo "Refusing NixVirt sync: unmanaged domain $domain" >&2
            exit 1
          fi
        done
      '';
    };
  };
}