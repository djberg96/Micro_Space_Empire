#define _GNU_SOURCE

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/*
 * Keep the launcher buildable from Fedora's runtime packages alone. These are
 * stable public GTK4, GLib, and WebKitGTK 6 ABI declarations; using the full
 * development headers would otherwise make end-user builds pull in a large
 * dependency tree.
 */
typedef struct _GApplication GApplication;
typedef struct _GtkApplication GtkApplication;
typedef struct _GtkWidget GtkWidget;
typedef struct _GtkWindow GtkWindow;
typedef unsigned long GType;
typedef unsigned long gulong;

extern GtkApplication *gtk_application_new(const char *application_id, int flags);
extern GtkWidget *gtk_application_window_new(GtkApplication *application);
extern void gtk_window_set_title(GtkWindow *window, const char *title);
extern void gtk_window_set_default_size(GtkWindow *window, int width, int height);
extern void gtk_window_set_child(GtkWindow *window, GtkWidget *child);
extern void gtk_window_present(GtkWindow *window);
extern GtkWidget *webkit_web_view_new(void);
extern void webkit_web_view_load_uri(void *web_view, const char *uri);
extern int g_application_run(GApplication *application, int argc, char **argv);
extern gulong g_signal_connect_data(
    void *instance,
    const char *detailed_signal,
    void (*handler)(void),
    void *data,
    void (*destroy_data)(void *, void *),
    int connect_flags);
extern void g_object_unref(void *object);
extern int g_mkdir_with_parents(const char *pathname, int mode);

extern const unsigned char _binary_micro_space_empire_server_start[];
extern const unsigned char _binary_micro_space_empire_server_end[];
extern char **environ;

static pid_t server_pid = -1;
static char game_url[128];

static void stop_server(void) {
  if (server_pid <= 0) {
    return;
  }

  kill(server_pid, SIGTERM);
  while (waitpid(server_pid, NULL, 0) < 0 && errno == EINTR) {
  }
  server_pid = -1;
}

static void handle_signal(int signal_number) {
  if (server_pid > 0) {
    kill(server_pid, SIGTERM);
  }
  _exit(128 + signal_number);
}

static uint16_t reserve_local_port(void) {
  int descriptor = socket(AF_INET, SOCK_STREAM, 0);
  if (descriptor < 0) {
    return 0;
  }

  struct sockaddr_in address = {
      .sin_family = AF_INET,
      .sin_port = 0,
      .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
  };
  if (bind(descriptor, (struct sockaddr *)&address, sizeof(address)) != 0) {
    close(descriptor);
    return 0;
  }

  socklen_t length = sizeof(address);
  if (getsockname(descriptor, (struct sockaddr *)&address, &length) != 0) {
    close(descriptor);
    return 0;
  }

  uint16_t port = ntohs(address.sin_port);
  close(descriptor);
  return port;
}

static int write_all(int descriptor, const unsigned char *data, size_t length) {
  while (length > 0) {
    ssize_t written = write(descriptor, data, length);
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      return -1;
    }
    data += written;
    length -= (size_t)written;
  }
  return 0;
}

static int embedded_server_descriptor(void) {
  int descriptor = memfd_create("micro-space-empire-server", MFD_CLOEXEC);
  if (descriptor < 0) {
    return -1;
  }

  size_t length = (size_t)(_binary_micro_space_empire_server_end -
                           _binary_micro_space_empire_server_start);
  if (write_all(descriptor, _binary_micro_space_empire_server_start, length) != 0 ||
      fchmod(descriptor, 0700) != 0 || lseek(descriptor, 0, SEEK_SET) < 0) {
    close(descriptor);
    return -1;
  }
  return descriptor;
}

static int database_path(char *path, size_t size) {
  const char *data_home = getenv("XDG_DATA_HOME");
  char directory[PATH_MAX];

  if (data_home && data_home[0] != '\0') {
    if (snprintf(directory, sizeof(directory), "%s/micro-space-empire", data_home) >=
        (int)sizeof(directory)) {
      return -1;
    }
  } else {
    const char *home = getenv("HOME");
    if (!home || home[0] == '\0' ||
        snprintf(directory, sizeof(directory), "%s/.local/share/micro-space-empire", home) >=
            (int)sizeof(directory)) {
      return -1;
    }
  }

  if (g_mkdir_with_parents(directory, 0700) != 0 ||
      snprintf(path, size, "%s/micro_space_empire.db", directory) >= (int)size) {
    return -1;
  }
  return 0;
}

static int start_server(uint16_t port) {
  int descriptor = embedded_server_descriptor();
  if (descriptor < 0) {
    return -1;
  }

  char port_text[16];
  char save_path[PATH_MAX];
  snprintf(port_text, sizeof(port_text), "%u", port);
  if (database_path(save_path, sizeof(save_path)) != 0) {
    close(descriptor);
    return -1;
  }

  server_pid = fork();
  if (server_pid < 0) {
    close(descriptor);
    return -1;
  }

  if (server_pid == 0) {
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    setenv("KEMAL_ENV", "production", 1);
    setenv("MSE_HOST", "127.0.0.1", 1);
    setenv("MSE_PORT", port_text, 1);
    setenv("MSE_DATABASE_PATH", save_path, 1);
    setenv("MSE_OPEN_BROWSER", "false", 1);

    int null_descriptor = open("/dev/null", O_RDWR);
    if (null_descriptor >= 0) {
      dup2(null_descriptor, STDOUT_FILENO);
      dup2(null_descriptor, STDERR_FILENO);
      close(null_descriptor);
    }

    char *const arguments[] = {(char *)"micro-space-empire-server", NULL};
    fexecve(descriptor, arguments, environ);
    _exit(127);
  }

  close(descriptor);
  return 0;
}

static int wait_for_server(uint16_t port) {
  const struct timespec pause = {.tv_sec = 0, .tv_nsec = 50 * 1000 * 1000};

  for (int attempt = 0; attempt < 100; ++attempt) {
    int status;
    if (waitpid(server_pid, &status, WNOHANG) == server_pid) {
      server_pid = -1;
      return -1;
    }

    int descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (descriptor >= 0) {
      struct sockaddr_in address = {
          .sin_family = AF_INET,
          .sin_port = htons(port),
          .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
      };
      if (connect(descriptor, (struct sockaddr *)&address, sizeof(address)) == 0) {
        close(descriptor);
        return 0;
      }
      close(descriptor);
    }
    nanosleep(&pause, NULL);
  }
  return -1;
}

static void activate(GtkApplication *application, void *unused) {
  (void)unused;
  GtkWidget *window = gtk_application_window_new(application);
  GtkWidget *web_view = webkit_web_view_new();

  gtk_window_set_title((GtkWindow *)window, "Micro Space Empire");
  gtk_window_set_default_size((GtkWindow *)window, 1440, 900);
  gtk_window_set_child((GtkWindow *)window, web_view);
  webkit_web_view_load_uri(web_view, game_url);
  gtk_window_present((GtkWindow *)window);
}

int main(int argc, char **argv) {
  uint16_t port = reserve_local_port();
  if (port == 0 || start_server(port) != 0 || wait_for_server(port) != 0) {
    fprintf(stderr, "Micro Space Empire could not start its private game server.\n");
    stop_server();
    return 1;
  }

  snprintf(game_url, sizeof(game_url), "http://127.0.0.1:%u/", port);
  atexit(stop_server);
  signal(SIGINT, handle_signal);
  signal(SIGTERM, handle_signal);

  /* G_APPLICATION_NON_UNIQUE lets separate launches have independent servers. */
  GtkApplication *application = gtk_application_new("com.microspaceempire.desktop", 1 << 5);
  g_signal_connect_data(application, "activate", (void (*)(void))activate, NULL, NULL, 0);
  int status = g_application_run((GApplication *)application, argc, argv);
  g_object_unref(application);
  return status;
}

__asm__(".section .note.GNU-stack,\"\",@progbits");
