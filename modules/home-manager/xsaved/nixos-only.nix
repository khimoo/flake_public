{ config, ... }:
{
  assertions = [
    {
      assertion = config.submoduleSupport.enable;
      message = "xsaved: PostgreSQL provisioning requires Home Manager inside NixOS";
    }
  ];
}
