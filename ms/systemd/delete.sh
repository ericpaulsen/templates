#!/usr/bin/env bash
set -eou  
systemctl --user stop coder.service
rm -f ~/.config/systemd/user/coder.service
