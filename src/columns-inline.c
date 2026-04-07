/*---------------------------------------------------------------------------
  Terminal width detection via ioctl(TIOCGWINSZ).
  Falls back to the COLUMNS environment variable, then to 80.
---------------------------------------------------------------------------*/
#include <sys/ioctl.h>
#include <unistd.h>
#include <stdlib.h>

static kk_integer_t kk_os_terminal_width(kk_context_t* ctx) {
  struct winsize ws = { 0 };
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) {
    return kk_integer_from_int((int)ws.ws_col, ctx);
  }
  const char* cols = getenv("COLUMNS");
  if (cols != NULL) {
    int w = atoi(cols);
    if (w > 0) return kk_integer_from_int(w, ctx);
  }
  return kk_integer_from_int(80, ctx);
}
