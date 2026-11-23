#import "MVMinervaEngine.h"
#include "VoxelEngine.hpp"
@implementation MVMinervaEngine {
    minerva::VoxelEngine _engine;
}
- (NSInteger)generateTestChunkAndReturnVisibleFaceCountAtX:(NSInteger)x z:(NSInteger)z {
    auto chunk = _engine.generateFlatTestChunk((int)x, (int)z);
    auto mesh = _engine.buildVisibleFaceMesh(chunk);
    return (NSInteger)(mesh.indices.size() / 6);
}
- (NSString *)engineVersion { return @"Minerva C++ engine scaffold 0.1"; }
@end
