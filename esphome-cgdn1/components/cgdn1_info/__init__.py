"""Dashboard "Device info" texts and the factory-block readout (header-only, ours).

Loading this component (`cgdn1_info:` in the YAML) copies info.h and info_esp32.h into the build;
ESPHome's generated esphome.h includes them, so the cgdn1.yaml lambdas can use
`cgdn1_info::chip_now()` etc. The formatting and the readout's hiding rules (info.h) have no
ESPHome dependencies and are unit-tested on the host (tests/test_info.py).
"""
import esphome.config_validation as cv

CODEOWNERS = []

CONFIG_SCHEMA = cv.Schema({})


async def to_code(config):
    pass
