/* Pepa Hacks — ALSA PCM Player
 * Reads raw PCM (44100 Hz, stereo, S16_LE) from stdin and plays via ALSA.
 * Build: arm-linux-gnu-gcc -shared (via stubs) or Ubuntu 16.04 arm cross-compiler
 * Usage: mpg123_bin -s - stream_url | alsa_play
 */
typedef void snd_pcm_t;
typedef long snd_pcm_sframes_t;
typedef unsigned long snd_pcm_uframes_t;

#define SND_PCM_STREAM_PLAYBACK 0
#define SND_PCM_FORMAT_S16_LE   2
#define SND_PCM_ACCESS_RW_INTERLEAVED 3

extern int snd_pcm_open(snd_pcm_t**, const char*, int, int);
extern int snd_pcm_set_params(snd_pcm_t*, int, int, unsigned int, unsigned int, int, unsigned int);
extern snd_pcm_sframes_t snd_pcm_writei(snd_pcm_t*, const void*, snd_pcm_uframes_t);
extern int snd_pcm_recover(snd_pcm_t*, int, int);
extern int snd_pcm_drain(snd_pcm_t*);
extern int snd_pcm_close(snd_pcm_t*);

static long do_read(int fd, void* buf, long len) {
    register int   r0 __asm__("r0") = fd;
    register void* r1 __asm__("r1") = buf;
    register long  r2 __asm__("r2") = len;
    register long  r7 __asm__("r7") = 3; /* __NR_read */
    __asm__ volatile("svc #0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r7) : "memory", "cc");
    return r0;
}

static void do_exit(int code) {
    register int r0 __asm__("r0") = code;
    register int r7 __asm__("r7") = 1; /* __NR_exit */
    __asm__ volatile("svc #0" : : "r"(r0), "r"(r7));
}

void _start(void) {
    snd_pcm_t *pcm = 0;
    if (snd_pcm_open(&pcm, "plughw:0,0", SND_PCM_STREAM_PLAYBACK, 0) < 0)
        { do_exit(1); return; }
    if (snd_pcm_set_params(pcm, SND_PCM_FORMAT_S16_LE,
                            SND_PCM_ACCESS_RW_INTERLEAVED, 2, 44100, 1, 500000) < 0)
        { snd_pcm_close(pcm); do_exit(1); return; }
    unsigned char buf[8192];
    long n;
    while ((n = do_read(0, buf, 8192)) > 0) {
        snd_pcm_sframes_t r = snd_pcm_writei(pcm, buf, (snd_pcm_uframes_t)(n / 4));
        if (r < 0) snd_pcm_recover(pcm, (int)r, 0);
    }
    snd_pcm_drain(pcm);
    snd_pcm_close(pcm);
    do_exit(0);
}
