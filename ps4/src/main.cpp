#include "game.hpp"
#include <stdio.h>

int main(int argc, char **argv) {
    Platform *p = create_platform(argc, argv);
    if (!p) return 1;
    cr::Game game(*p);
    if (!game.init()) return 2;
    game.run();
    delete p;
    return 0;
}
