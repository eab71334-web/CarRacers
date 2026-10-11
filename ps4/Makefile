CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra

pc_client: src/main.cpp src/game.cpp src/platform_pc.cpp src/game.hpp src/platform.hpp
	$(CXX) $(CXXFLAGS) src/main.cpp src/game.cpp src/platform_pc.cpp -o pc_client -lm

clean:
	rm -f pc_client
