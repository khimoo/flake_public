{ config, lib, pkgs, settings, ... }:

let
  cfg = config.programs.gnomeDisplayDefault;

  pythonEnv = pkgs.python3.withPackages (p: [ p.pygobject3 ]);

  # display-configuration-switcher の保存設定のうち「スリープ直前に active だった
  # もの」の名前を $XDG_RUNTIME_DIR にスナップショットし、復帰時にそれを Mutter
  # の ApplyMonitorsConfig 経由で再適用するスクリプト。
  helperScript = pkgs.writeScriptBin "gnome-display-default" ''
    #!${pythonEnv}/bin/python3
    import os
    import pathlib
    import sys
    from gi.repository import Gio, GLib  # noqa: E402

    SCHEMA_ID = "org.gnome.shell.extensions.display-configuration-switcher"

    SNAPSHOT_PATH = (
        pathlib.Path(os.environ["XDG_RUNTIME_DIR"])
        / "gnome-display-default"
        / "last-config-name"
    )


    def get_settings():
        src = Gio.SettingsSchemaSource.get_default()
        if src is None or src.lookup(SCHEMA_ID, True) is None:
            print(
                f"schema {SCHEMA_ID} not found; is the extension installed?",
                file=sys.stderr,
            )
            return None
        return Gio.Settings.new(SCHEMA_ID)


    def cmd_snapshot():
        gs = get_settings()
        if gs is None:
            return 0  # extension 未導入なら no-op
        idx = gs.get_uint("last-config-index")
        configs = gs.get_value("configs")
        if idx >= configs.n_children():
            print(
                f"last-config-index ({idx}) out of range "
                f"({configs.n_children()} saved configs)",
                file=sys.stderr,
            )
            return 1
        name = configs.get_child_value(idx).get_child_value(0).get_string()
        SNAPSHOT_PATH.parent.mkdir(parents=True, exist_ok=True)
        SNAPSHOT_PATH.write_text(name)
        print(f"snapshotted active display config: {name!r}")
        return 0


    def cmd_restore():
        if not SNAPSHOT_PATH.exists():
            print("no snapshot file; nothing to restore", file=sys.stderr)
            return 0
        target_name = SNAPSHOT_PATH.read_text().strip()
        if not target_name:
            print("snapshot file empty; nothing to restore", file=sys.stderr)
            return 0

        gs = get_settings()
        if gs is None:
            return 0

        configs = gs.get_value("configs")
        target = None
        for i in range(configs.n_children()):
            entry = configs.get_child_value(i)
            if entry.get_child_value(0).get_string() == target_name:
                target = entry
                break
        if target is None:
            print(
                f"snapshotted config {target_name!r} no longer exists in dconf",
                file=sys.stderr,
            )
            return 1

        logical_monitors = target.get_child_value(2)
        properties = target.get_child_value(3)

        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        proxy = Gio.DBusProxy.new_sync(
            bus,
            Gio.DBusProxyFlags.NONE,
            None,
            "org.gnome.Mutter.DisplayConfig",
            "/org/gnome/Mutter/DisplayConfig",
            "org.gnome.Mutter.DisplayConfig",
            None,
        )
        state = proxy.call_sync(
            "GetCurrentState", None, Gio.DBusCallFlags.NONE, -1, None
        )
        serial = state.get_child_value(0).get_uint32()

        # method=1: temporary (no confirmation prompt; matches the extension's
        # own click-to-apply path)
        params = GLib.Variant.new_tuple(
            GLib.Variant.new_uint32(serial),
            GLib.Variant.new_uint32(1),
            logical_monitors,
            properties,
        )
        proxy.call_sync(
            "ApplyMonitorsConfig", params, Gio.DBusCallFlags.NONE, -1, None
        )
        print(f"restored display config: {target_name!r}")
        return 0


    def main():
        if len(sys.argv) != 2 or sys.argv[1] not in {"snapshot", "restore"}:
            print(f"usage: {sys.argv[0]} (snapshot|restore)", file=sys.stderr)
            return 2
        return cmd_snapshot() if sys.argv[1] == "snapshot" else cmd_restore()


    sys.exit(main())
  '';

  sleepTargets = [
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];
in
{
  options.programs.gnomeDisplayDefault = {
    enable = lib.mkEnableOption ''
      スリープ直前に有効だった display-configuration-switcher 設定を
      復帰時に自動で再適用する仕組み
    '';
  };

  config = lib.mkIf (settings.features.gnome && cfg.enable) {
    home.packages = [ helperScript ];

    systemd.user.services.gnome-display-snapshot = {
      Unit = {
        Description = "Snapshot active GNOME display config before sleep";
        Before = sleepTargets;
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${helperScript}/bin/gnome-display-default snapshot";
      };
      Install = {
        WantedBy = sleepTargets;
      };
    };

    systemd.user.services.gnome-display-restore = {
      Unit = {
        Description = "Restore snapshotted GNOME display config after resume";
        After = sleepTargets;
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${helperScript}/bin/gnome-display-default restore";
      };
      Install = {
        WantedBy = sleepTargets;
      };
    };
  };
}
