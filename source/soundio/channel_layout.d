/// Translated from C to D
module soundio.channel_layout;

@nogc nothrow:
extern(C): __gshared:


import soundio.soundio_private;
import soundio.util;
import core.stdc.stdio;
import core.stdc.string: strlen;

package:

private SoundIoChannelLayout[26] builtin_channel_layouts = [
    {
        "Mono",
        1,
        [
            SoundIoChannelId.FrontCenter,
        ],
    },
    {
        "Stereo",
        2,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
        ],
    },
    {
        "2.1",
        3,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.Lfe,
        ],
    },
    {
        "3.0",
        3,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
        ]
    },
    {
        "3.0 (back)",
        3,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.BackCenter,
        ]
    },
    {
        "3.1",
        4,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "4.0",
        4,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackCenter,
        ]
    },
    {
        "Quad",
        4,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
        ],
    },
    {
        "Quad (side)",
        4,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
        ]
    },
    {
        "4.1",
        5,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "5.0 (back)",
        5,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
        ]
    },
    {
        "5.0 (side)",
        5,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
        ]
    },
    {
        "5.1",
        6,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "5.1 (back)",
        6,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "6.0 (side)",
        6,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.BackCenter,
        ]
    },
    {
        "6.0 (front)",
        6,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.FrontLeftCenter,
            SoundIoChannelId.FrontRightCenter,
        ]
    },
    {
        "Hexagonal",
        6,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
            SoundIoChannelId.BackCenter,
        ]
    },
    {
        "6.1",
        7,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.BackCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "6.1 (back)",
        7,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
            SoundIoChannelId.BackCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "6.1 (front)",
        7,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.FrontLeftCenter,
            SoundIoChannelId.FrontRightCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "7.0",
        7,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
        ]
    },
    {
        "7.0 (front)",
        7,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.FrontLeftCenter,
            SoundIoChannelId.FrontRightCenter,
        ]
    },
    {
        "7.1",
        8,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "7.1 (wide)",
        8,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.FrontLeftCenter,
            SoundIoChannelId.FrontRightCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "7.1 (wide) (back)",
        8,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
            SoundIoChannelId.FrontLeftCenter,
            SoundIoChannelId.FrontRightCenter,
            SoundIoChannelId.Lfe,
        ]
    },
    {
        "Octagonal",
        8,
        [
            SoundIoChannelId.FrontLeft,
            SoundIoChannelId.FrontRight,
            SoundIoChannelId.FrontCenter,
            SoundIoChannelId.SideLeft,
            SoundIoChannelId.SideRight,
            SoundIoChannelId.BackLeft,
            SoundIoChannelId.BackRight,
            SoundIoChannelId.BackCenter,
        ]
    },
];

enum CHANNEL_NAME_ALIAS_COUNT = 3;
alias const(char)*[CHANNEL_NAME_ALIAS_COUNT] channel_names_t;
private channel_names_t* channel_names = [
    ["(Invalid Channel)", null, null],
    ["Front Left", "FL", "front-left"],
    ["Front Right", "FR", "front-right"],
    ["Front Center", "FC", "front-center"],
    ["LFE", "LFE", "lfe"],
    ["Back Left", "BL", "rear-left"],
    ["Back Right", "BR", "rear-right"],
    ["Front Left Center", "FLC", "front-left-of-center"],
    ["Front Right Center", "FRC", "front-right-of-center"],
    ["Back Center", "BC", "rear-center"],
    ["Side Left", "SL", "side-left"],
    ["Side Right", "SR", "side-right"],
    ["Top Center", "TC", "top-center"],
    ["Top Front Left", "TFL", "top-front-left"],
    ["Top Front Center", "TFC", "top-front-center"],
    ["Top Front Right", "TFR", "top-front-right"],
    ["Top Back Left", "TBL", "top-rear-left"],
    ["Top Back Center", "TBC", "top-rear-center"],
    ["Top Back Right", "TBR", "top-rear-right"],
    ["Back Left Center", null, null],
    ["Back Right Center", null, null],
    ["Front Left Wide", null, null],
    ["Front Right Wide", null, null],
    ["Front Left High", null, null],
    ["Front Center High", null, null],
    ["Front Right High", null, null],
    ["Top Front Left Center", null, null],
    ["Top Front Right Center", null, null],
    ["Top Side Left", null, null],
    ["Top Side Right", null, null],
    ["Left LFE", null, null],
    ["Right LFE", null, null],
    ["LFE 2", null, null],
    ["Bottom Center", null, null],
    ["Bottom Left Center", null, null],
    ["Bottom Right Center", null, null],
    ["Mid/Side Mid", null, null],
    ["Mid/Side Side", null, null],
    ["Ambisonic W", null, null],
    ["Ambisonic X", null, null],
    ["Ambisonic Y", null, null],
    ["Ambisonic Z", null, null],
    ["X-Y X", null, null],
    ["X-Y Y", null, null],
    ["Headphones Left", null, null],
    ["Headphones Right", null, null],
    ["Click Track", null, null],
    ["Foreign Language", null, null],
    ["Hearing Impaired", null, null],
    ["Narration", null, null],
    ["Haptic", null, null],
    ["Dialog Centric Mix", null, null],
    ["Aux", null, null],
    ["Aux 0", null, null],
    ["Aux 1", null, null],
    ["Aux 2", null, null],
    ["Aux 3", null, null],
    ["Aux 4", null, null],
    ["Aux 5", null, null],
    ["Aux 6", null, null],
    ["Aux 7", null, null],
    ["Aux 8", null, null],
    ["Aux 9", null, null],
    ["Aux 10", null, null],
    ["Aux 11", null, null],
    ["Aux 12", null, null],
    ["Aux 13", null, null],
    ["Aux 14", null, null],
    ["Aux 15", null, null],
];

const(char)* soundio_get_channel_name(SoundIoChannelId id) {
    if (id >= channel_names.length)
        return "(Invalid Channel)";
    else
        return channel_names[id][0];
}

bool soundio_channel_layout_equal(const(SoundIoChannelLayout)* a, const(SoundIoChannelLayout)* b) {
    if (a.channel_count != b.channel_count)
        return false;

    for (int i = 0; i < a.channel_count; i += 1) {
        if (a.channels[i] != b.channels[i])
            return false;
    }

    return true;
}

int soundio_channel_layout_builtin_count() {
    return builtin_channel_layouts.length;
}

const(SoundIoChannelLayout)* soundio_channel_layout_get_builtin(int index) {
    assert(index >= 0);
    assert(index <= builtin_channel_layouts.length);
    return &builtin_channel_layouts[index];
}

int soundio_channel_layout_find_channel(const(SoundIoChannelLayout)* layout, SoundIoChannelId channel) {
    for (int i = 0; i < layout.channel_count; i += 1) {
        if (layout.channels[i] == channel)
            return i;
    }
    return -1;
}

bool soundio_channel_layout_detect_builtin(SoundIoChannelLayout* layout) {
    for (int i = 0; i < builtin_channel_layouts.length; i += 1) {
        const(SoundIoChannelLayout)* builtin_layout = &builtin_channel_layouts[i];
        if (soundio_channel_layout_equal(builtin_layout, layout)) {
            layout.name = builtin_layout.name;
            return true;
        }
    }
    layout.name = null;
    return false;
}

const(SoundIoChannelLayout)* soundio_channel_layout_get_default(int channel_count) {
    switch (channel_count) {
        case 1: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId.Mono);
        case 2: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId.Stereo);
        case 3: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId._3Point0);
        case 4: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId._4Point0);
        case 5: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId._5Point0Back);
        case 6: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId._5Point1Back);
        case 7: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId._6Point1);
        case 8: return soundio_channel_layout_get_builtin(SoundIoChannelLayoutId._7Point1);
        default: break;
    }
    return null;
}

SoundIoChannelId soundio_parse_channel_id(const(char)* str, int str_len) {
    for (int id = 0; id < channel_names.length; id += 1) {
        for (int i = 0; i < CHANNEL_NAME_ALIAS_COUNT; i += 1) {
            const(char)* alias_ = channel_names[id][i];
            if (!alias_)
                break;
            int alias_len = cast(int) strlen(alias_);
            if (soundio_streql(alias_, alias_len, str, str_len))
                return cast(SoundIoChannelId)id;
        }
    }
    return SoundIoChannelId.Invalid;
}
