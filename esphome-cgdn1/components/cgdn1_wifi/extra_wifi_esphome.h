#pragma once
// ESPHome side of the extra WiFi network (extra_wifi.h has the record and the checks): kept in
// ESPHome's preferences under its own key, so it survives reflashes (ESPHome's own saved network
// is keyed by the config hash and dropped by every new build). The password is never logged.

#ifdef ESP_PLATFORM

#include "extra_wifi.h"

#include <algorithm>

#include "esphome/components/wifi/wifi_component.h"
#include "esphome/core/helpers.h"
#include "esphome/core/log.h"
#include "esphome/core/preferences.h"

namespace cgdn1_wifi {

static const char *const TAG = "extra_wifi";

inline esphome::ESPPreferenceObject &pref() {
  static esphome::ESPPreferenceObject p =
      esphome::global_preferences->make_preference<ExtraWifi>(esphome::fnv1_hash("cgdn1_extra_wifi"), true);
  return p;
}

inline ExtraWifi saved() {
  ExtraWifi w{};
  if (!pref().load(&w) || !has(w))
    w = ExtraWifi{};
  return w;
}

inline void add_to_wifi(const ExtraWifi &w) {
  esphome::wifi::WiFiAP ap;
  ap.set_ssid(w.ssid);
  ap.set_password(w.password);
  esphome::wifi::global_wifi_component->add_sta(ap);
}

// on_boot, before WiFi starts: put the saved network next to the built-in ones.
inline void apply_saved() {
  const ExtraWifi w = saved();
  if (!has(w))
    return;
  add_to_wifi(w);
  ESP_LOGI(TAG, "Extra network: %s", w.ssid);
}

// API action set_wifi: check, save (flushed now), and add it to the list WiFi tries right away.
inline bool store(const std::string &ssid, const std::string &password) {
  ExtraWifi w{};
  const Check c = check(ssid.data(), ssid.size(), password.data(), password.size());
  if (c != Check::OK || !make(w, ssid.data(), ssid.size(), password.data(), password.size())) {
    ESP_LOGW(TAG, "set_wifi refused: %s", check_text(c));
    return false;
  }
  if (!pref().save(&w) || !esphome::global_preferences->sync()) {
    ESP_LOGW(TAG, "set_wifi: saving failed");
    return false;
  }
  add_to_wifi(w);
  ESP_LOGI(TAG, "Extra network saved: %s (tried whenever the built-in networks are out of reach)", w.ssid);
  return true;
}

// API action forget_wifi: clears the saved network; it leaves WiFi's list at the next restart.
inline void forget() {
  ExtraWifi w{};
  pref().save(&w);
  esphome::global_preferences->sync();
  ESP_LOGI(TAG, "Extra network forgotten (gone from the WiFi list after a restart)");
}

inline std::string saved_label() { return label(saved()); }

// ---- dashboard "Add WiFi" section -----------------------------------------------------------
// The typed name and password wait here (RAM only) until Connect; the password text entity is not
// optimistic, so its value is never published as a state. Wiped after every Connect.

struct Pending {
  std::string ssid, password;
  std::string result;
  uint32_t result_ms{0};
};

inline Pending &pending() {
  static Pending p;
  return p;
}

inline void wipe(std::string &s) {
  std::fill(s.begin(), s.end(), '\0');
  s.clear();
}

inline bool hotspot_up() { return esphome::wifi::global_wifi_component->is_ap_active(); }

inline void set_result(const std::string &text) {
  pending().result = text;
  pending().result_ms = esphome::millis();
}

inline void set_pending_ssid(const std::string &ssid) { pending().ssid = ssid; }

inline void set_pending_password(const std::string &password) {
  wipe(pending().password);
  if (!hotspot_up()) {
    set_result(PAGE_NOT_ON_HOTSPOT);
    ESP_LOGW(TAG, "Add WiFi: entry refused, the fallback hotspot is not up");
    return;
  }
  pending().password = password;
  set_result("Password entered; press Connect");
}

inline std::string connect_from_page() {
  Pending &p = pending();
  const PageResult r = page_decide(hotspot_up(), p.ssid.data(), p.ssid.size(), p.password.data(), p.password.size());
  const Check c = check(p.ssid.data(), p.ssid.size(), p.password.data(), p.password.size());
  std::string text = page_text(r, p.ssid.c_str(), c);
  if (r == PageResult::SAVED && !store(p.ssid, p.password))
    text = "Not saved: saving failed (see the log)";
  wipe(p.password);
  if (r == PageResult::SAVED)
    p.ssid.clear();
  set_result(text);
  return text;
}

// Status line: the last result for 2 minutes, otherwise whether the page can be used right now.
inline std::string page_status() {
  const Pending &p = pending();
  if (!p.result.empty() && esphome::millis() - p.result_ms < 120000)
    return p.result;
  return hotspot_up() ? PAGE_READY : PAGE_NOT_ON_HOTSPOT;
}

}  // namespace cgdn1_wifi

#endif  // ESP_PLATFORM
