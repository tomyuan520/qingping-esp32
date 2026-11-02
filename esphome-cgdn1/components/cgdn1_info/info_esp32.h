#pragma once
// ESP-IDF side of the "Device info" texts (info.h does the formatting). Everything here only
// reads: chip eFuses, the flash chip's JEDEC id, the OTA partitions' app descriptions and the
// factory block.

#ifdef ESP_PLATFORM

#include "info.h"

#include <esp_chip_info.h>
#include <esp_efuse.h>
#include <esp_flash.h>
#include <esp_ota_ops.h>
#include <esp_rom_sys.h>

#include "esphome/core/helpers.h"
#include "esphome/core/log.h"

namespace cgdn1_info {

inline std::string chip_now() {
  esp_chip_info_t info;
  esp_chip_info(&info);
  return chip_text(esp_efuse_get_pkg_ver(), info.revision, info.cores, esp_rom_get_cpu_ticks_per_us());
}

inline std::string flash_now() {
  uint32_t id = 0;
  if (esp_flash_read_id(esp_flash_default_chip, &id) != ESP_OK)
    id = 0;
  return flash_text(id);
}

inline std::string slots_now() {
  const esp_partition_t *running = esp_ota_get_running_partition();
  const esp_partition_t *other = esp_ota_get_next_update_partition(nullptr);
  esp_app_desc_t desc{};
  const bool ok = other != nullptr && esp_ota_get_partition_description(other, &desc) == ESP_OK;
  return slots_text(running != nullptr ? running->label : "?", other != nullptr ? other->label : "?", ok,
                    desc.project_name, desc.version);
}

// Stock's factory-info sector (docs/hardware.md: inside the `test` partition, never written).
static constexpr uint32_t FACTORY_ADDR = 0x3d2000, FACTORY_SIZE = 0x1000;

// Writes the factory_summary() of the sector to the log (tag "factory"); nothing is published.
inline void log_factory_block() {
  std::vector<uint8_t> b(FACTORY_SIZE);
  if (esp_flash_read(esp_flash_default_chip, b.data(), FACTORY_ADDR, FACTORY_SIZE) != ESP_OK) {
    ESP_LOGW("factory", "reading 0x%06" PRIx32 " failed", FACTORY_ADDR);
    return;
  }
  const std::string mac = esphome::get_mac_address();  // 12 hex chars, our own (public) MAC
  for (const auto &line : factory_summary(b.data(), b.size(), mac.c_str()))
    ESP_LOGI("factory", "%s", line.c_str());
}

}  // namespace cgdn1_info

#endif  // ESP_PLATFORM
