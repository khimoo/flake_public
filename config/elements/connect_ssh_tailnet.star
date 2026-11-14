when = ["connect_ssh", "tailscale"]

def writes(connect_ssh):
    return [write(connect_ssh, True)]
