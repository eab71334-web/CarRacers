// Linux/PC platform layer: lets the portable game code be built and tested without a console.
// Usage: pc_client [--host IP] [--frames N] [--out frame.ppm] [--steer S]
#include "platform.hpp"
#include <arpa/inet.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <vector>

struct PcPlatform : Platform {
    int w = 1280, h = 720;
    std::vector<uint32_t> fb;
    char host[64] = {0};
    int maxFrames = 0, frame = 0;
    const char *out = nullptr;
    float steer = 0.25f;

    bool init(int &W, int &H) override {
        W = w;
        H = h;
        fb.assign((size_t)w * h, 0);
        return true;
    }
    uint32_t *backbuffer() override { return fb.data(); }
    void present() override {
        frame++;
        if (maxFrames && frame == maxFrames && out) {
            FILE *f = fopen(out, "wb");
            if (f) {
                fprintf(f, "P6\n%d %d\n255\n", w, h);
                for (uint32_t c : fb) {
                    unsigned char px[3] = {(unsigned char)(c >> 16), (unsigned char)(c >> 8), (unsigned char)c};
                    fwrite(px, 1, 3, f);
                }
                fclose(f);
            }
        }
        usleep(16000);
    }
    Input poll_input() override {
        Input in;
        in.throttle = 1.f;     // scripted: full throttle, constant left steer
        in.steer = steer;
        in.quit = maxFrames && frame >= maxFrames;
        return in;
    }
    double now() override {
        timespec ts;
        clock_gettime(CLOCK_MONOTONIC, &ts);
        return ts.tv_sec + ts.tv_nsec * 1e-9;
    }
    int udp_open(int bind_port) override {
        int s = socket(AF_INET, SOCK_DGRAM, 0);
        if (s < 0) return -1;
        int one = 1;
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
        fcntl(s, F_SETFL, O_NONBLOCK);
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_addr.s_addr = htonl(INADDR_ANY);
        a.sin_port = htons(bind_port);
        if (bind(s, (sockaddr *)&a, sizeof a) < 0) { close(s); return -1; }
        return s;
    }
    int udp_send(int s, const char *ip, int port, const void *d, int n) override {
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_port = htons(port);
        inet_pton(AF_INET, ip, &a.sin_addr);
        return (int)sendto(s, d, n, 0, (sockaddr *)&a, sizeof a);
    }
    int udp_recv(int s, void *buf, int cap, char *ip_out, int *port_out) override {
        sockaddr_in a{};
        socklen_t l = sizeof a;
        int n = (int)recvfrom(s, buf, cap, 0, (sockaddr *)&a, &l);
        if (n <= 0) return 0;
        inet_ntop(AF_INET, &a.sin_addr, ip_out, 16);
        *port_out = ntohs(a.sin_port);
        return n;
    }
    const char *host_override() override { return host[0] ? host : nullptr; }
};

Platform *create_platform(int argc, char **argv) {
    auto *p = new PcPlatform();
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--host") && i + 1 < argc) snprintf(p->host, sizeof p->host, "%s", argv[++i]);
        else if (!strcmp(argv[i], "--frames") && i + 1 < argc) p->maxFrames = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--out") && i + 1 < argc) p->out = argv[++i];
        else if (!strcmp(argv[i], "--steer") && i + 1 < argc) p->steer = (float)atof(argv[++i]);
    }
    return p;
}
