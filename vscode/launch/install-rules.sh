#!/bin/bash

sudo sed -e "s/<USER>/$USER/g" -e 'w /etc/polkit-1/rules.d/99-manage-nginx.rules' ./99-manage-nginx.rules
