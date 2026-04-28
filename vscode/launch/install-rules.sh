#!/bin/bash
# Copyright 2024 RnD Center "ELVEES", JSC

sudo sed -e "s/<USER>/$USER/g" -e \
	'w /etc/polkit-1/rules.d/99-manage-nginx.rules' \
	./99-manage-nginx.rules
