#!/usr/bin/env bash
set -eou  
mkdir -p ~/.config/systemd/user/
sed -i "s#CODER_TOKEN_VALUE#${CODER_AGENT_TOKEN}#g" coder.service
sed -i "s#CODER_URL_VALUE#${CODER_AGENT_URL}#g" coder.service
cp ./coder.service ~/.config/systemd/user
systemctl --user daemon-reload
systemctl --user restart coder.service
