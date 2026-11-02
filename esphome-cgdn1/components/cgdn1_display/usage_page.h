#pragma once
// State, validation, age and layout of the Claude / Codex usage pages (ours; stock has none).
// Pure: no ESPHome includes, so the host tests (tests/test_usage_page.py) compile it with plain g++.
// The numbers arrive from the owner's Mac through the API action set_usage (cgdn1.yaml); the
// display lambda draws the pages with ESPHome fonts from the values and helpers here.
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>

#include "display_math.h"

namespace esphome::cgdn1_display {

/// No update for longer than this: the numbers are drawn hollow (stale).
static constexpr uint32_t USAGE_STALE_S = 3600;
static constexpr size_t USAGE_ACCOUNT_MAX = 12;

enum class UsageLook : uint8_t { NONE, FRESH, STALE };

/// One service's last numbers. Value-initialised = no data yet (a boot shows "—").
struct UsageState {
  bool has;
  float five_hour;
  float seven_day;
  char account[USAGE_ACCOUNT_MAX + 1];
  uint32_t age_s;  // age of the numbers when they arrived
  uint32_t rx_ms;  // millis() when they arrived
};

inline bool usage_pct_ok(float pct) { return std::isfinite(pct) && pct >= 0.0f && pct <= 100.0f; }

/// Store an update; refuses (and keeps the old numbers) on a bad percentage or a negative age.
/// The account keeps at most USAGE_ACCOUNT_MAX bytes, anything outside printable ASCII becomes '?'.
inline bool usage_set(UsageState &s, const char *account, size_t account_len, float five_hour, float seven_day,
                      int32_t age_s, uint32_t now_ms) {
  if (!usage_pct_ok(five_hour) || !usage_pct_ok(seven_day) || age_s < 0)
    return false;
  size_t n = account_len < USAGE_ACCOUNT_MAX ? account_len : USAGE_ACCOUNT_MAX;
  for (size_t i = 0; i < n; i++) {
    const unsigned char c = (unsigned char) account[i];
    s.account[i] = c >= 0x20 && c <= 0x7E ? (char) c : '?';
  }
  s.account[n] = '\0';
  s.has = true;
  s.five_hour = five_hour;
  s.seven_day = seven_day;
  s.age_s = (uint32_t) age_s;
  s.rx_ms = now_ms;
  return true;
}

/// Current age: the age on arrival plus the time since (unsigned difference survives the millis() wrap).
inline uint32_t usage_age_s(const UsageState &s, uint32_t now_ms) { return s.age_s + (uint32_t) (now_ms - s.rx_ms) / 1000; }

inline UsageLook usage_look(const UsageState &s, uint32_t now_ms) {
  if (!s.has)
    return UsageLook::NONE;
  return usage_age_s(s, now_ms) > USAGE_STALE_S ? UsageLook::STALE : UsageLook::FRESH;
}

/// Top-right corner: "—" without data; "now" / "2m ago" / "3h ago" / "2d ago"; with an account
/// "daybreak · 9m" (an empty account falls back to the bare age).
inline void usage_corner_text(const UsageState &s, uint32_t now_ms, bool with_account, char *out, size_t n) {
  if (!s.has) {
    std::snprintf(out, n, "—");
    return;
  }
  const uint32_t a = usage_age_s(s, now_ms);
  char age[16];
  if (a < 60)
    std::snprintf(age, sizeof(age), "now");
  else if (a < 3600)
    std::snprintf(age, sizeof(age), "%um", (unsigned) (a / 60));
  else if (a < 86400)
    std::snprintf(age, sizeof(age), "%uh", (unsigned) (a / 3600));
  else
    std::snprintf(age, sizeof(age), "%ud", (unsigned) (a / 86400));
  const bool recent = a < 60;
  if (with_account && s.account[0] != '\0')
    std::snprintf(out, n, "%s · %s", s.account, age);
  else if (with_account || recent)
    std::snprintf(out, n, "%s", age);
  else
    std::snprintf(out, n, "%s ago", age);
}

inline float usage_clamp(float pct) { return pct < 0.0f ? 0.0f : (pct > 100.0f ? 100.0f : pct); }
inline int usage_pct(float pct) { return (int) lroundf(usage_clamp(pct)); }
inline int usage_bar_fill(float pct, int inner_w) { return (int) lroundf(usage_clamp(pct) * inner_w / 100.0f); }

// Layout on the 160 x 128 canvas, relative to the page origin. Everything stays below the page
// dots (y >= BOUNCE_TOP_MARGIN = 17) so the 3 s indicator after a slide never overlaps it.
static constexpr int USAGE_TITLE_Y = 18;          // title (left) and corner text (right), top
static constexpr int USAGE_ROW_Y[2] = {34, 76};   // top of the big digits, rows "5h" and "7d"
static constexpr int USAGE_LABEL_X = 8;
static constexpr int USAGE_DIGITS_X = 40;
static constexpr int USAGE_BAR_X = 8;
static constexpr int USAGE_BAR_W = 144;
static constexpr int USAGE_BAR_H = 5;
static constexpr int USAGE_BAR_DY = 31;           // bar top below the row's digit top
static constexpr int USAGE_RIGHT_X = USAGE_BAR_X + USAGE_BAR_W;  // right edge of corner text and bars

/// Everything a usage page draws (for bounce_range): title row down to the second bar.
inline Rect usage_ink() {
  return {USAGE_BAR_X, USAGE_TITLE_Y, USAGE_RIGHT_X, USAGE_ROW_Y[1] + USAGE_BAR_DY + USAGE_BAR_H};
}

}  // namespace esphome::cgdn1_display
