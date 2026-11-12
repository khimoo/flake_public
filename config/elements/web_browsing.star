requires = ["firefox", "brave", "google_chrome"]

def public(zen_browser):
    return {"command": zen_browser.command, "desktop": zen_browser.desktop}

def user_config(zen_browser, incoming):
    if len(incoming) > 1:
        fail("web_browsing: only one HTTP/HTTPS handler may be selected")
    http_desktop = incoming[0].value if incoming else zen_browser.desktop
    defaults = {
        mime: zen_browser.desktop
        for mime in ["text/html", "text/xml", "application/xhtml+xml", "x-scheme-handler/about"]
    }
    defaults.update({"x-scheme-handler/" + scheme: http_desktop for scheme in ["http", "https"]})
    return {"home": {
        "xdg.mimeApps.enable": True,
        "xdg.mimeApps.defaultApplications": defaults,
    }}
