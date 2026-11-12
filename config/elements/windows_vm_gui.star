when = ["windows_vm", "gui"]

def user_config(windows_vm):
    if windows_vm.domain == None:
        fail("windows_vm_gui: set windows_vm_domain in the host file")
    timeout = windows_vm.boot_timeout
    if type(timeout) != "int" or timeout <= 0:
        fail("windows_vm: boot timeout must be positive")
    launcher = shellAppEnv("windows-vm", [
        pkg("coreutils"), repoPkg("packages/freerdp-grab-once"), pkg("libnotify"), pkg("libsecret"),
        pkg("libvirt"), pkg("util-linux"), pkg("virt-manager"),
    ], {"WINDOWS_VM_DOMAIN": windows_vm.domain, "WINDOWS_VM_BOOT_TIMEOUT": str(timeout)}, repoText("modules/home-manager/windows-vm.sh"))
    executable = concat(launcher, "/bin/windows-vm")
    return {"home": {
        "home.packages": [launcher],
        # AltGr では SDL が KMOD_RALT ではなく KMOD_MODE を立てる（docs/architecture/windows-vm.md）。
        ("xdg", "configFile", "freerdp/sdl-freerdp.json", "text"): toJSON({"SDL_KeyModMask": ["KMOD_MODE"], "SDL_Grab": "SDL_SCANCODE_RALT"}),
        "xdg.desktopEntries.windows-vm": {
            "name": "Windows",
            "comment": "VM の Windows を起動して FreeRDP で接続する",
            "exec": concat(executable, " connect"),
            "icon": "computer",
            "terminal": False,
            "categories": ["System"],
            "actions": {
                "shutdown": {"name": "シャットダウン", "exec": concat(executable, " shutdown")},
                "console": {"name": "SPICE で開く", "exec": concat(executable, " console")},
            },
        },
    }}
