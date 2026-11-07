def public(host):
    return {
        "users": host.windows_vm_users,
        "domain": getattr(host, "windows_vm_domain", None),
        "boot_timeout": getattr(host, "windows_vm_boot_timeout", 600),
    }

def config(host, incoming):
    if not host.linux:
        fail("windows_vm: supports Linux only")
    domain = getattr(host, "windows_vm_domain", None)
    if domain != None and not incoming:
        fail("windows_vm: launcher requires gui")
    nixos = {
        "virtualisation.spiceUSBRedirection.enable": True,
        "virtualisation.libvirtd.enable": True,
        # virtiofs を共有する VM は suspend から復元できず、保存ファイルがルートを埋める。
        "virtualisation.libvirtd.onShutdown": "shutdown",
        # VM は使うときだけランチャーで起動する。
        "virtualisation.libvirtd.onBoot": "ignore",
        "virtualisation.libvirtd.qemu.package": pkg("qemu_kvm"),
        "virtualisation.libvirtd.qemu.runAsRoot": True,
        "virtualisation.libvirtd.qemu.swtpm.enable": True,
        "virtualisation.libvirtd.qemu.vhostUserPackages": [pkg("virtiofsd")],
        ("environment", "etc", "ovmf/edk2-x86_64-secure-code.fd", "source"): concat(pkg("qemu_kvm"), "/share/qemu/edk2-x86_64-secure-code.fd"),
        ("environment", "etc", "ovmf/edk2-i386-vars.fd", "source"): concat(pkg("qemu_kvm"), "/share/qemu/edk2-i386-vars.fd"),
        "programs.virt-manager.enable": True,
        "systemd.services.libvirt-network-autostart": {
            "description": "Enable autostart for libvirt default network",
            "after": ["libvirtd.service"],
            "requires": ["libvirtd.service"],
            "wantedBy": ["multi-user.target"],
            "serviceConfig": {"Type": "oneshot", "ExecStart": concat(exe("libvirt", "virsh"), " net-autostart default"), "RemainAfterExit": "yes"},
        },
    }
    for name in host.windows_vm_users:
        nixos[("users", "users", name, "extraGroups")] = ["libvirtd"]
    return {"nixos": nixos}
