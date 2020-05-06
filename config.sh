#!/bin/bash

CONFIG="$HOME/.config/oem-scripts/config.ini"

has_config ()
{
    if [ -f "$CONFIG" ]; then
        true
    else
        false
    fi
}

read_config ()
{
    has_config && grep ^"$1 = " "$CONFIG" | awk '{print $3}'
}

write_config ()
{
    if [ ! -f "$CONFIG" ]; then
        mkdir -p "$HOME/.config/oem-scripts"
        touch "$CONFIG"
    fi
    if [ -z "$(read_config "$1")" ]; then
        echo "$1 = $2" >> "$CONFIG"
    else
        sed -i "s/$1 = .*/$1 = $2/" "$CONFIG"
    fi
}
