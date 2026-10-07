/*
 * kago-tun — the only setuid-root program of KaGo VPN for macOS.
 *
 * "All traffic through VPN" needs a root Mihomo core (it creates the utun
 * interface and the routes). A setuid copy of Mihomo itself would let any
 * process of an admin user run Mihomo as root with its own -d/-f and make it
 * write files anywhere. This wrapper takes nothing from the caller but the
 * config on stdin:
 *   - argv and the environment are ignored (no -d, -f, -post-up, SAFE_PATHS,
 *     CLASH_* ...);
 *   - the core and its home folder are root-owned and fixed
 *     (/Library/Application Support/net.usekago.app/{mihomo,run}), so
 *     providers, cache and geodata can only be written there;
 *   - the config is refused if it names a listener or a file the core would
 *     create outside its home (controller unix socket/pipe/TLS, external UI,
 *     inbound listeners), asks to set the system clock, or uses YAML escapes
 *     or tags that could hide such a key.
 * It then execs the core: the real uid stays the user's, so the app can stop
 * it with a signal, and ptrace is refused for a set-uid process.
 *
 * Build: clang -O2 -Wall -Wextra -Werror -arch arm64 -arch x86_64 \
 *          -mmacosx-version-min=12.0 -o kago-tun kago_tun.c
 * Test:  cc -DKAGO_TUN_SELF_TEST -o kago-tun-test kago_tun.c && ./kago-tun-test
 */

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define KAGO_ROOT "/Library/Application Support/net.usekago.app"
#define KAGO_CORE KAGO_ROOT "/mihomo"
#define KAGO_RUN KAGO_ROOT "/run"
#define KAGO_CONFIG KAGO_RUN "/config.yaml"
#define KAGO_MAX_CONFIG (16u * 1024u * 1024u)

/* Keys and constructs the root core must never get from a config. */
static const char *const kForbidden[] = {
    "external-controller-unix",
    "external-controller-pipe",
    "external-controller-tls",
    "external-ui",
    "external-doh-server",
    "write-to-system",
    "listeners",
    "!!",           /* YAML tags such as !!binary */
    "!<",           /* verbatim tags */
    "%tag",         /* tag directives */
    "tag:yaml.org", /* full tag names */
};

/* Case-insensitive search for needle in the first len bytes of hay. */
static int contains_ci(const char *hay, size_t len, const char *needle) {
  size_t n = strlen(needle);
  if (n == 0 || n > len) return 0;
  for (size_t i = 0; i + n <= len; i++) {
    size_t j = 0;
    while (j < n && tolower((unsigned char)hay[i + j]) == needle[j]) j++;
    if (j == n) return 1;
  }
  return 0;
}

/*
 * 1 if the config may be given to the root core. Only simple escapes are
 * allowed (\\ \" \/ \n \r \t \b \f): \u, \x, \U and line continuations could
 * spell a forbidden key without its letters appearing in the text.
 */
int kago_config_allowed(const char *buf, size_t len) {
  if (len == 0 || len > KAGO_MAX_CONFIG) return 0;
  if (memchr(buf, '\0', len) != NULL) return 0;
  for (size_t i = 0; i < len; i++) {
    if (buf[i] != '\\') continue;
    if (i + 1 >= len) return 0;
    switch (buf[i + 1]) {
      case '\\': case '"': case '/': case 'n': case 'r': case 't':
      case 'b': case 'f':
        i++;
        break;
      default:
        return 0;
    }
  }
  for (size_t k = 0; k < sizeof(kForbidden) / sizeof(kForbidden[0]); k++) {
    if (contains_ci(buf, len, kForbidden[k])) return 0;
  }
  return 1;
}

#ifndef KAGO_TUN_SELF_TEST

static void fail(const char *message) {
  fprintf(stderr, "kago-tun: %s\n", message);
  exit(1);
}

/* A root-owned path nobody else can replace: not a symlink, owner root,
 * not writable by group or others, and of the expected type. */
static void require_root_owned(const char *path, mode_t type) {
  struct stat st;
  if (lstat(path, &st) != 0) fail("missing root-owned file");
  if ((st.st_mode & S_IFMT) != type) fail("unexpected file type");
  if (st.st_uid != 0) fail("file is not owned by root");
  if (st.st_mode & (S_IWGRP | S_IWOTH)) fail("file is writable by others");
}

static char *read_stdin(size_t *out_len) {
  size_t cap = 64 * 1024, len = 0;
  char *buf = malloc(cap);
  if (buf == NULL) fail("out of memory");
  for (;;) {
    if (len == cap) {
      if (cap >= KAGO_MAX_CONFIG) fail("config is too large");
      cap *= 2;
      char *next = realloc(buf, cap);
      if (next == NULL) fail("out of memory");
      buf = next;
    }
    ssize_t n = read(STDIN_FILENO, buf + len, cap - len);
    if (n == 0) break;
    if (n < 0) {
      if (errno == EINTR) continue;
      fail("cannot read the config");
    }
    len += (size_t)n;
    if (len > KAGO_MAX_CONFIG) fail("config is too large");
  }
  *out_len = len;
  return buf;
}

int main(void) {
  if (geteuid() != 0) fail("must be installed set-uid root");
  umask(077);

  /* Nothing inherited beyond stdio. */
  long max_fd = sysconf(_SC_OPEN_MAX);
  if (max_fd < 0 || max_fd > 65536) max_fd = 65536;
  for (int fd = 3; fd < max_fd; fd++) close(fd);

  require_root_owned(KAGO_ROOT, S_IFDIR);
  require_root_owned(KAGO_CORE, S_IFREG);
  struct stat run;
  if (lstat(KAGO_RUN, &run) != 0) {
    if (mkdir(KAGO_RUN, 0700) != 0) fail("cannot create the core folder");
  }
  require_root_owned(KAGO_RUN, S_IFDIR);
  if (chmod(KAGO_RUN, 0700) != 0) fail("cannot protect the core folder");

  size_t len = 0;
  char *config = read_stdin(&len);
  if (!kago_config_allowed(config, len)) fail("config refused");

  int out = open(KAGO_CONFIG, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (out < 0) fail("cannot write the config");
  size_t written = 0;
  while (written < len) {
    ssize_t n = write(out, config + written, len - written);
    if (n < 0) {
      if (errno == EINTR) continue;
      fail("cannot write the config");
    }
    written += (size_t)n;
  }
  if (fchmod(out, 0600) != 0 || close(out) != 0) fail("cannot write the config");
  free(config);

  int null_fd = open("/dev/null", O_RDONLY);
  if (null_fd >= 0) {
    dup2(null_fd, STDIN_FILENO);
    if (null_fd != STDIN_FILENO) close(null_fd);
  }

  char *const argv[] = {"mihomo", "-d", KAGO_RUN, "-f", KAGO_CONFIG, NULL};
  char *const envp[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "HOME=/var/root", NULL};
  execve(KAGO_CORE, argv, envp);
  fail("cannot start the core");
  return 1;
}

#else /* KAGO_TUN_SELF_TEST */

static int failures = 0;

static void expect(const char *name, const char *config, int allowed) {
  if (kago_config_allowed(config, strlen(config)) != allowed) {
    fprintf(stderr, "FAIL %s\n", name);
    failures++;
  }
}

int main(int argc, char **argv) {
  /* --check: is the config on stdin allowed? (used by the Dart tests) */
  if (argc == 2 && strcmp(argv[1], "--check") == 0) {
    size_t cap = KAGO_MAX_CONFIG + 1, len = 0;
    char *buf = malloc(cap);
    if (buf == NULL) return 2;
    ssize_t n;
    while (len < cap && (n = read(STDIN_FILENO, buf + len, cap - len)) > 0) len += (size_t)n;
    int allowed = kago_config_allowed(buf, len);
    free(buf);
    return allowed ? 0 : 1;
  }
  expect("plain json", "{\"mixed-port\":7890,\"proxies\":[{\"name\":\"de \\\"1\\\"\"}]}", 1);
  expect("cyrillic", "{\"proxies\":[{\"name\":\"Германия\"}]}", 1);
  expect("unix socket", "{\"external-controller-unix\":\"/etc/x\"}", 0);
  expect("yaml unix socket", "external-controller-unix: /etc/x\n", 0);
  expect("upper case", "{\"External-Controller-Unix\":\"/etc/x\"}", 0);
  expect("unicode escape", "{\"external-controller-\\u0075nix\":\"/etc/x\"}", 0);
  expect("hex escape", "{\"external-controller-\\x75nix\":\"/etc/x\"}", 0);
  expect("continuation", "{\"external-controller-\\\nunix\":\"/etc/x\"}", 0);
  expect("ntp clock", "{\"ntp\":{\"enable\":true,\"write-to-system\":true}}", 0);
  expect("external ui", "{\"external-ui\":\"/tmp/ui\"}", 0);
  expect("listeners", "{\"listeners\":[]}", 0);
  expect("binary tag", "a: !!binary ZXh0ZXJuYWw=\n", 0);
  expect("tag directive", "%TAG ! tag:yaml.org,2002:\n---\na: 1\n", 0);
  expect("empty", "", 0);
  if (failures == 0) printf("kago-tun self-test: ok\n");
  return failures == 0 ? 0 : 1;
}

#endif
