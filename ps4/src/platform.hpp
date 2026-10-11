#pragma once
#include <stdint.h>

// Everything the game needs from the host system. Implemented by platform_pc.cpp
// (Linux, for testing) and platform_ps4.cpp (OpenOrbis SDK).

struct Input {
    float throttle = 0.f;  // 0..1
    float brake = 0.f;     // 0..1
    float steer = 0.f;     // -1..1, positive = left (same as the Godot game)
    bool quit = false;
};

struct Platform {
    virtual ~Platform() {}
    virtual bool init(int &w, int &h) = 0;   // returns the frame size to draw at
    virtual uint32_t *backbuffer() = 0;      // w*h pixels, 0x00RRGGBB
    virtual void present() = 0;              // show the frame (and pace to ~60 fps)
    virtual Input poll_input() = 0;
    virtual double now() = 0;                // seconds, monotonic
    virtual int udp_open(int bind_port) = 0; // non-blocking socket, bind_port 0 = any
    virtual int udp_send(int h, const char *ip, int port, const void *d, int n) = 0;
    virtual int udp_recv(int h, void *buf, int cap, char *ip_out16, int *port_out) = 0; // 0 if nothing
    virtual const char *host_override() = 0; // fixed host IP or nullptr to auto-discover
};

Platform *create_platform(int argc, char **argv);
