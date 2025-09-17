/**
 * user.js - Firefox memory- and performance-optimization tweaks
 *
 * This file is intended for users with many tabs or profiles, to reduce RAM usage,
 * limit background processes, and disable unnecessary features.
 * Drop this file into your Firefox profile directory:
 * ~/.mozilla/firefox/<profile>/
 *
 * Note: prefs in this file override Firefox defaults on startup.
 */

/***********************************************
 * Tab Unloading / Background Tab Management
 ***********************************************/

// Automatically unload background tabs when memory is low
user_pref("browser.tabs.unloadOnLowMemory", true);

// Delay (in milliseconds) before unloading background tabs after low-memory is detected
user_pref("browser.tabs.unloadOnLowMemory.delay", 500);

// Target percentage of memory to free when unloading tabs (0-100)
user_pref("browser.tabs.unloadOnLowMemory.percentage", 75);

// Load tabs only when selected (do not preload background tabs)
user_pref("browser.tabs.loadInBackground", false);

// Don't load all tabs at startup; load them on-demand when clicked
user_pref("browser.sessionstore.restore_on_demand", true);

// Maximum number of closed tabs stored for "Undo Close Tab" (0 disables this feature)
user_pref("browser.sessionstore.max_tabs_undo", 0);

/***********************************************
 * Network / Prefetching
 ***********************************************/

// Disable preloading pages that you haven't clicked
user_pref("network.prefetch-next", false);

/***********************************************
 * Built-in Feature Disabling
 ***********************************************/

// Disable Pocket integration (toolbar, context menu, background tasks)
user_pref("extensions.pocket.enabled", false);

// Disable Firefox telemetry (data collection)
user_pref("toolkit.telemetry.enabled", false);

// Disable Health Report upload
user_pref("datareporting.healthreport.uploadEnabled", false);

/***********************************************
 * Memory / Session History
 ***********************************************/

// Disable "fast back" page cache to save memory
user_pref("browser.sessionhistory.max_total_viewers", 0);

