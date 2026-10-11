// PS4 platform layer for the OpenOrbis toolchain (https://github.com/OpenOrbis/OpenOrbis-PS4-Toolchain).
//
// NOT VERIFIED ON HARDWARE and not compiled here: the OpenOrbis headers were not available when this
// was written. The calls below follow the toolchain's sample projects, but names/signatures can differ
// between toolchain versions. If the build fails, compare each call with the matching sample under
// OpenOrbis' samples/ folder (video out, pad input, networking) and fix the line the compiler points at.
#include "platform.hpp"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <orbis/libkernel.h>
#include <orbis/Net.h>
#include <orbis/Pad.h>
#include <orbis/Sysmodule.h>
#include <orbis/UserService.h>
#include <orbis/VideoOut.h>

namespace {
constexpr int kW = 1920, kH = 1080;
constexpr size_t kFrameBytes = (size_t)kW * kH * 4;
constexpr int kBuffers = 2;
constexpr size_t kAlign = 2 * 1024 * 1024;

size_t align_up(size_t v) { return (v + kAlign - 1) & ~(kAlign - 1); }
} // namespace

struct Ps4Platform : Platform {
    int video = -1, pad = -1;
    uint8_t *mem = nullptr;
    int cur = 0;
    bool quit = false;
    char hostBuf[16] = {0};

    bool init(int &W, int &H) override {
        W = kW;
        H = kH;

        // --- video out: two XRGB/BGRA frame buffers in direct memory ---
        sceUserServiceInitialize(nullptr);
        video = sceVideoOutOpen(ORBIS_VIDEO_USER_MAIN, ORBIS_VIDEO_OUT_BUS_TYPE_MAIN, 0, nullptr);
        if (video < 0) return false;

        size_t total = align_up(kFrameBytes) * kBuffers;
        off_t phys = 0;
        if (sceKernelAllocateDirectMemory(0, sceKernelGetDirectMemorySize(), total, kAlign, 3, &phys) != 0) return false;
        void *addr = nullptr;
        if (sceKernelMapDirectMemory(&addr, total, 0x33, 0, phys, kAlign) != 0) return false;
        mem = (uint8_t *)addr;

        OrbisVideoOutBufferAttribute attr;
        sceVideoOutSetBufferAttribute(&attr, ORBIS_VIDEO_OUT_PIXEL_FORMAT_B8_G8_R8_A8_SRGB,
                                      ORBIS_VIDEO_OUT_TILING_MODE_LINEAR, ORBIS_VIDEO_OUT_ASPECT_RATIO_16_9, kW, kH, kW);
        void *addrs[kBuffers];
        for (int i = 0; i < kBuffers; i++) addrs[i] = mem + (size_t)i * align_up(kFrameBytes);
        if (sceVideoOutRegisterBuffers(video, 0, addrs, kBuffers, &attr) != 0) return false;
        sceVideoOutSetFlipRate(video, 0);

        // --- controller ---
        scePadInit();
        int user = 0;
        sceUserServiceGetInitialUser(&user);
        pad = scePadOpen(user, 0, 0, nullptr);

        // --- network ---
        sceSysmoduleLoadModule(ORBIS_SYSMODULE_NET);
        sceNetInit();

        // Optional fixed host: put the IP (e.g. 192.168.1.20) in this file to skip auto-discovery.
        FILE *f = fopen("/data/carracers/host.txt", "r");
        if (f) {
            if (fgets(hostBuf, sizeof hostBuf, f)) {
                for (char *c = hostBuf; *c; c++) if (*c == '\n' || *c == '\r') *c = 0;
            }
            fclose(f);
        }
        return true;
    }

    uint32_t *backbuffer() override { return (uint32_t *)(mem + (size_t)cur * align_up(kFrameBytes)); }

    void present() override {
        sceVideoOutSubmitFlip(video, cur, ORBIS_VIDEO_OUT_FLIP_MODE_VSYNC, 0);
        cur = (cur + 1) % kBuffers;
        sceKernelUsleep(14000);   // crude ~60 fps pacing
    }

    Input poll_input() override {
        Input in;
        OrbisPadData d;
        memset(&d, 0, sizeof d);
        if (pad >= 0 && scePadReadState(pad, &d) == 0) {
            in.throttle = d.analogButtons.r2 / 255.f;
            in.brake = d.analogButtons.l2 / 255.f;
            if (d.buttons & ORBIS_PAD_BUTTON_CROSS) in.throttle = 1.f;
            if (d.buttons & ORBIS_PAD_BUTTON_SQUARE) in.brake = 1.f;
            float sx = ((float)d.leftStick.x - 128.f) / 128.f;   // right = positive
            if (d.buttons & ORBIS_PAD_BUTTON_LEFT) sx = -1.f;
            if (d.buttons & ORBIS_PAD_BUTTON_RIGHT) sx = 1.f;
            if (sx > -0.12f && sx < 0.12f) sx = 0.f;
            in.steer = -sx;   // game uses positive = left
        }
        return in;
    }

    double now() override {
        return (double)sceKernelGetProcessTime() / 1e6;
    }

    int udp_open(int bind_port) override {
        int s = sceNetSocket("carracers", ORBIS_NET_AF_INET, ORBIS_NET_SOCK_DGRAM, 0);
        if (s < 0) return -1;
        int on = 1;
        sceNetSetsockopt(s, ORBIS_NET_SOL_SOCKET, ORBIS_NET_SO_NBIO, &on, sizeof on);
        sceNetSetsockopt(s, ORBIS_NET_SOL_SOCKET, ORBIS_NET_SO_REUSEADDR, &on, sizeof on);
        OrbisNetSockaddrIn a;
        memset(&a, 0, sizeof a);
        a.sin_len = sizeof a;
        a.sin_family = ORBIS_NET_AF_INET;
        a.sin_addr.s_addr = 0;
        a.sin_port = sceNetHtons((uint16_t)bind_port);
        if (sceNetBind(s, (OrbisNetSockaddr *)&a, sizeof a) < 0) { sceNetSocketClose(s); return -1; }
        return s;
    }

    int udp_send(int s, const char *ip, int port, const void *d, int n) override {
        OrbisNetSockaddrIn a;
        memset(&a, 0, sizeof a);
        a.sin_len = sizeof a;
        a.sin_family = ORBIS_NET_AF_INET;
        a.sin_port = sceNetHtons((uint16_t)port);
        sceNetInetPton(ORBIS_NET_AF_INET, ip, &a.sin_addr);
        return sceNetSendto(s, d, n, 0, (OrbisNetSockaddr *)&a, sizeof a);
    }

    int udp_recv(int s, void *buf, int cap, char *ip_out, int *port_out) override {
        OrbisNetSockaddrIn a;
        unsigned int l = sizeof a;
        int n = sceNetRecvfrom(s, buf, cap, 0, (OrbisNetSockaddr *)&a, &l);
        if (n <= 0) return 0;
        sceNetInetNtop(ORBIS_NET_AF_INET, &a.sin_addr, ip_out, 16);
        *port_out = sceNetNtohs(a.sin_port);
        return n;
    }

    const char *host_override() override { return hostBuf[0] ? hostBuf : nullptr; }
};

Platform *create_platform(int, char **) { return new Ps4Platform(); }
