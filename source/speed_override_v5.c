#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static float cached_speed = 0.30f;
static long  cached_mtime = 0;

static float read_speed_clamped(void) {
    struct stat st;
    if (stat("/mnt/data/speed.conf", &st) == 0 && (long)st.st_mtime != cached_mtime) {
        cached_mtime = (long)st.st_mtime;
        FILE* f = fopen("/mnt/data/speed.conf", "r");
        if (f) {
            char buf[32]; buf[0]=0;
            fgets(buf, sizeof(buf), f); fclose(f);
            float v = 0.30f;
            if      (!strncmp(buf,"slow",  4)) v=0.20f;
            else if (!strncmp(buf,"normal",6)) v=0.30f;
            else if (!strncmp(buf,"fast",  4)) v=0.45f;
            else if (!strncmp(buf,"turbo", 5)) v=0.55f;
            else if (!strncmp(buf,"ultra", 5)) v=0.65f;
            else if (!strncmp(buf,"max",   3)) v=0.80f;
            cached_speed = v < 0.80f ? v : 0.80f;
        }
    }
    return cached_speed;
}
static double gd(void) { return (double)read_speed_clamped(); }
static float g1,g2,g3,g4,g5,g6,g7,g8;
float* _ZN9NavConfig5Robot13Get_MAX_SPEEDEv(void* t)        { g1=read_speed_clamped(); return &g1; }
float* _ZN9NavConfig5Robot19Get_LIMIT_MAX_SPEEDEv(void* t)  { g2=read_speed_clamped(); return &g2; }
float* _ZN9NavConfig10GoStraight13Get_MAX_SPEEDEv(void* t)  { g3=read_speed_clamped(); return &g3; }
float* _ZN9NavConfig10GoStraight14Get_OVER_SPEEDEv(void* t) { g4=read_speed_clamped(); return &g4; }
float* _ZN9NavConfig12WallFollower9Get_SPEEDEv(void* t)           { g5=read_speed_clamped(); return &g5; }
float* _ZN9NavConfig17WallFollowerTANOS9Get_SPEEDEv(void* t)      { g6=read_speed_clamped(); return &g6; }
float* _ZN9NavConfig22WallFollowerLightTouch9Get_SPEEDEv(void* t) { g7=read_speed_clamped(); return &g7; }
float* _ZN9NavConfig14WallFollowerST9Get_SPEEDEv(void* t)         { g8=read_speed_clamped(); return &g8; }
double _ZN11RobotDevice16GetLimitMaxSpeedEv(void* t) { return gd(); }
double _ZN11RobotDevice11GetMaxSpeedEv(void* t)      { return gd(); }
void _ZN17NavRRLoaderPlugin8SetSpeedEdd(void* t, double l, double a) {
    static void (*o)(void*,double,double)=0;
    if(!o) o=(void(*)(void*,double,double))dlsym(RTLD_NEXT,"_ZN17NavRRLoaderPlugin8SetSpeedEdd");
    if(o) o(t,l,a);
}
void _ZN17NavRRLoaderPlugin13ForceSetSpeedEdd(void* t, double l, double a) {
    static void (*o)(void*,double,double)=0;
    if(!o) o=(void(*)(void*,double,double))dlsym(RTLD_NEXT,"_ZN17NavRRLoaderPlugin13ForceSetSpeedEdd");
    if(o) o(t,l,a);
}
