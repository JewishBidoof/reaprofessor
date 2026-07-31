// ReaProfessor — tiny REAPER extension
// Adds Extensions → ReaProfessor via hookcustommenu (coexists with all other
// extensions). Does NOT touch reaper-menu.ini.
//
// Launch: custom_action requires hookcommand2 (not only hookcommand). We also
// register the hub .lua as a ReaScript action when the file is present so
// REAPER can run it directly.

#include "reaper_plugin.h"

#ifdef _WIN32
  #include <windows.h>
#else
  #include "swell.h"
#endif

#include <stdio.h>
#include <string.h>

static bool (*AddExtensionsMainMenu)();
static int  (*AddRemoveReaScript)(bool add, int sectionID, const char *scriptfn, bool commit);
static const char *(*GetResourcePath)();
static void (*Main_OnCommand)(int command, int flag);
static int  (*NamedCommandLookup)(const char *name);
static void (*ShowConsoleMsg)(const char *msg);
static int  (*plugin_register)(const char *name, void *infostruct);
static void (*SetExtState)(const char *section, const char *key, const char *val, bool persist);

static int g_cmd = 0;          // our Extensions/action command id
static int g_script_cmd = 0;   // AddRemoveReaScript id for the hub .lua (never equal to g_cmd)
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
  *(void **)&AddRemoveReaScript = getFunc("AddRemoveReaScript");
  *(void **)&ShowConsoleMsg = getFunc("ShowConsoleMsg");
  *(void **)&SetExtState = getFunc("SetExtState");
  #undef REQ
  return true;
}

static bool file_exists(const char *path)
{
#ifdef _WIN32
  return GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES;
#else
  FILE *f = fopen(path, "r");
  if (!f) return false;
  fclose(f);
  return true;
#endif
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
    if (file_exists(out)) return true;
  }
  out[0] = 0;
  return false;
}

static int ensure_script_cmd()
{
  if (g_script_cmd) return g_script_cmd;
  if (!g_script_path[0] && !find_hub_script(g_script_path, sizeof(g_script_path))) {
    return 0;
  }
  if (AddRemoveReaScript) {
    g_script_cmd = AddRemoveReaScript(true, 0, g_script_path, true);
  }
  return g_script_cmd;
}

static void run_hub()
{
  const int script_cmd = ensure_script_cmd();
  if (!script_cmd) {
    if (ShowConsoleMsg) {
      ShowConsoleMsg(
        "[ReaProfessor] Hub script not found.\n"
        "Expected Scripts/ReaProfessor/ReaProfessor.lua under the resource path.\n");
    }
    return;
  }
  // Never Main_OnCommand(g_cmd) — that re-enters this action.
  Main_OnCommand(script_cmd, 0);
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

// custom_action docs: related callback must be hookcommand2.
static bool hook_command2(KbdSectionInfo *sec, int command, int val, int val2,
                          int relmode, HWND hwnd)
{
  (void)sec; (void)val; (void)val2; (void)relmode; (void)hwnd;
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
  if (!menu) return;

  // Prefer the ReaScript command id so the menu invokes REAPER's normal
  // script runner (no dependency on which hook fires for custom_action).
  ensure_script_cmd();
  const int id = g_script_cmd ? g_script_cmd : g_cmd;
  if (!id) return;

  MENUITEMINFO mi;
  memset(&mi, 0, sizeof(mi));
  mi.cbSize = sizeof(mi);
  mi.fMask = MIIM_TYPE | MIIM_ID;
  mi.fType = MFT_STRING;
  mi.wID = (UINT)id;
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
      plugin_register("-hookcommand2", (void *)hook_command2);
      plugin_register("-hookcustommenu", (void *)hook_menu);
    }
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION) return 0;
  if (!resolve_api(rec->GetFunc)) return 0;

  find_hub_script(g_script_path, sizeof(g_script_path));
  ensure_script_cmd();

  // Named action in the Action List + Extensions menu.
  static custom_action_register_t action =
    { 0, "REAPROFESSOR", "ReaProfessor", NULL };
  g_cmd = (int)(intptr_t)plugin_register("custom_action", &action);
  if (!g_cmd) return 0;

  plugin_register("hookcommand", (void *)hook_command);
  plugin_register("hookcommand2", (void *)hook_command2);
  plugin_register("hookcustommenu", (void *)hook_menu);
  AddExtensionsMainMenu();

  if (SetExtState) {
    SetExtState("ReaProfessor", "native_ext", "1", false);
  }
  return 1;
}
