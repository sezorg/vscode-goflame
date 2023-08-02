#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"VideoSourceToken":"src",
	"ImagingSettings": {
		"WhiteBalance": {
			"Mode": "AUTO"
		},
		"Focus": {
			"AutoFocusMode": "MANUAL",
			"DefaultSpeed": 100.0,
			"NearLimit": 1.0,
			"FarLimit": 2.0
		}
	}
}
DELIMITER
)
json_test imaging/SetImagingSettings
