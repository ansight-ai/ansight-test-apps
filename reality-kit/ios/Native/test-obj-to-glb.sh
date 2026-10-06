#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/triangle.obj" <<'OBJ'
mtllib triangle.mtl
v 0 0 0
v 1 0 0
v 0 1 0
vt 0 0
vt 1 0
vt 0 1
vn 0 0 1
f 1/1/1 2/2/1 3/3/1
OBJ
cat > "$test_dir/triangle.mtl" <<'MTL'
newmtl rock
map_Kd rock.png
MTL
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9VfV8AAAAASUVORK5CYII=' | base64 -D > "$test_dir/rock.png"
cat > "$test_dir/Main.swift" <<'SWIFT'
import Foundation
@main struct Main {
    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try ObjToGlb.convert(objDirectory: input, destination: output)
    }
}
SWIFT

xcrun swiftc -parse-as-library -module-cache-path "$test_dir/module-cache" \
  "$script_dir/ObjToGlb.swift" "$test_dir/Main.swift" -o "$test_dir/converter"
"$test_dir/converter" "$test_dir" "$test_dir/triangle.glb"
python3 - "$test_dir/triangle.glb" <<'PY'
import json
import pathlib
import struct
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
magic, version, length = struct.unpack_from('<III', data)
assert (magic, version, length) == (0x46546C67, 2, len(data))
json_length, json_type = struct.unpack_from('<II', data, 12)
assert json_type == 0x4E4F534A
model = json.loads(data[20:20 + json_length])
assert model['accessors'][0]['count'] == 3
assert model['accessors'][0]['max'] == [1, 1, 0]
assert model['images'][0]['mimeType'] == 'image/png'
assert model['meshes'][0]['primitives'][0]['indices'] == 3
print('GLB header, mesh, indices, bounds, and embedded texture verified')
PY
