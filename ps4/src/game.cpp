#include "game.hpp"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace cr {

static const int kBridgePort = 24567;
static const int kDiscoveryPort = 24566;
static const float kPi = 3.14159265f;

static const uint32_t kColors[8] = {0xE5484D, 0x408CF2, 0xF2CC33, 0x4DCC73, 0xB366E6, 0xFF8C33, 0xE6E6E6, 0x33E6E6};

// 5x7 digit font (plus '/'), one row per byte, low 5 bits.
static const uint8_t kFont[11][7] = {
    {0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E}, {0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E},
    {0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F}, {0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E},
    {0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02}, {0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E},
    {0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E}, {0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08},
    {0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E}, {0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C},
    {0x01, 0x01, 0x02, 0x04, 0x08, 0x10, 0x10}};

bool Game::init() {
    if (!p_.init(W_, H_)) return false;
    scale_ = (float)H_ / 200.f;   // whole track (diameter 180 m) fits the screen height
    cx_ = W_ / 2.f;
    cy_ = H_ / 2.f;
    build_background();
    sock_ = p_.udp_open(0);
    disc_ = p_.udp_open(kDiscoveryPort);
    const char *ho = p_.host_override();
    if (ho && *ho) {
        snprintf(hostIp_, sizeof hostIp_, "%s", ho);
        haveHost_ = true;
    }
    spawn(0);
    return sock_ >= 0;
}

void Game::spawn(int slot) {
    float lane = 58.f + (float)(slot % 4) * 7.f;
    float row = (float)(slot / 4) * 8.f;
    x = lane;
    z = -row;
    yaw = kPi;
    speed = 0;
    lap = 0;
    nextSector_ = 1;
    finished_ = false;
    raceTime_ = 0;
}

void Game::build_background() {
    bg_.assign((size_t)W_ * H_, 0x2E7D32);
    for (int py = 0; py < H_; py++) {
        for (int px = 0; px < W_; px++) {
            float wx = ((float)px - cx_) / scale_, wz = ((float)py - cy_) / scale_;
            float r = sqrtf(wx * wx + wz * wz);
            uint32_t c = 0x2E7D32;
            if (r >= kInner - 0.5f && r <= kOuter + 0.5f) {
                c = 0x38383C;
                if (r < kInner + 0.5f || r > kOuter - 0.5f) c = 0xD9D9D9;     // walls
                else if (fabsf(wz) < 0.8f && wx > 0) c = 0xFFFFFF;              // start line
            }
            bg_[(size_t)py * W_ + px] = c;
        }
    }
}

void Game::step(const Input &in, float dt) {
    const float kMax = 38.f, kAccel = 18.f, kBrake = 30.f, kFric = 8.f, kSteer = 2.2f;
    float axis = in.throttle - in.brake;
    auto toward = [](float v, float t, float d) { return v < t ? fminf(v + d, t) : fmaxf(v - d, t); };
    if (axis > 0.f) speed = toward(speed, kMax, kAccel * dt);
    else if (axis < 0.f) speed = toward(speed, -kMax * 0.3f, kBrake * dt);
    else speed = toward(speed, 0.f, kFric * dt);

    yaw += in.steer * kSteer * dt * fmaxf(-1.f, fminf(1.f, speed / 10.f));
    x += -sinf(yaw) * speed * dt;
    z += -cosf(yaw) * speed * dt;

    // Walls: push back inside the track and lose speed.
    float r = sqrtf(x * x + z * z);
    const float lo = kInner + 1.6f, hi = kOuter - 1.6f;
    if (r < lo || r > hi) {
        float t = (r < lo ? lo : hi) / (r > 0.001f ? r : 1.f);
        x *= t;
        z *= t;
        speed *= 0.9f;
    }

    // Lap counting: four sectors around the loop, in driving direction.
    float a = atan2f(z, x);
    if (a < 0) a += 2.f * kPi;
    int sector = (int)(a / (kPi / 2.f)) % 4;
    if (!finished_ && sector == nextSector_) {
        nextSector_ = (nextSector_ + 1) % 4;
        if (sector == 0 && ++lap >= kLaps) finished_ = true;
    }
    if (!finished_) raceTime_ += dt;
}

void Game::handle_packet(const char *d, int n, double now) {
    char buf[1500];
    if (n <= 0 || n >= (int)sizeof buf) return;
    memcpy(buf, d, n);
    buf[n] = 0;
    if (strncmp(buf, "CR1|A|", 6) == 0) {
        int id = atoi(buf + 6);
        if (myId != id) {
            myId = id;
            spawn((id - 1000) & 7);
        }
        lastWorld_ = now;
    } else if (strncmp(buf, "CR1|W|", 6) == 0) {
        lastWorld_ = now;
        const char *s = buf + 6;
        while (*s) {
            int id;
            float rx, ry, rz, ryaw, rsp;
            if (sscanf(s, "%d,%f,%f,%f,%f,%f", &id, &rx, &ry, &rz, &ryaw, &rsp) != 6) break;
            RemoteCar *slot = nullptr;
            for (auto &c : rc_) if (c.alive && c.id == id) { slot = &c; break; }
            if (!slot) {
                for (auto &c : rc_) if (!c.alive) { slot = &c; break; }
                if (slot) { slot->alive = true; slot->id = id; slot->x = rx; slot->z = rz; slot->yaw = ryaw; }
            }
            if (slot) { slot->tx = rx; slot->tz = rz; slot->tyaw = ryaw; slot->speed = rsp; slot->last = now; }
            const char *next = strchr(s, ';');
            if (!next) break;
            s = next + 1;
        }
    }
}

void Game::networking(double now) {
    char buf[1500], ip[16];
    int port;
    int n;
    while (sock_ >= 0 && (n = p_.udp_recv(sock_, buf, sizeof buf - 1, ip, &port)) > 0) handle_packet(buf, n, now);

    // Find the host from its discovery broadcast.
    while (!haveHost_ && disc_ >= 0 && (n = p_.udp_recv(disc_, buf, sizeof buf - 1, ip, &port)) > 0) {
        buf[n] = 0;
        if (strncmp(buf, "CARRACERS1|", 11) == 0) {
            snprintf(hostIp_, sizeof hostIp_, "%s", ip);
            haveHost_ = true;
        }
    }
    if (!haveHost_) return;

    if (myId >= 0 && now - lastWorld_ > 5.0) myId = -1;   // host went away: rejoin
    if (myId < 0) {
        if (now - lastJoin_ >= 1.0) {
            lastJoin_ = now;
            const char *j = "CR1|J|PS4";
            p_.udp_send(sock_, hostIp_, kBridgePort, j, (int)strlen(j));
        }
    } else if (now - lastSend_ >= 1.0 / 30.0) {
        lastSend_ = now;
        char m[160];
        int len = snprintf(m, sizeof m, "CR1|S|%.2f|0.30|%.2f|%.3f|%.2f", x, z, yaw, speed);
        p_.udp_send(sock_, hostIp_, kBridgePort, m, len);
    }
    for (auto &c : rc_) {
        if (!c.alive) continue;
        if (now - c.last > 3.0) { c.alive = false; continue; }
        c.x += (c.tx - c.x) * 0.3f;
        c.z += (c.tz - c.z) * 0.3f;
        float d = c.tyaw - c.yaw;
        while (d > kPi) d -= 2 * kPi;
        while (d < -kPi) d += 2 * kPi;
        c.yaw += d * 0.3f;
    }
}

void Game::fill_rect(int x0, int y0, int x1, int y1, uint32_t c) {
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > W_) x1 = W_;
    if (y1 > H_) y1 = H_;
    uint32_t *fb = p_.backbuffer();
    for (int y = y0; y < y1; y++)
        for (int xx = x0; xx < x1; xx++) fb[(size_t)y * W_ + xx] = c;
}

void Game::draw_car(float wx, float wz, float wyaw, uint32_t c) {
    const float hl = 2.6f, hw = 1.4f;   // drawn a bit larger than the real car so it is visible
    float sx = cx_ + wx * scale_, sy = cy_ + wz * scale_;
    float fx = -sinf(wyaw), fz = -cosf(wyaw);
    float rx = -fz, rz = fx;
    int rad = (int)((hl + hw) * scale_) + 2;
    uint32_t *fb = p_.backbuffer();
    for (int py = (int)sy - rad; py <= (int)sy + rad; py++) {
        if (py < 0 || py >= H_) continue;
        for (int px = (int)sx - rad; px <= (int)sx + rad; px++) {
            if (px < 0 || px >= W_) continue;
            float dx = ((float)px - sx) / scale_, dz = ((float)py - sy) / scale_;
            float along = dx * fx + dz * fz, side = dx * rx + dz * rz;
            if (fabsf(along) < hl && fabsf(side) < hw) fb[(size_t)py * W_ + px] = along > hl * 0.45f ? 0xFFFFFF : c;
        }
    }
}

void Game::draw_text(int x0, int y0, const char *s, int px, uint32_t c) {
    for (; *s; s++, x0 += 6 * px) {
        int g = (*s >= '0' && *s <= '9') ? *s - '0' : (*s == '/' ? 10 : -1);
        if (g < 0) continue;
        for (int row = 0; row < 7; row++)
            for (int col = 0; col < 5; col++)
                if (kFont[g][row] & (1 << (4 - col))) fill_rect(x0 + col * px, y0 + row * px, x0 + (col + 1) * px, y0 + (row + 1) * px, c);
    }
}

void Game::render() {
    uint32_t *fb = p_.backbuffer();
    memcpy(fb, bg_.data(), bg_.size() * sizeof(uint32_t));
    for (auto &c : rc_)
        if (c.alive) draw_car(c.x, c.z, c.yaw, kColors[c.id & 7]);
    draw_car(x, z, yaw, kColors[myId >= 0 ? (myId - 1000) & 7 : 0]);

    char t[32];
    snprintf(t, sizeof t, "%d/%d", lap + 1 > kLaps ? kLaps : lap + 1, kLaps);
    draw_text(30, 30, t, 8, 0xFFFFFF);
    snprintf(t, sizeof t, "%d", (int)(fabsf(speed) * 3.6f));
    draw_text(30, 110, t, 8, 0xFFFF66);
    fill_rect(30, H_ - 60, 30 + (int)(fabsf(speed) / 38.f * 300.f), H_ - 30, 0xE5484D);
    // Connection indicator: red = looking for host, yellow = joining, green = in race.
    fill_rect(W_ - 70, 30, W_ - 30, 70, !haveHost_ ? 0xE5484D : (myId < 0 ? 0xF2CC33 : 0x4DCC73));
    if (finished_) fill_rect(W_ / 2 - 200, 30, W_ / 2 + 200, 60, 0xFFD700);
}

void Game::run() {
    double last = p_.now();
    for (;;) {
        Input in = p_.poll_input();
        if (in.quit) break;
        double now = p_.now();
        float dt = (float)(now - last);
        last = now;
        if (dt < 0.001f) dt = 0.001f;
        if (dt > 0.05f) dt = 0.05f;
        step(in, dt);
        networking(now);
        render();
        p_.present();
    }
}

} // namespace cr
