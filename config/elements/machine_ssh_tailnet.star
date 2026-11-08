when = ["machine_ssh", "tailscale"]

def writes(machine_ssh):
    return [write(machine_ssh, True)]
