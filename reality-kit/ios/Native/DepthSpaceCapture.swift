import ARKit
import Foundation

// A visual scan made from camera-aligned LiDAR depth frames. Unlike ARKit's
// scene mesh, these triangles retain the camera pixels that saw each surface.
@available(iOS 18.0, *)
enum DepthSpaceCapture {
    struct Frame {
        let width: Int
        let height: Int
        let depth: [Float]
        let rgba: [UInt8]
        let intrinsics: simd_float3x3
        let cameraTransform: simd_float4x4
    }

    struct Result {
        let positions: [SIMD3<Float>]
        let colors: [SIMD4<Float>]
    }

    private struct DepthVertex {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
        let depth: Float
        let voxel: SIMD3<Int32>
    }

    private struct VoxelAccumulator {
        var position: SIMD3<Float>
        var color: SIMD3<Float>
        var count: Float
    }

    private struct Triangle {
        let a: SIMD3<Int32>
        let b: SIMD3<Int32>
        let c: SIMD3<Int32>
    }

    private struct TriangleKey: Hashable {
        let a: SIMD3<Int32>
        let b: SIMD3<Int32>
        let c: SIMD3<Int32>
    }

    static func capture(_ frame: ARFrame) -> Frame? {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let depthMap = depthData.depthMap
        guard
              CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPlaneCount(frame.capturedImage) >= 2 else { return nil }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }
        let color = frame.capturedImage
        let confidence = depthData.confidenceMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(color, .readOnly)
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer {
            if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
            CVPixelBufferUnlockBaseAddress(color, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let yBase = CVPixelBufferGetBaseAddressOfPlane(color, 0),
              let cbcrBase = CVPixelBufferGetBaseAddressOfPlane(color, 1) else { return nil }
        let yWidth = CVPixelBufferGetWidthOfPlane(color, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(color, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(color, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(color, 1)
        let depthStride = CVPixelBufferGetBytesPerRow(depthMap)
        let confidenceStride = confidence.map(CVPixelBufferGetBytesPerRow)
        let confidenceBytes = confidence.flatMap(CVPixelBufferGetBaseAddress)?
            .assumingMemoryBound(to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(color, 0)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(color, 1)
        let depthBytes = UnsafeRawPointer(depthBase)
        let luma = yBase.assumingMemoryBound(to: UInt8.self)
        let chroma = cbcrBase.assumingMemoryBound(to: UInt8.self)
        var depths = [Float](repeating: 0, count: width * height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        func byte(_ value: Float) -> UInt8 {
            UInt8(min(max(value.rounded(), 0), 255))
        }
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let depthValue = depthBytes.advanced(by: y * depthStride + x * 4)
                    .loadUnaligned(as: Float.self)
                let confidenceValue = confidenceBytes.map { $0[y * (confidenceStride ?? width) + x] } ?? 2
                depths[index] = confidenceValue == 0 ? 0 : depthValue
                let colorX = min(yWidth - 1, x * yWidth / width)
                let colorY = min(yHeight - 1, y * yHeight / height)
                let chromaX = min(chromaWidth - 1, colorX / 2)
                let chromaY = min(chromaHeight - 1, colorY / 2)
                let yy = Float(luma[colorY * yStride + colorX])
                let uvOffset = chromaY * chromaStride + chromaX * 2
                let cb = Float(chroma[uvOffset]) - 128
                let cr = Float(chroma[uvOffset + 1]) - 128
                let pixel = index * 4
                rgba[pixel] = byte(yy + 1.5748 * cr)
                rgba[pixel + 1] = byte(yy - 0.1873 * cb - 0.4681 * cr)
                rgba[pixel + 2] = byte(yy + 1.8556 * cb)
                rgba[pixel + 3] = 255
            }
        }
        var intrinsics = frame.camera.intrinsics
        intrinsics.columns.0.x *= Float(width) / Float(yWidth)
        intrinsics.columns.1.y *= Float(height) / Float(yHeight)
        intrinsics.columns.2.x *= Float(width) / Float(yWidth)
        intrinsics.columns.2.y *= Float(height) / Float(yHeight)
        return Frame(width: width, height: height, depth: depths, rgba: rgba,
                     intrinsics: intrinsics, cameraTransform: frame.camera.transform)
    }

    static func build(from frames: [Frame], highDetail: Bool) throws -> Result {
        guard !frames.isEmpty else { throw ObjToGlbError.noTriangles }
        var voxels: [SIMD3<Int32>: VoxelAccumulator] = [:]
        var triangles: [Triangle] = []
        var seen = Set<TriangleKey>()
        let voxelSize: Float = highDetail ? 0.018 : 0.03
        let faceBudget = highDetail ? 240_000 : 180_000
        let frameBudget = max(1, faceBudget / frames.count)
        var frameFaces = 0
        func comesBefore(_ left: SIMD3<Int32>, _ right: SIMD3<Int32>) -> Bool {
            if left.x != right.x { return left.x < right.x }
            if left.y != right.y { return left.y < right.y }
            return left.z < right.z
        }
        func include(_ vertex: DepthVertex) {
            if var current = voxels[vertex.voxel] {
                current.position += vertex.position
                current.color += vertex.color
                current.count += 1
                voxels[vertex.voxel] = current
            } else {
                voxels[vertex.voxel] = VoxelAccumulator(position: vertex.position,
                                                         color: vertex.color, count: 1)
            }
        }
        func append(_ a: DepthVertex, _ b: DepthVertex, _ c: DepthVertex) {
            guard frameFaces < frameBudget else { return }
            guard a.voxel != b.voxel, b.voxel != c.voxel,
                  c.voxel != a.voxel else { return }
            let sorted = [a.voxel, b.voxel, c.voxel].sorted(by: comesBefore)
            let key = TriangleKey(a: sorted[0], b: sorted[1], c: sorted[2])
            guard seen.insert(key).inserted else { return }
            include(a)
            include(b)
            include(c)
            triangles.append(Triangle(a: a.voxel, b: b.voxel, c: c.voxel))
            frameFaces += 1
        }
        var positions: [SIMD3<Float>] = []
        let step = highDetail ? 1 : 2
        for frame in frames {
            frameFaces = 0
            func vertex(_ x: Int, _ y: Int) -> DepthVertex? {
                let depth = frame.depth[y * frame.width + x]
                guard depth.isFinite, depth > 0.2, depth < 5 else { return nil }
                let fx = frame.intrinsics.columns.0.x
                let fy = frame.intrinsics.columns.1.y
                let cx = frame.intrinsics.columns.2.x
                let cy = frame.intrinsics.columns.2.y
                let local = SIMD4<Float>((Float(x) - cx) / fx * depth,
                                         -(Float(y) - cy) / fy * depth,
                                         -depth, 1)
                let world = frame.cameraTransform * local
                let position = SIMD3<Float>(world.x, world.y, world.z)
                let voxel = SIMD3<Int32>(Int32((position.x / voxelSize).rounded()),
                                          Int32((position.y / voxelSize).rounded()),
                                          Int32((position.z / voxelSize).rounded()))
                let offset = (y * frame.width + x) * 4
                let color = SIMD3<Float>(Float(frame.rgba[offset]) / 255,
                                         Float(frame.rgba[offset + 1]) / 255,
                                         Float(frame.rgba[offset + 2]) / 255)
                return DepthVertex(position: position, color: color,
                                   depth: depth, voxel: voxel)
            }
            for y in stride(from: 0, to: frame.height - step, by: step) {
                for x in stride(from: 0, to: frame.width - step, by: step) {
                    guard let a = vertex(x, y),
                          let b = vertex(x + step, y),
                          let c = vertex(x, y + step),
                          let d = vertex(x + step, y + step) else { continue }
                    let nearest = min(a.depth, b.depth, c.depth, d.depth)
                    guard max(a.depth, b.depth, c.depth, d.depth) - nearest
                            < max(0.08, nearest * 0.06) else { continue }
                    append(a, c, b)
                    append(b, c, d)
                }
            }
        }
        guard !triangles.isEmpty else { throw ObjToGlbError.noTriangles }
        var colors: [SIMD4<Float>] = []
        positions.reserveCapacity(triangles.count * 3)
        colors.reserveCapacity(triangles.count * 3)
        for triangle in triangles {
            for key in [triangle.a, triangle.b, triangle.c] {
                guard let voxel = voxels[key] else { continue }
                positions.append(voxel.position / voxel.count)
                let rgb = voxel.color / voxel.count
                colors.append(SIMD4<Float>(rgb.x, rgb.y, rgb.z, 1))
            }
        }
        return Result(positions: positions, colors: colors)
    }
}
