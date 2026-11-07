def config(host):
    return {"home": {"home.packages": [repoPkgWith("packages/mimikopi-env", {
        "dataDir": host.mimikopi_data_dir,
        "hsaOverrideGfxVersion": getattr(host, "mimikopi_hsa_override", None),
    })]}}
