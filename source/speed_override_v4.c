/* Pepa Hacks — Speed Override v4
 * Overrides WallFollower planning speeds for SLAM-accurate speed changes.
 *
 * Build (requires Ubuntu 16.04 cross-compiler for glibc 2.19 compatibility):
 *   docker run --rm -v $(pwd):/src ubuntu:16.04 bash -c \
 *     'apt-get install -y gcc-arm-linux-gnueabihf && \
 *      arm-linux-gnueabihf-gcc -shared -fPIC -march=armv7-a -mfpu=vfpv3-d16 \
 *        -mfloat-abi=hard -O2 -ldl /src/source/speed_override_v4.c \
 *        -o /src/binaries/speed_override.so'
 *
 * HOW IT WORKS:
 *   Loaded via /etc/ld.so.preload, this library intercepts the WallFollower
 *   and GoStraight planning speed functions. When the navigation plans cleaning
 *   sweeps, it gets the speed from /mnt/data/speed.conf instead of the
 *   hardcoded 0.30 m/s factory value. SetSpeed passes through unchanged so
 *   SLAM stays accurate (nav plans AND executes at the same speed).
 *
 * SAFETY:
 *   - Hard ceiling: 0.80 m/s (LIDAR scan density drops below reliable at >1.0)
 *   - Factory fallback (0.30 m/s) if speed.conf is missing or unreadable
 *   - Each getter has its own static storage to avoid shared-state race conditions
 *   - SetSpeed passes through to the real function via dlsym(RTLD_NEXT)
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#define HARD_CEILING_MS 0.80f  /* absolute maximum — change with care */
#define FACTORY_DEFAULT 0.30f  /* safe fallback if speed.conf is missing */

static float read_speed_clamped(void) {
    FILE* f = fopen("/mnt/data/speed.conf", "r");
    if (!f) return FACTORY_DEFAULT;
    char buf[32]; buf[0] = 0;
    fgets(buf, sizeof(buf), f); fclose(f);
    float v;
    if      (!strncmp(buf, "slow",   4)) v = 0.20f;
    else if (!strncmp(buf, "normal", 6)) v = 0.30f;
    else if (!strncmp(buf, "fast",   4)) v = 0.45f;
    else if (!strncmp(buf, "turbo",  5)) v = 0.55f;
    else if (!strncmp(buf, "ultra",  5)) v = 0.65f;
    else if (!strncmp(buf, "max",    3)) v = 0.80f;
    else                                 return FACTORY_DEFAULT;
    /* enforce hard ceiling */
    return v < HARD_CEILING_MS ? v : HARD_CEILING_MS;
}

/* Separate static storage per getter — avoids shared-state race conditions */
static float g_robot_max,  g_robot_limit,
             g_gs_max,     g_gs_over,
             g_wf,         g_wf_tanos,
             g_wf_lt,      g_wf_st;

float* _ZN9NavConfig5Robot13Get_MAX_SPEEDEv(void* t)
    { g_robot_max   = read_speed_clamped(); return &g_robot_max; }
float* _ZN9NavConfig5Robot19Get_LIMIT_MAX_SPEEDEv(void* t)
    { g_robot_limit = read_speed_clamped(); return &g_robot_limit; }

float* _ZN9NavConfig10GoStraight13Get_MAX_SPEEDEv(void* t)
    { g_gs_max  = read_speed_clamped(); return &g_gs_max; }
float* _ZN9NavConfig10GoStraight14Get_OVER_SPEEDEv(void* t)
    /* OVER_SPEED is the boost threshold — keep it at or below the ceiling */
    { g_gs_over = read_speed_clamped(); return &g_gs_over; }

/* WallFollower variants — these drive the actual cleaning sweep speed */
float* _ZN9NavConfig12WallFollower9Get_SPEEDEv(void* t)
    { g_wf      = read_speed_clamped(); return &g_wf; }
float* _ZN9NavConfig17WallFollowerTANOS9Get_SPEEDEv(void* t)
    { g_wf_tanos = read_speed_clamped(); return &g_wf_tanos; }
float* _ZN9NavConfig22WallFollowerLightTouch9Get_SPEEDEv(void* t)
    { g_wf_lt   = read_speed_clamped(); return &g_wf_lt; }
float* _ZN9NavConfig14WallFollowerST9Get_SPEEDEv(void* t)
    { g_wf_st   = read_speed_clamped(); return &g_wf_st; }

/* RobotDevice runtime getters */
double _ZN11RobotDevice16GetLimitMaxSpeedEv(void* t)
    { return (double)read_speed_clamped(); }
double _ZN11RobotDevice11GetMaxSpeedEv(void* t)
    { return (double)read_speed_clamped(); }

/* SetSpeed: pass through unchanged — nav already planned at the correct speed */
void _ZN17NavRRLoaderPlugin8SetSpeedEdd(void* t, double lin, double ang) {
    static void (*orig)(void*, double, double) = 0;
    if (!orig) orig = (void(*)(void*,double,double))
        dlsym(RTLD_NEXT, "_ZN17NavRRLoaderPlugin8SetSpeedEdd");
    if (orig) orig(t, lin, ang);
}
void _ZN17NavRRLoaderPlugin13ForceSetSpeedEdd(void* t, double lin, double ang) {
    static void (*orig)(void*, double, double) = 0;
    if (!orig) orig = (void(*)(void*,double,double))
        dlsym(RTLD_NEXT, "_ZN17NavRRLoaderPlugin13ForceSetSpeedEdd");
    if (orig) orig(t, lin, ang);
}
