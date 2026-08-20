#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/sysinfo.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <time.h>

/* ── ANSI colour codes ────────────────────────────────────────────── */
#define RESET   "\033[0m"
#define BOLD    "\033[1m"
#define DIM     "\033[2m"
#define RED     "\033[31m"
#define GREEN   "\033[32m"
#define YELLOW  "\033[33m"
#define BLUE    "\033[34m"
#define CYAN    "\033[36m"
#define WHITE   "\033[37m"
#define BGREEN  "\033[1;32m"
#define BCYAN   "\033[1;36m"
#define BYELLOW "\033[1;33m"

#define BAR_WIDTH 30

/* ── Helpers ──────────────────────────────────────────────────────── */
static void clear_screen(void) { printf("\033[2J\033[H"); }

static void print_bar(double pct, const char *colour)
{
    int filled = (int)(pct * BAR_WIDTH / 100.0);
    printf("%s[", colour);
    for (int i = 0; i < BAR_WIDTH; i++)
        printf("%s", i < filled ? "█" : "░");
    printf("%s]%s %5.1f%%", colour, RESET, pct);
}

/* ── CPU usage ────────────────────────────────────────────────────── */
typedef struct { long user, nice, sys, idle, iowait, irq, softirq; } CpuStat;

static int read_cpu(CpuStat *s)
{
    FILE *f = fopen("/proc/stat", "r");
    if (!f) return -1;
    int r = fscanf(f, "cpu %ld %ld %ld %ld %ld %ld %ld",
                   &s->user, &s->nice, &s->sys, &s->idle,
                   &s->iowait, &s->irq, &s->softirq);
    fclose(f);
    return r == 7 ? 0 : -1;
}

static double cpu_percent(void)
{
    CpuStat a, b;
    if (read_cpu(&a)) return -1;
    usleep(200000);
    if (read_cpu(&b)) return -1;
    long idle1 = a.idle + a.iowait,  idle2 = b.idle + b.iowait;
    long tot1  = a.user + a.nice + a.sys + a.idle + a.iowait + a.irq + a.softirq;
    long tot2  = b.user + b.nice + b.sys + b.idle + b.iowait + b.irq + b.softirq;
    long dtot  = tot2 - tot1;
    if (dtot == 0) return 0.0;
    return 100.0 * (1.0 - (double)(idle2 - idle1) / dtot);
}

/* ── RAM ──────────────────────────────────────────────────────────── */
static void ram_info(unsigned long *used_mb, unsigned long *total_mb)
{
    struct sysinfo si;
    sysinfo(&si);
    *total_mb = si.totalram * si.mem_unit / 1024 / 1024;
    *used_mb  = (*total_mb) - si.freeram * si.mem_unit / 1024 / 1024;
}

/* ── Uptime ───────────────────────────────────────────────────────── */
static void uptime_str(char *buf, size_t n)
{
    struct sysinfo si;
    sysinfo(&si);
    long s = si.uptime;
    snprintf(buf, n, "%ldd %ldh %ldm", s/86400, (s%86400)/3600, (s%3600)/60);
}

/* ── Load average ─────────────────────────────────────────────────── */
static void load_avg(char *buf, size_t n)
{
    FILE *f = fopen("/proc/loadavg", "r");
    if (!f) { snprintf(buf, n, "N/A"); return; }
    double a, b, c;
    fscanf(f, "%lf %lf %lf", &a, &b, &c);
    fclose(f);
    snprintf(buf, n, "%.2f  %.2f  %.2f", a, b, c);
}

/* ── Network interfaces ───────────────────────────────────────────── */
static void print_net(void)
{
    struct ifaddrs *ifa, *p;
    if (getifaddrs(&ifa)) return;
    for (p = ifa; p; p = p->ifa_next) {
        if (!p->ifa_addr) continue;
        if (p->ifa_addr->sa_family != AF_INET) continue;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET,
                  &((struct sockaddr_in *)p->ifa_addr)->sin_addr,
                  ip, sizeof(ip));
        int up = (p->ifa_flags & IFF_UP) && (p->ifa_flags & IFF_RUNNING);
        printf("   %s%-12s%s ip: %-18s [%s%s%s]\n",
               BCYAN, p->ifa_name, RESET,
               ip,
               up ? BGREEN : RED,
               up ? "UP" : "DOWN",
               RESET);
    }
    freeifaddrs(ifa);
}

/* ── Hostname ─────────────────────────────────────────────────────── */
static void get_hostname(char *buf, size_t n)
{
    if (gethostname(buf, n)) snprintf(buf, n, "unknown");
}

/* ── Draw ─────────────────────────────────────────────────────────── */
static void draw(void)
{
    clear_screen();

    /* header */
    printf("%s", BGREEN);
    printf("  ╔══════════════════════════════════════════════════════╗\n");
    printf("  ║          GreenWayOS  │  System Engineering Toolkit   ║\n");
    printf("  ╚══════════════════════════════════════════════════════╝\n");
    printf("%s\n", RESET);

    /* hostname + time */
    char host[64]; get_hostname(host, sizeof(host));
    time_t t = time(NULL);
    struct tm *tm_ = localtime(&t);
    char tbuf[32];
    strftime(tbuf, sizeof(tbuf), "%Y-%m-%d  %H:%M:%S", tm_);

    printf("  %sHost:%s %-28s  %sTime:%s %s\n\n",
           BYELLOW, RESET, host, BYELLOW, RESET, tbuf);

    printf("  %sCreator:%s Sergey Karamyshev (Vorsess)\n\n",
           BYELLOW, RESET);

    /* uptime / load */
    char up[32], la[48];
    uptime_str(up, sizeof(up));
    load_avg(la, sizeof(la));
    printf("  %sUptime:%s %-24s  %sLoad (1/5/15):%s %s\n\n",
           CYAN, RESET, up, CYAN, RESET, la);

    /* CPU */
    double cpup = cpu_percent();
    printf("  %sCPU Usage%s\n  ", BYELLOW, RESET);
    const char *ccol = cpup < 50 ? BGREEN : cpup < 80 ? BYELLOW : RED;
    print_bar(cpup, ccol);
    printf("\n\n");

    /* RAM */
    unsigned long used, total;
    ram_info(&used, &total);
    double ramp = total ? 100.0 * used / total : 0;
    printf("  %sRAM Usage%s   %lu / %lu MB\n  ", BYELLOW, RESET, used, total);
    const char *rcol = ramp < 60 ? BGREEN : ramp < 85 ? BYELLOW : RED;
    print_bar(ramp, rcol);
    printf("\n\n");

    /* network */
    printf("  %sNetwork Interfaces%s\n", BYELLOW, RESET);
    print_net();

    /* footer */
    printf("\n  %s── Press Ctrl-C to exit  │  refresh every 2 seconds ─────%s\n",
           DIM, RESET);
}

static volatile int running = 1;

static void on_signal(int sig)
{
    (void)sig;
    running = 0;
}

int main(void)
{
    /* Register signal handlers to restore terminal on exit */
    signal(SIGINT,  on_signal);
    signal(SIGTERM, on_signal);

    /* hide cursor */
    printf("\033[?25l");
    /* alternate screen buffer */
    printf("\033[?1049h");
    fflush(stdout);

    while (running) {
        draw();
        sleep(2);
    }

    /* restore cursor and main screen buffer */
    printf("\033[?25h");
    printf("\033[?1049l");
    fflush(stdout);
    return 0;
}
