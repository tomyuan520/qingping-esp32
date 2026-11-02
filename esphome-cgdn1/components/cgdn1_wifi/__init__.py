"""One extra WiFi network, set over the encrypted API (header-only, ours).

Loading this component (`cgdn1_wifi:` in the YAML) copies extra_wifi.h and extra_wifi_esphome.h into
the build; ESPHome's generated esphome.h includes them, so the cgdn1.yaml lambdas can use
`cgdn1_wifi::store()` etc. The checks and the stored record (extra_wifi.h) have no ESPHome
dependencies and are unit-tested on the host (tests/test_wifi_extra.py).
"""
import esphome.config_validation as cv

CODEOWNERS = []

CONFIG_SCHEMA = cv.Schema({})


async def to_code(config):
    pass
