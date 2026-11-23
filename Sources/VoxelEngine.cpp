#include "VoxelEngine.hpp"
#include <algorithm>

namespace minerva {
static size_t indexOf(int x, int y, int z) {
    return static_cast<size_t>((y * Chunk::SizeZ + z) * Chunk::SizeX + x);
}
Chunk::Chunk() : blocks(static_cast<size_t>(SizeX * SizeY * SizeZ)) {}
Block Chunk::get(int x, int y, int z) const {
    if (x < 0 || x >= SizeX || y < 0 || y >= SizeY || z < 0 || z >= SizeZ) return {};
    return blocks[indexOf(x, y, z)];
}
void Chunk::set(int x, int y, int z, uint16_t id) {
    if (x < 0 || x >= SizeX || y < 0 || y >= SizeY || z < 0 || z >= SizeZ) return;
    blocks[indexOf(x, y, z)].id = id;
}
Chunk VoxelEngine::generateFlatTestChunk(int chunkX, int chunkZ) const {
    (void)chunkX; (void)chunkZ;
    Chunk chunk;
    // Small deterministic test terrain. Replace with the production world generator
    // after the Swift/C++ bridge has been validated in the app.
    for (int x = 0; x < Chunk::SizeX; ++x)
        for (int z = 0; z < Chunk::SizeZ; ++z) {
            chunk.set(x, 0, z, 3); chunk.set(x, 1, z, 2); chunk.set(x, 2, z, 1);
        }
    return chunk;
}
MeshData VoxelEngine::buildVisibleFaceMesh(const Chunk& chunk) const {
    MeshData mesh;
    // CPU-side face culling only. Mesh upload/rendering is intentionally left to
    // the renderer integration step, not performed on the UI thread.
    const int dirs[6][3] = {{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
    const float corners[6][4][3] = {
        {{1,0,0},{1,1,0},{1,1,1},{1,0,1}}, {{0,0,1},{0,1,1},{0,1,0},{0,0,0}},
        {{0,1,1},{1,1,1},{1,1,0},{0,1,0}}, {{0,0,0},{1,0,0},{1,0,1},{0,0,1}},
        {{1,0,1},{1,1,1},{0,1,1},{0,0,1}}, {{0,0,0},{0,1,0},{1,1,0},{1,0,0}}
    };
    for (int y=0; y<Chunk::SizeY; ++y) for (int z=0; z<Chunk::SizeZ; ++z) for (int x=0; x<Chunk::SizeX; ++x) {
        if (chunk.get(x,y,z).id == 0) continue;
        for (int f=0; f<6; ++f) {
            if (chunk.get(x+dirs[f][0], y+dirs[f][1], z+dirs[f][2]).id != 0) continue;
            const uint32_t base = static_cast<uint32_t>(mesh.positions.size()/3);
            for (int c=0; c<4; ++c) {
                mesh.positions.insert(mesh.positions.end(), {x+corners[f][c][0], y+corners[f][c][1], z+corners[f][c][2]});
                mesh.normals.insert(mesh.normals.end(), {static_cast<float>(dirs[f][0]), static_cast<float>(dirs[f][1]), static_cast<float>(dirs[f][2])});
            }
            mesh.indices.insert(mesh.indices.end(), {base,base+1,base+2,base,base+2,base+3});
        }
    }
    return mesh;
}
}
