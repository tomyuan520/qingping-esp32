#pragma once
// One extra WiFi network next to the ones built into the firmware (ours, not in stock). Set from the
// dashboard's "Add WiFi" section on the fallback hotspot, or with the API action set_wifi
// (tools/cgdn1_set_wifi.py), e.g. when the monitor is somewhere new. Unlike ESPHome's own saved network (wifi.configure, captive portal) it is added to
// the built-in list instead of replacing it, and survives reflashes. No ESPHome or ESP-IDF
// dependencies, so it is unit-tested on the host (tests/test_wifi_extra.py).

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

namespace cgdn1_wifi {

static constexpr size_t SSID_MAX = 32, PASSWORD_MIN = 8, PASSWORD_MAX = 63, PSK_HEX = 64;
static constexpr uint32_t MAGIC = 0x57694669;  // "WiFi"

// Stored as raw bytes in ESPHome's preferences: trivially copyable, all zero = no network.
struct ExtraWifi {
  uint32_t magic;
  char ssid[SSID_MAX + 1];
  char password[PSK_HEX + 1];
};

enum class Check : uint8_t { OK, BAD_SSID_LENGTH, BAD_SSID_CHARS, BAD_PASSWORD_LENGTH, BAD_PASSWORD_CHARS };

inline const char *check_text(Check c) {
  switch (c) {
    case Check::OK: return "ok";
    case Check::BAD_SSID_LENGTH: return "network name must be 1-32 bytes";
    case Check::BAD_SSID_CHARS: return "network name has control characters";
    case Check::BAD_PASSWORD_LENGTH:
      return "password must be empty (open network), 8-63 characters or 64 hex digits";
    case Check::BAD_PASSWORD_CHARS: return "password must be printable ASCII";
  }
  return "?";
}

inline bool is_hex(char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'); }

// SSID: 1-32 bytes (UTF-8 allowed), no control characters. Password: empty (open network), 8-63
// printable ASCII characters (WPA passphrase) or 64 hex digits (raw PSK).
inline Check check(const char *ssid, size_t ssid_len, const char *pw, size_t pw_len) {
  if (ssid_len < 1 || ssid_len > SSID_MAX)
    return Check::BAD_SSID_LENGTH;
  for (size_t i = 0; i < ssid_len; i++)
    if ((uint8_t) ssid[i] < 0x20 || ssid[i] == 0x7f)
      return Check::BAD_SSID_CHARS;
  for (size_t i = 0; i < pw_len; i++)
    if ((uint8_t) pw[i] < 0x20 || (uint8_t) pw[i] > 0x7e)
      return Check::BAD_PASSWORD_CHARS;
  if (pw_len == 0 || (pw_len >= PASSWORD_MIN && pw_len <= PASSWORD_MAX))
    return Check::OK;
  if (pw_len == PSK_HEX) {
    for (size_t i = 0; i < pw_len; i++)
      if (!is_hex(pw[i]))
        return Check::BAD_PASSWORD_LENGTH;
    return Check::OK;
  }
  return Check::BAD_PASSWORD_LENGTH;
}

inline bool has(const ExtraWifi &w) { return w.magic == MAGIC && w.ssid[0] != '\0'; }

// Fills `w` when check() passes; otherwise leaves it empty and returns false.
inline bool make(ExtraWifi &w, const char *ssid, size_t ssid_len, const char *pw, size_t pw_len) {
  w = ExtraWifi{};
  if (check(ssid, ssid_len, pw, pw_len) != Check::OK)
    return false;
  w.magic = MAGIC;
  memcpy(w.ssid, ssid, ssid_len);
  memcpy(w.password, pw, pw_len);
  return true;
}

// For the dashboard: the network name only, never the password.
inline std::string label(const ExtraWifi &w) {
  if (!has(w))
    return "none";
  std::string s(w.ssid);
  return w.password[0] == '\0' ? s + " (open)" : s;
}

// ---- dashboard "Add WiFi" section (used on the fallback hotspot) ------------------------------
// The dashboard is plain HTTP: over the fallback hotspot the link is encrypted by its password, on
// a shared network it is not, so the page only takes a password while the hotspot is up.

enum class PageResult : uint8_t { SAVED, NOT_ON_HOTSPOT, NO_NAME, INVALID };

inline PageResult page_decide(bool ap_active, const char *ssid, size_t ssid_len, const char *pw, size_t pw_len) {
  if (!ap_active)
    return PageResult::NOT_ON_HOTSPOT;
  if (ssid_len == 0)
    return PageResult::NO_NAME;
  return check(ssid, ssid_len, pw, pw_len) == Check::OK ? PageResult::SAVED : PageResult::INVALID;
}

static constexpr const char *PAGE_NOT_ON_HOTSPOT =
    "Only on the fallback hotspot (http://192.168.4.1); on a network use tools/cgdn1_set_wifi.py";
static constexpr const char *PAGE_READY = "Enter a WiFi name and password, then press Connect";

inline std::string page_text(PageResult r, const char *ssid, Check c) {
  switch (r) {
    case PageResult::SAVED:
      return std::string("Saved '") + ssid + "': joining it when in reach (the hotspot closes once it's connected)";
    case PageResult::NOT_ON_HOTSPOT: return PAGE_NOT_ON_HOTSPOT;
    case PageResult::NO_NAME: return "Enter a WiFi name first";
    case PageResult::INVALID: return std::string("Not saved: ") + check_text(c);
  }
  return "?";
}

}  // namespace cgdn1_wifi
