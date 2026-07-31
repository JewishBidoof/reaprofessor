// ReaProfessor — tiny REAPER extension
// Adds Extensions → ReaProfessor via hookcustommenu (coexists with all other
// extensions). Does NOT touch reaper-menu.ini.
//
// Launch path mirrors ReaPack/SWS:
//   command_id + gaccel + hookcommand → one-shot timer → Main_OnCommand(script)
// Hub .lua is located under Scripts/ (several layouts) or ExtState, then
// registered via AddRemoveReaScript or custom_action(reascript).

#include "reaper_plugin.h"

#ifdef _WIN32
  #include <windows.h>
#else
  #include "swell.h"
  #include <dirent.h>
  #include <sys/stat.h>
  #include <unistd.h>
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
static const char *(*GetExtState)(const char *section, const char *key);

static int g_cmd = 0;          // command_id for Extensions / Action List
static int g_script_cmd = 0;   // command id that runs the hub .lua
static char g_script_path[4096];
static bool g_pending_launch = false;
static gaccel_register_t g_accel;
static custom_action_register_t g_script_action;

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
  *(void **)&GetExtState = getFunc("GetExtState");
  #undef REQ
  return true;
}

static bool file_exists(const char *path)
{
  if (!path || !*path) return false;
#ifdef _WIN32
  DWORD attrs = GetFileAttributesA(path);
  return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
#else
  struct stat st;
  if (stat(path, &st) != 0) return false;
  return S_ISREG(st.st_mode);
#endif
}

static bool is_hub_filename(const char *name)
{
  return name && !strcmp(name, "ReaProfessor.lua");
}

// Depth-limited walk for …/ReaProfessor.lua under Scripts/.
static bool walk_find_hub(const char *dir, char *out, size_t out_sz, int depth)
{
  if (depth < 0 || !dir || !*dir) return false;
#ifdef _WIN32
  char pattern[4096];
  snprintf(pattern, sizeof(pattern), "%s\\*", dir);
  WIN32_FIND_DATAA fd;
  HANDLE h = FindFirstFileA(pattern, &fd);
  if (h == INVALID_HANDLE_VALUE) return false;
  do {
    if (!strcmp(fd.cFileName, ".") || !strcmp(fd.cFileName, "..")) continue;
    char child[4096];
    snprintf(child, sizeof(child), "%s\\%s", dir, fd.cFileName);
    if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
      if (walk_find_hub(child, out, out_sz, depth - 1)) {
        FindClose(h);
        return true;
      }
    } else if (is_hub_filename(fd.cFileName)) {
      snprintf(out, out_sz, "%s", child);
      FindClose(h);
      return true;
    }
  } while (FindNextFileA(h, &fd));
  FindClose(h);
#else
  DIR *d = opendir(dir);
  if (!d) return false;
  struct dirent *ent;
  while ((ent = readdir(d)) != NULL) {
    if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, "..")) continue;
    char child[4096];
    snprintf(child, sizeof(child), "%s/%s", dir, ent->d_name);
    struct stat st;
    if (stat(child, &st) != 0) continue;
    if (S_ISDIR(st.st_mode)) {
      if (walk_find_hub(child, out, out_sz, depth - 1)) {
        closedir(d);
        return true;
      }
    } else if (S_ISREG(st.st_mode) && is_hub_filename(ent->d_name)) {
      snprintf(out, out_sz, "%s", child);
      closedir(d);
      return true;
    }
  }
  closedir(d);
#endif
  return false;
}

static bool find_hub_script(char *out, size_t out_sz)
{
  out[0] = 0;

  // 1) Path persisted by Lua (Menu.register_hub / startup_hook).
  if (GetExtState) {
    const char *saved = GetExtState("ReaProfessor", "menu_hub_path");
    if (saved && *saved && file_exists(saved)) {
      snprintf(out, out_sz, "%s", saved);
      return true;
    }
  }

  const char *res = GetResourcePath();
  if (!res || !*res) return false;

  // 2) Known ReaPack / manual layouts (forward slashes OK on Windows REAPER).
  static const char *rels[] = {
    "/Scripts/ReaProfessor/ReaProfessor.lua",
    "/Scripts/Live/ReaProfessor/ReaProfessor.lua",
    "/Scripts/ReaProfessor Scripts/ReaProfessor/ReaProfessor.lua",
    "/Scripts/ReaProfessor Scripts/Live/ReaProfessor.lua",
  };
  for (size_t i = 0; i < sizeof(rels) / sizeof(rels[0]); i++) {
    snprintf(out, out_sz, "%s%s", res, rels[i]);
    if (file_exists(out)) return true;
  }

  // 3) Shallow scan under Scripts/ for any ReaProfessor.lua (covers odd ReaPack trees).
  char scripts[4096];
  snprintf(scripts, sizeof(scripts), "%s/Scripts", res);
  if (walk_find_hub(scripts, out, out_sz, 4)) return true;

  out[0] = 0;
  return false;
}

static int ensure_script_cmd()
{
  if (g_script_cmd) return g_script_cmd;

  // Always re-resolve: scripts may appear after a ReaPack sync without restart.
  if (!find_hub_script(g_script_path, sizeof(g_script_path))) {
    return 0;
  }

  if (AddRemoveReaScript) {
    g_script_cmd = AddRemoveReaScript(true, 0, g_script_path, true);
    if (g_script_cmd) return g_script_cmd;
  }

  // Fallback: register the file as a ReaScript custom_action (idStr NULL).
  memset(&g_script_action, 0, sizeof(g_script_action));
  g_script_action.uniqueSectionId = 0;
  g_script_action.idStr = NULL;
  g_script_action.name = g_script_path; // must outlive registration
  g_script_cmd = (int)(intptr_t)plugin_register("custom_action", &g_script_action);
  return g_script_cmd;
}

static void report_launch_failure()
{
  if (!ShowConsoleMsg) return;
  const char *res = GetResourcePath ? GetResourcePath() : "(null)";
  if (!res) res = "(null)";
  if (!g_script_path[0]) {
    ShowConsoleMsg("[ReaProfessor] Hub script not found under Scripts/.\n");
    ShowConsoleMsg("Resource path: ");
    ShowConsoleMsg(res);
    ShowConsoleMsg(
      "\nInstall/sync the ReaProfessor package (ReaPack), or load\n"
      "Scripts/ReaProfessor/ReaProfessor.lua once via Actions → ReaScript: Load.\n");
  } else {
    ShowConsoleMsg(
      "[ReaProfessor] Found hub script but could not register it as an action:\n  ");
    ShowConsoleMsg(g_script_path);
    ShowConsoleMsg(
      "\nTry Actions → Show action list → ReaScript: Load… on that file, then retry.\n");
  }
}

static void launch_timer()
{
  // One-shot: unregister first so we do not spin every ~30ms.
  plugin_register("-timer", (void *)launch_timer);
  if (!g_pending_launch) return;
  g_pending_launch = false;

  // Allow a fresh resolve each launch (path may have been empty at plugin load).
  if (!g_script_cmd) g_script_path[0] = 0;

  const int script_cmd = ensure_script_cmd();
  if (!script_cmd) {
    report_launch_failure();
    return;
  }
  Main_OnCommand(script_cmd, 0);
}

static void request_hub_launch()
{
  g_pending_launch = true;
  // Nested Main_OnCommand(script) from inside a command hook does not run
  // ReaScripts; defer to REAPER's timer so the script starts cleanly.
  plugin_register("timer", (void *)launch_timer);
}

static bool hook_command(int command, int flag)
{
  (void)flag;
  if (g_cmd && command == g_cmd) {
    request_hub_launch();
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
      plugin_register("-timer", (void *)launch_timer);
      if (g_cmd) {
        plugin_register("-gaccel", &g_accel);
        plugin_register("-command_id", (void *)"REAPROFESSOR");
      }
    }
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION) return 0;
  if (!resolve_api(rec->GetFunc)) return 0;

  find_hub_script(g_script_path, sizeof(g_script_path));
  ensure_script_cmd();

  g_cmd = (int)(intptr_t)plugin_register("command_id", (void *)"REAPROFESSOR");
  if (!g_cmd) return 0;

  memset(&g_accel, 0, sizeof(g_accel));
  g_accel.accel.cmd = (unsigned short)g_cmd;
  g_accel.desc = "ReaProfessor";
  plugin_register("gaccel", &g_accel);

  plugin_register("hookcommand", (void *)hook_command);
  plugin_register("hookcustommenu", (void *)hook_menu);
  AddExtensionsMainMenu();

  if (SetExtState) {
    SetExtState("ReaProfessor", "native_ext", "1", false);
  }
  return 1;
}
