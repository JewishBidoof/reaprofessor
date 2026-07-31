// ReaProfessor — tiny REAPER extension
// Adds Extensions → ReaProfessor via hookcustommenu (coexists with all other
// extensions). Does NOT touch reaper-menu.ini.
//
// Build: see native/Makefile / tools/build_extension.sh

#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_AddExtensionsMainMenu
#define REAPERAPI_WANT_AddRemoveReaScript
#define REAPERAPI_WANT_GetResourcePath
#define REAPERAPI_WANT_Main_OnCommand
#define REAPERAPI_WANT_NamedCommandLookup
#define REAPERAPI_WANT_ShowConsoleMsg
#define REAPERAPI_WANT_plugin_register

#include "reaper_plugin.h"

#ifdef _WIN32
  #include <windows.h>
#else
  #include "swell.h"
#endif

#include <stdio.h>
#include <string.h>

#ifndef _WIN32
  // swell-modstub provides function pointers; declare what we use if needed
#endif

// Minimal API pointers (avoid shipping the huge generated functions header)
static bool (*AddExtensionsMainMenu)();
static int  (*AddRemoveReaScript)(bool add, int sectionID, const char *scriptfn, bool commit);
static const char *(*GetResourcePath)();
static void (*Main_OnCommand)(int command, int flag);
static int  (*NamedCommandLookup)(const char *name);
static void (*ShowConsoleMsg)(const char *msg);
static int  (*plugin_register)(const char *name, void *infostruct);

static int g_cmd = 0;
static char g_script_path[4096];

static bool resolve_api(void *(*getFunc)(const char *))
{
  #define REQ(name) do { \
    *(void **)&name = getFunc(#name); \
    if (!name) return false; \
  } while (0)
  REQ(AddExtensionsMainMenu);
  REQ(GetResourcePath);
  REQ(Main_OnCommand);
  REQ(NamedCommandLookup);
  REQ(plugin_register);
  // optional
  *(void **)&AddRemoveReaScript = getFunc("AddRemoveReaScript");
  *(void **)&ShowConsoleMsg = getFunc("ShowConsoleMsg");
  #undef REQ
  return true;
}

static bool find_hub_script(char *out, size_t out_sz)
{
  const char *res = GetResourcePath();
  if (!res || !*res) return false;
  static const char *rels[] = {
    "/Scripts/ReaProfessor/ReaProfessor.lua",
    "/Scripts/Live/ReaProfessor/ReaProfessor.lua",
  };
  for (size_t i = 0; i < sizeof(rels) / sizeof(rels[0]); i++) {
    snprintf(out, out_sz, "%s%s", res, rels[i]);
#ifdef _WIN32
    if (GetFileAttributesA(out) != INVALID_FILE_ATTRIBUTES) return true;
#else
    FILE *f = fopen(out, "r");
    if (f) { fclose(f); return true; }
#endif
  }
  out[0] = 0;
  return false;
}

static void run_hub()
{
  if (!g_script_path[0] && !find_hub_script(g_script_path, sizeof(g_script_path))) {
    if (ShowConsoleMsg)
      ShowConsoleMsg("[ReaProfessor] Hub script not found under Scripts/ReaProfessor/\n");
    return;
  }

  int cmd = 0;
  if (AddRemoveReaScript) {
    cmd = AddRemoveReaScript(true, 0, g_script_path, true);
  }
  if (!cmd) {
    // Fall back to named lookup if already registered in the action list
    cmd = NamedCommandLookup("_REAPROFESSOR");
  }
  if (cmd) {
    Main_OnCommand(cmd, 0);
  } else if (ShowConsoleMsg) {
    ShowConsoleMsg("[ReaProfessor] Could not register/run hub script\n");
  }
}

static bool hook_command(int command, int flag)
{
  (void)flag;
  if (g_cmd && command == g_cmd) {
    run_hub();
    return true;
  }
  return false;
}

static void hook_menu(const char *menustr, HMENU menu, int flag)
{
  if (flag != 0) return;
  if (!menustr || strcmp(menustr, "Main extensions") != 0) return;
  if (!menu || !g_cmd) return;

  MENUITEMINFO mi;
  memset(&mi, 0, sizeof(mi));
  mi.cbSize = sizeof(mi);
  mi.fMask = MIIM_TYPE | MIIM_ID;
  mi.fType = MFT_STRING;
  mi.wID = (UINT)g_cmd;
  mi.dwTypeData = (char *)"ReaProfessor";
  InsertMenuItem(menu, GetMenuItemCount(menu), TRUE, &mi);
}

extern "C" REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(
  REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t *rec)
{
  (void)hInstance;
  if (!rec) {
    if (plugin_register) {
      plugin_register("-hookcommand", (void *)hook_command);
      plugin_register("-hookcustommenu", (void *)hook_menu);
    }
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION) return 0;
  if (!resolve_api(rec->GetFunc)) return 0;

  find_hub_script(g_script_path, sizeof(g_script_path));

  static custom_action_register_t action =
    { 0, "REAPROFESSOR", "ReaProfessor", NULL };
  g_cmd = (int)(intptr_t)plugin_register("custom_action", &action);
  if (!g_cmd) return 0;

  plugin_register("hookcommand", (void *)hook_command);
  plugin_register("hookcustommenu", (void *)hook_menu);
  AddExtensionsMainMenu();
  return 1;
}
