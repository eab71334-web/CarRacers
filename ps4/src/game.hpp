#pragma once
#include "platform.hpp"
#include <vector>

namespace cr {

constexpr float kInner = 50.f, kOuter = 90.f, kCenter = 70.f;
constexpr int kLaps = 3;
constexpr int kMaxRemote = 8;

struct RemoteCar {
    bool alive = false;
    int id = 0;
    float x = 0, z = 0, yaw = 0, speed = 0;     // displayed (smoothed)
    float tx = 0, tz = 0, tyaw = 0;             // latest network value
    double last = 0;
};

class Game {
public:
    explicit Game(Platform &p) : p_(p) {}
    bool init();
    void run();

    // Exposed so tests can inspect them.
    float x = 0, z = 0, yaw = 0, speed = 0;
    int lap = 0;
    int myId = -1;

private:
    void step(const Input &in, float dt);
    void networking(double now);
    void handle_packet(const char *data, int n, double now);
    void render();
    void build_background();
    void fill_rect(int x0, int y0, int x1, int y1, uint32_t c);
    void draw_car(float wx, float wz, float wyaw, uint32_t c);
    void draw_text(int x, int y, const char *s, int px, uint32_t c);
    void spawn(int slot);

    Platform &p_;
    int W_ = 0, H_ = 0;
    float scale_ = 1.f, cx_ = 0, cy_ = 0;
    std::vector<uint32_t> bg_;

    int nextSector_ = 1;
    bool finished_ = false;
    double raceTime_ = 0;

    int sock_ = -1, disc_ = -1;
    char hostIp_[16] = {0};
    bool haveHost_ = false;
    double lastJoin_ = -10, lastSend_ = 0, lastWorld_ = 0;
    RemoteCar rc_[kMaxRemote];
};

} // namespace cr
