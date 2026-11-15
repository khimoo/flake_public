requires = ["tailscale"]

def writes(connect_ssh):
    return [write(connect_ssh, True)]
