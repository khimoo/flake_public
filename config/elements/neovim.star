# lua/plugins/lang/typst/output_path.lua が tinymistOutput の findmnt と fsType を読む。
def config(incoming):
    outputs = [w.value["tinymist_output"] for w in incoming if "tinymist_output" in w.value]
    if not outputs:
        return {}
    if len(outputs) > 1:
        fail("neovim: more than one element sets tinymist_output")
    return {"home": {
        "local.neovim.features.lsp.data.tinymistOutput": {
            "findmnt": outputs[0]["findmnt"],
            "fsType": outputs[0]["fs_type"],
        },
    }}
