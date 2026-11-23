#pragma once
#include <cstdint>
#include <vector>
#include <array>
#include <string>

namespace minerva {
struct Block { uint16_t id{0}; };
struct Chunk {
    static constexpr int SizeX = 16, SizeY = 64, SizeZ = 16;
    std::vector<Block> blocks;
    Chunk();
    Block get(int x, int y, int z) const;
    void set(int x, int y, int z, uint16_t id);
};
struct MeshData {
    std::vector<float> positions;
    std::vector<float> normals;
    std::vector<uint32_t> indices;
};
class VoxelEngine {
public:
    Chunk generateFlatTestChunk(int chunkX, int chunkZ) const;
    MeshData buildVisibleFaceMesh(const Chunk& chunk) const;
};
}
