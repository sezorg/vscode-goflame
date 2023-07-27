#!/bin/sh

. "./../../CameraConfiguration.sh"

# Формирование параметров JSON запроса.
JSON=$(
	cat <<DELIMITER
{
	"ProfileToken": "main",
	"Position": {
		"Zoom": {
			"x": 0.41,
			"space": "http://www.onvif.org/ver10/tptz/ZoomSpaces/PositionGenericSpace"
		}
	}
}
DELIMITER
)
json_test ptz/RelativeMove
