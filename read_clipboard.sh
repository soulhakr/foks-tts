#!/bin/zsh
# Read the image on the clipboard aloud, highlighting the current word.
# Workflow: capture an area with Shottr (it copies to the clipboard), then run this
# (bind it to a hotkey via a Shortcut or Automator Quick Action).
export HF_HUB_OFFLINE=1
exec /usr/bin/swift "${0:A:h}/read_screen.swift" "$@"
