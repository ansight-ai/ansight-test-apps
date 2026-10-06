import Foundation

enum ObjToGlbError: LocalizedError {
    case noObj
    case noTriangles
    case invalidFace(String)
    case unsupportedTexture(String)

    var errorDescription: String? {
        switch self {
        case .noObj: return "Object Capture did not create an OBJ file."
        case .noTriangles: return "The OBJ contains no triangles."
        case .invalidFace(let value): return "Invalid OBJ face: \(value)"
        case .unsupportedTexture(let value): return "Unsupported OBJ texture: \(value)"
        }
    }
}

enum ObjToGlb {
    static func writeUntexturedTriangles(_ positions: [SIMD3<Float>],
                                         colors: [SIMD4<Float>]? = nil,
                                         destination: URL) throws {
        try writeTriangles(positions, uvs: Array(repeating: SIMD2<Float>(0, 0), count: positions.count),
                           texture: nil, colors: colors, useMipmaps: false,
                           destination: destination)
    }

    static func writeSceneTriangles(_ positions: [SIMD3<Float>], uvs: [SIMD2<Float>],
                                    texturePNG: Data, destination: URL) throws {
        try writeTriangles(positions, uvs: uvs, texture: (texturePNG, "image/png"),
                           colors: nil, useMipmaps: false, destination: destination)
    }

    private static func writeTriangles(_ positions: [SIMD3<Float>], uvs: [SIMD2<Float>],
                                       texture: (Data, String)?, colors: [SIMD4<Float>]?,
                                       useMipmaps: Bool,
                                       destination: URL) throws {
        guard !positions.isEmpty, positions.count.isMultiple(of: 3) else {
            throw ObjToGlbError.noTriangles
        }
        guard uvs.count == positions.count,
              colors == nil || colors?.count == positions.count else {
            throw ObjToGlbError.noTriangles
        }
        var normals: [SIMD3<Float>] = []
        normals.reserveCapacity(positions.count)
        for index in stride(from: 0, to: positions.count, by: 3) {
            let ab = positions[index + 1] - positions[index]
            let ac = positions[index + 2] - positions[index]
            let cross = SIMD3<Float>(ab.y * ac.z - ab.z * ac.y,
                                     ab.z * ac.x - ab.x * ac.z,
                                     ab.x * ac.y - ab.y * ac.x)
            let magnitude = (cross.x * cross.x + cross.y * cross.y + cross.z * cross.z).squareRoot()
            let normal = magnitude > 0 ? cross / magnitude : SIMD3<Float>(0, 1, 0)
            normals.append(contentsOf: [normal, normal, normal])
        }
        try writeGlb(positions: positions, normals: normals,
                     uvs: uvs, texture: texture, colors: colors,
                     useMipmaps: useMipmaps, destination: destination)
    }

    private struct FaceVertex {
        let position: Int
        let uv: Int?
        let normal: Int?
    }

    static func convert(objDirectory: URL, destination: URL) throws {
        let objURL = FileManager.default.enumerator(at: objDirectory,
                                                         includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.pathExtension.lowercased() == "obj" }
        guard let objURL else { throw ObjToGlbError.noObj }
        let text = try String(contentsOf: objURL, encoding: .utf8)
        var positions: [SIMD3<Float>] = []
        var sourceNormals: [SIMD3<Float>] = []
        var sourceUVs: [SIMD2<Float>] = []
        var outPositions: [SIMD3<Float>] = []
        var outNormals: [SIMD3<Float>] = []
        var outUVs: [SIMD2<Float>] = []
        var materialLibrary: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = parts.first else { continue }
            switch command {
            case "v" where parts.count >= 4:
                positions.append(SIMD3(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0))
            case "vn" where parts.count >= 4:
                sourceNormals.append(SIMD3(Float(parts[1]) ?? 0, Float(parts[2]) ?? 0, Float(parts[3]) ?? 0))
            case "vt" where parts.count >= 3:
                sourceUVs.append(SIMD2(Float(parts[1]) ?? 0, 1 - (Float(parts[2]) ?? 0)))
            case "mtllib" where parts.count >= 2:
                materialLibrary = parts.dropFirst().joined(separator: " ")
            case "f" where parts.count >= 4:
                let face = try parts.dropFirst().map {
                    try parseFaceVertex($0, positions: positions.count, uvs: sourceUVs.count,
                                        normals: sourceNormals.count)
                }
                for corner in 1..<(face.count - 1) {
                    let triangle = [face[0], face[corner], face[corner + 1]]
                    let a = positions[triangle[0].position]
                    let b = positions[triangle[1].position]
                    let c = positions[triangle[2].position]
                    let ab = b - a
                    let ac = c - a
                    let cross = SIMD3<Float>(ab.y * ac.z - ab.z * ac.y,
                                             ab.z * ac.x - ab.x * ac.z,
                                             ab.x * ac.y - ab.y * ac.x)
                    let magnitude = (cross.x * cross.x + cross.y * cross.y + cross.z * cross.z).squareRoot()
                    let faceNormal = magnitude > 0 ? cross / magnitude : SIMD3<Float>(0, 1, 0)
                    for vertex in triangle {
                        outPositions.append(positions[vertex.position])
                        outNormals.append(vertex.normal.map { sourceNormals[$0] } ?? faceNormal)
                        outUVs.append(vertex.uv.map { sourceUVs[$0] } ?? SIMD2<Float>(0, 0))
                    }
                }
            default:
                break
            }
        }

        guard !outPositions.isEmpty else { throw ObjToGlbError.noTriangles }
        let texture = try readTexture(objURL: objURL, materialLibrary: materialLibrary)
        try writeGlb(positions: outPositions, normals: outNormals, uvs: outUVs,
                     texture: texture, destination: destination)
    }

    private static func parseFaceVertex(_ value: String, positions: Int, uvs: Int,
                                        normals: Int) throws -> FaceVertex {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let position = resolveIndex(parts.first ?? "", count: positions) else {
            throw ObjToGlbError.invalidFace(value)
        }
        let uv = parts.count > 1 ? resolveIndex(parts[1], count: uvs) : nil
        let normal = parts.count > 2 ? resolveIndex(parts[2], count: normals) : nil
        return FaceVertex(position: position, uv: uv, normal: normal)
    }

    private static func resolveIndex(_ value: String, count: Int) -> Int? {
        guard let index = Int(value), index != 0 else { return nil }
        let zeroBased = index > 0 ? index - 1 : count + index
        return (0..<count).contains(zeroBased) ? zeroBased : nil
    }

    private static func readTexture(objURL: URL, materialLibrary: String?) throws -> (Data, String)? {
        guard let materialLibrary else { return nil }
        let mtlURL = objURL.deletingLastPathComponent().appendingPathComponent(materialLibrary)
        guard FileManager.default.fileExists(atPath: mtlURL.path) else { return nil }
        let text = try String(contentsOf: mtlURL, encoding: .utf8)
        guard let line = text.components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix("map_Kd ") }) else { return nil }
        // Object Capture's MTL writes a plain map_Kd filename. Complex MTL options are out of scope.
        let fileName = String(line.dropFirst("map_Kd ".count)).trimmingCharacters(in: .whitespaces)
        let url = mtlURL.deletingLastPathComponent().appendingPathComponent(fileName)
        let mime: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "png": mime = "image/png"
        default: throw ObjToGlbError.unsupportedTexture(fileName)
        }
        return (try Data(contentsOf: url), mime)
    }

    private static func writeGlb(positions: [SIMD3<Float>], normals: [SIMD3<Float>],
                                 uvs: [SIMD2<Float>], texture: (Data, String)?,
                                 colors: [SIMD4<Float>]? = nil,
                                 useMipmaps: Bool = true,
                                 destination: URL) throws {
        var binary = Data()
        var views: [[String: Any]] = []
        func appendView(_ data: Data, target: Int? = nil) -> Int {
            while binary.count % 4 != 0 { binary.append(0) }
            let offset = binary.count
            binary.append(data)
            var view: [String: Any] = ["buffer": 0, "byteOffset": offset, "byteLength": data.count]
            if let target { view["target"] = target }
            views.append(view)
            return views.count - 1
        }

        let positionView = appendView(floatData(positions.flatMap { [$0.x, $0.y, $0.z] }), target: 34962)
        let normalView = appendView(floatData(normals.flatMap { [$0.x, $0.y, $0.z] }), target: 34962)
        let uvView = appendView(floatData(uvs.flatMap { [$0.x, $0.y] }), target: 34962)
        let colorView = colors.map { appendView(floatData($0.flatMap { [$0.x, $0.y, $0.z, $0.w] }), target: 34962) }
        let indexView = appendView(uintData(Array(0..<UInt32(positions.count))), target: 34963)
        let imageView = texture.map { appendView($0.0) }
        while binary.count % 4 != 0 { binary.append(0) }

        let minimum: [Float] = [positions.map { $0.x }.min() ?? 0,
                                positions.map { $0.y }.min() ?? 0,
                                positions.map { $0.z }.min() ?? 0]
        let maximum: [Float] = [positions.map { $0.x }.max() ?? 0,
                                positions.map { $0.y }.max() ?? 0,
                                positions.map { $0.z }.max() ?? 0]
        var accessors: [[String: Any]] = [
            ["bufferView": positionView, "componentType": 5126, "count": positions.count,
             "type": "VEC3", "min": minimum, "max": maximum],
            ["bufferView": normalView, "componentType": 5126, "count": normals.count, "type": "VEC3"],
            ["bufferView": uvView, "componentType": 5126, "count": uvs.count, "type": "VEC2"],
            ["bufferView": indexView, "componentType": 5125, "count": positions.count, "type": "SCALAR"],
        ]
        var attributes: [String: Int] = ["POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2]
        if let colors, let colorView {
            attributes["COLOR_0"] = accessors.count
            accessors.append(["bufferView": colorView, "componentType": 5126,
                              "count": colors.count, "type": "VEC4"])
        }
        var pbr: [String: Any] = ["baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0,
                                      "roughnessFactor": 1]
        if texture != nil { pbr["baseColorTexture"] = ["index": 0] }
        var gltf: [String: Any] = [
            "asset": ["version": "2.0", "generator": "BoulderCaptureSpike"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [["mesh": 0]],
            "meshes": [["primitives": [["attributes": attributes,
                                         "indices": 3, "material": 0]]]],
            "materials": [["pbrMetallicRoughness": pbr, "doubleSided": true]],
            "buffers": [["byteLength": binary.count]],
            "bufferViews": views,
            "accessors": accessors,
        ]
        if let texture, let imageView {
            gltf["images"] = [["bufferView": imageView, "mimeType": texture.1]]
            gltf["textures"] = [["source": 0, "sampler": 0]]
            gltf["samplers"] = [["magFilter": 9729,
                                  "minFilter": useMipmaps ? 9987 : 9729,
                                  "wrapS": useMipmaps ? 10497 : 33071,
                                  "wrapT": useMipmaps ? 10497 : 33071]]
        }

        var json = try JSONSerialization.data(withJSONObject: gltf, options: [.sortedKeys])
        while json.count % 4 != 0 { json.append(0x20) }
        var output = Data()
        appendUInt32(0x46546C67, to: &output) // glTF
        appendUInt32(2, to: &output)
        appendUInt32(UInt32(12 + 8 + json.count + 8 + binary.count), to: &output)
        appendUInt32(UInt32(json.count), to: &output)
        appendUInt32(0x4E4F534A, to: &output) // JSON
        output.append(json)
        appendUInt32(UInt32(binary.count), to: &output)
        appendUInt32(0x004E4942, to: &output) // BIN
        output.append(binary)
        try output.write(to: destination, options: .atomic)
    }

    private static func floatData(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values { appendUInt32(value.bitPattern, to: &data) }
        return data
    }

    private static func uintData(_ values: [UInt32]) -> Data {
        var data = Data(capacity: values.count * 4)
        for value in values { appendUInt32(value, to: &data) }
        return data
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
