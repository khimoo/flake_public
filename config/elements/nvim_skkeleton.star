# denops が deno で動く。
def writes(neovim):
    return [write(neovim, {
        "feature": "skkeleton",
        "packages": [pkg("deno")],
        "data": {"skkeleton": {"dictionary": concat(pkg("skk-jisyo-dict"))}},
    })]
