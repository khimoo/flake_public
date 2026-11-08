requires = ["pipewire"]

def config(host):
    return {"nixos": {
        ("services", "pipewire", "extraConfig", "pipewire", "93-echo-cancel"): {
            "context.modules": [{
                "name": "libpipewire-module-echo-cancel",
                "args": {
                    "library.name": "aec/libspa-aec-webrtc",
                    "monitor.mode": True,
                    "audio.rate": 48000,
                    "aec.args": {
                        "webrtc.gain_control": False,
                        "webrtc.noise_suppression": False,
                    },
                    "capture.props": {
                        "node.name": "echo-cancel-capture",
                        "target.object": host.echo_cancel_source,
                        "node.dont-fallback": True,
                        "node.linger": True,
                    },
                    "source.props": {
                        "node.name": "echo-cancel-source",
                        "node.description": "Echo-Cancel Microphone",
                        "priority.session": 0,
                    },
                    "sink.props": {"node.name": "echo-cancel-reference"},
                },
            }],
        },
    }}
