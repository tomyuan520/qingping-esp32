#pragma once
// Texts for the dashboard "Device info" group (ours, not in stock) and the factory-block readout.
// No ESPHome or ESP-IDF dependencies, so it is unit-tested on the host (tests/test_info.py); the
// ESP-IDF calls that feed it live in info_esp32.h.

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace cgdn1_info {

static constexpr const char *SEP = " \xc2\xb7 ";  // " · "

// Printable ASCII only (anything else -> '?'), at most `max` chars.
inline std::string clean(const char *s, size_t max = 32) {
  std::string out;
  for (size_t i = 0; s != nullptr && s[i] != '\0' && i < max; i++)
    out += (s[i] >= 0x20 && s[i] <= 0x7e) ? s[i] : '?';
  return out;
}

// ESP32 package eFuse (EFUSE_RD_CHIP_VER_PKG_*).
inline const char *package_name(uint32_t pkg) {
  switch (pkg) {
    case 0: return "ESP32-D0WDQ6";
    case 1: return "ESP32-D0WDQ5";
    case 2: return "ESP32-D2WDQ5";
    case 4: return "ESP32-U4WDH";
    case 5: return "ESP32-PICO-D4";
    case 6: return "ESP32-PICO-V3-02";
    case 7: return "ESP32-D0WDR2-V3";
    default: return nullptr;
  }
}

// `revision` as esp_chip_info() gives it: major * 100 + minor.
inline std::string chip_text(uint32_t pkg, unsigned revision, unsigned cores, unsigned mhz) {
  char name[32];
  const char *n = package_name(pkg);
  if (n == nullptr)
    snprintf(name, sizeof(name), "ESP32 (package %u)", (unsigned) pkg);
  char buf[96];
  snprintf(buf, sizeof(buf), "%s, rev v%u.%u, %u core%s, %u MHz", n != nullptr ? n : name, revision / 100,
           revision % 100, cores, cores == 1 ? "" : "s", mhz);
  return buf;
}

// JEDEC manufacturer byte -> name (the usual ESP32 module flash vendors).
inline const char *flash_vendor(uint8_t mfr) {
  switch (mfr) {
    case 0xC8: return "GigaDevice";
    case 0xEF: return "Winbond";
    case 0x20: return "XMC";
    case 0x68: return "Boya";
    case 0xC2: return "Macronix";
    case 0x1C: return "EON";
    case 0x0B: return "XTX";
    case 0x5E: return "Zbit";
    case 0x85: return "Puya";
    case 0x9D: return "ISSI";
    case 0xA1: return "Fudan";
    default: return nullptr;
  }
}

// 24-bit JEDEC id (manufacturer, type, capacity = log2 of the size in bytes).
inline std::string flash_text(uint32_t jedec) {
  if (jedec == 0 || jedec == 0xFFFFFF)
    return "unknown (no flash ID)";
  const uint8_t mfr = jedec >> 16, cap = jedec & 0xFF;
  char size[24], vendor[24], buf[80];
  if (cap >= 0x14 && cap <= 0x1F)  // 1 MB .. 2 GB
    snprintf(size, sizeof(size), "%u MB", 1u << (cap - 20));
  else
    snprintf(size, sizeof(size), "unknown size");
  const char *v = flash_vendor(mfr);
  if (v == nullptr)
    snprintf(vendor, sizeof(vendor), "vendor 0x%02X", mfr);
  snprintf(buf, sizeof(buf), "%s, %s (%06X)", size, v != nullptr ? v : vendor, (unsigned) jedec);
  return buf;
}

// Running OTA slot, and what the other slot holds (its app description), e.g. stock 4.8.5.
inline std::string slots_text(const char *running, const char *other, bool other_ok, const char *project,
                              const char *version) {
  std::string s = "running " + clean(running, 16) + SEP + "other " + clean(other, 16) + ": ";
  if (!other_ok)
    return s + "no valid app";
  s += clean(project);
  const std::string v = clean(version);
  return v.empty() ? s : s + " " + v;
}

inline std::string firmware_text(const char *esphome_version, const char *rev, const char *built) {
  std::string s = std::string("ESPHome ") + clean(esphome_version);
  const std::string r = clean(rev);
  if (!r.empty())
    s += SEP + r;
  return s + SEP + "built " + clean(built, 40);
}

// RSSI -> 0..100 % (the common 2 * (dBm + 100) mapping); NaN stays NaN.
inline float signal_pct(float dbm) {
  if (std::isnan(dbm))
    return NAN;
  const float p = 2.0f * (dbm + 100.0f);
  return p < 0.0f ? 0.0f : p > 100.0f ? 100.0f : p;
}

// ---- factory block (flash 0x3d2000, written at the factory, never by stock or us) -------------
// The readout says what is where without printing anything that could be a secret (the stock
// HomeKit stack keeps a pairing setup code in factory data on such devices). Content is shown only
// for version-like text (at most 5 chars, digits and dots: "0001", "1.0.2"), 1-2 byte binary
// fields, and the device's own (public) MAC as "<device MAC>". Every other text run is reported
// as its length and character classes, every other binary run as its length. 0xFF / 0x00 = blank.

inline bool blank(uint8_t c) { return c == 0xFF || c == 0x00; }
inline bool printable(uint8_t c) { return c >= 0x20 && c <= 0x7e; }

inline size_t text_run(const uint8_t *b, size_t len, size_t i) {
  size_t j = i;
  while (j < len && printable(b[j]))
    j++;
  return j - i;
}

static constexpr size_t MIN_TEXT = 3, MAX_VERSION_TEXT = 5, MAX_SHOWN_BYTES = 2;

inline bool version_like(const uint8_t *s, size_t n) {
  if (n > MAX_VERSION_TEXT)
    return false;
  for (size_t i = 0; i < n; i++)
    if (!((s[i] >= '0' && s[i] <= '9') || s[i] == '.'))
      return false;
  return true;
}

inline bool same_hex(const uint8_t *s, size_t n, const char *mac) {
  if (mac == nullptr || strlen(mac) != n || n == 0)
    return false;
  for (size_t i = 0; i < n; i++) {
    const int a = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
    const int b = (mac[i] >= 'a' && mac[i] <= 'z') ? mac[i] - 32 : mac[i];
    if (a != b)
      return false;
  }
  return true;
}

// "upper, lower, digits" then each punctuation char used, in ASCII order: "' ', '-', '.'".
inline std::string char_classes(const uint8_t *s, size_t n) {
  bool upper = false, lower = false, digit = false, punct[128] = {};
  for (size_t i = 0; i < n; i++) {
    const uint8_t c = s[i];
    if (c >= 'A' && c <= 'Z')
      upper = true;
    else if (c >= 'a' && c <= 'z')
      lower = true;
    else if (c >= '0' && c <= '9')
      digit = true;
    else if (c < 128)
      punct[c] = true;
  }
  std::string out;
  auto add = [&](const std::string &x) { out += (out.empty() ? "" : ", ") + x; };
  if (upper)
    add("upper");
  if (lower)
    add("lower");
  if (digit)
    add("digits");
  for (int c = 0x20; c < 0x7f; c++)
    if (punct[c])
      add(std::string("'") + (char) c + "'");
  return out;
}

// `mac`: the device's own MAC as 12 hex chars (shown as "<device MAC>" where the block holds it).
inline std::vector<std::string> factory_summary(const uint8_t *b, size_t len, const char *mac,
                                                size_t max_lines = 48) {
  std::vector<std::string> out;
  char buf[160];
  if (len > 0 && b[0] == 'Z')
    out.emplace_back("factory block: 'Z' marker present");
  else {
    snprintf(buf, sizeof(buf), "factory block: no 'Z' marker (first byte 0x%02x)", len > 0 ? b[0] : 0);
    out.emplace_back(buf);
  }
  size_t entries = 0;
  auto add = [&](const std::string &s) {
    if (entries++ < max_lines)
      out.push_back(s);
  };
  size_t i = 0;
  while (i < len) {
    if (blank(b[i])) {
      i++;
      continue;
    }
    const size_t t = text_run(b, len, i);
    if (t >= MIN_TEXT) {
      if (version_like(b + i, t))
        snprintf(buf, sizeof(buf), "+0x%03zx: \"%.*s\"", i, (int) t, (const char *) b + i);
      else if (same_hex(b + i, t, mac))
        snprintf(buf, sizeof(buf), "+0x%03zx: <device MAC>", i);
      else
        snprintf(buf, sizeof(buf), "+0x%03zx: <%zu chars: %s>", i, t, char_classes(b + i, t).c_str());
      add(buf);
      i += t;
      continue;
    }
    size_t j = i;
    while (j < len && !blank(b[j]) && text_run(b, len, j) < MIN_TEXT)
      j++;
    const size_t n = j - i;
    if (n <= MAX_SHOWN_BYTES) {
      int p = snprintf(buf, sizeof(buf), "+0x%03zx:", i);
      for (size_t k = i; k < j; k++)
        p += snprintf(buf + p, sizeof(buf) - p, " %02x", b[k]);
    } else {
      snprintf(buf, sizeof(buf), "+0x%03zx: <%zu bytes binary>", i, n);
    }
    add(buf);
    i = j;
  }
  if (entries == 0)
    out.emplace_back("(all blank)");
  else if (entries > max_lines) {
    snprintf(buf, sizeof(buf), "... %zu more entries", entries - max_lines);
    out.emplace_back(buf);
  }
  return out;
}

}  // namespace cgdn1_info
