#include "vmlinux.h"
#include "hid_bpf.h"
#include "hid_bpf_helpers.h"
#include <bpf/bpf_tracing.h>
#include "descriptor.h"

HID_BPF_CONFIG(
    HID_DEVICE(BUS_BLUETOOTH, HID_GROUP_GENERIC, 0x04fe, 0x0202)
);

SEC(HID_BPF_RDESC_FIXUP)
int BPF_PROG(hhkb_audio_fixup, struct hid_bpf_ctx *hctx)
{
    __u8 *data = hid_bpf_get_data(hctx, 0, 4096);
    if (!data)
        return 0;
    return hhkb_audio_patch(data, hctx->size);
}

HID_BPF_OPS(hhkb_bt_audio) = {
    .hid_rdesc_fixup = (void *)hhkb_audio_fixup,
};

SEC("syscall")
int probe(struct hid_bpf_probe_args *args)
{
    args->retval = args->rdesc_size == 315 ? 0 : -EINVAL;
    return 0;
}

char _license[] SEC("license") = "GPL";
