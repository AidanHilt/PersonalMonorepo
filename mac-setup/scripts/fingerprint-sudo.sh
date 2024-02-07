#!/bin/zsh

PAM_CONFIGURATION_TEMPLATE=/etc/pam.d/sudo_local.template
PAM_CONFIGURATION_LOCATION=/etc/pam.d/sudo_local

cp "$PAM_CONFIGURATION_TEMPLATE" "$PAM_CONFIGURATION_LOCATION"

sed -i "" 's/^#auth/auth/' "$PAM_CONFIGURATION_LOCATION"