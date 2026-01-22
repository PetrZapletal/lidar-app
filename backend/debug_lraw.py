#!/usr/bin/env python3
"""
Debug script for LRAW parsing
"""
import struct
import sys
from pathlib import Path


def debug_lraw(filepath):
    """Parse LRAW with detailed position tracking"""
    with open(filepath, 'rb') as f:
        file_size = f.seek(0, 2)
        f.seek(0)
        print(f"File size: {file_size:,} bytes ({file_size/1024/1024:.2f} MB)")
        print()

        # Header (32 bytes)
        print("=" * 60)
        print("HEADER (32 bytes)")
        print("=" * 60)
        magic = f.read(4)
        print(f"  Magic: {magic} (expected: b'LRAW')")

        version = struct.unpack('<H', f.read(2))[0]
        flags = struct.unpack('<H', f.read(2))[0]
        mesh_count = struct.unpack('<I', f.read(4))[0]
        texture_count = struct.unpack('<I', f.read(4))[0]
        depth_count = struct.unpack('<I', f.read(4))[0]
        reserved = f.read(12)

        print(f"  Version: {version}")
        print(f"  Flags: 0x{flags:04x}")
        print(f"    - HAS_CLASSIFICATIONS: {bool(flags & 0x01)}")
        print(f"    - HAS_CONFIDENCE_MAPS: {bool(flags & 0x02)}")
        print(f"    - HAS_TEXTURE_FRAMES: {bool(flags & 0x04)}")
        print(f"    - HAS_DEPTH_FRAMES: {bool(flags & 0x08)}")
        print(f"  Mesh count: {mesh_count}")
        print(f"  Texture count: {texture_count}")
        print(f"  Depth count: {depth_count}")
        print(f"  Current position: {f.tell()}")
        print()

        # Parse mesh anchors
        print("=" * 60)
        print(f"MESH ANCHORS ({mesh_count})")
        print("=" * 60)

        for i in range(mesh_count):
            pos_start = f.tell()
            print(f"\n  Mesh {i} @ position {pos_start}")

            # UUID
            uuid = f.read(16)
            if len(uuid) < 16:
                print(f"    ERROR: Incomplete UUID, got {len(uuid)} bytes")
                break
            print(f"    UUID: {uuid.hex()[:32]}...")

            # Transform
            transform_data = f.read(64)
            if len(transform_data) < 64:
                print(f"    ERROR: Incomplete transform, got {len(transform_data)} bytes")
                break
            print(f"    Transform: 64 bytes read")

            # Vertex count
            vc_data = f.read(4)
            if len(vc_data) < 4:
                print(f"    ERROR: Incomplete vertex count, got {len(vc_data)} bytes")
                break
            vertex_count = struct.unpack('<I', vc_data)[0]
            print(f"    Vertex count: {vertex_count}")

            # Sanity check
            if vertex_count > 1_000_000:
                print(f"    WARNING: Vertex count seems too large!")
                print(f"    Raw bytes: {vc_data.hex()}")
                print(f"    Position: {f.tell() - 4}")
                # Show surrounding bytes
                f.seek(f.tell() - 20)
                context = f.read(40)
                print(f"    Context (-20 to +20): {context.hex()}")
                return

            # Face count
            fc_data = f.read(4)
            face_count = struct.unpack('<I', fc_data)[0]
            print(f"    Face count: {face_count}")

            # Classification flag
            class_flag = struct.unpack('<B', f.read(1))[0]
            print(f"    Has classification: {class_flag}")

            # Calculate expected sizes
            # NOTE: iOS simd types are 16 bytes due to SIMD alignment!
            SIMD_STRIDE = 16
            vertices_size = vertex_count * SIMD_STRIDE
            normals_size = vertex_count * SIMD_STRIDE
            faces_size = face_count * SIMD_STRIDE  # simd_uint3 is also 16 bytes

            print(f"    Expected vertices size: {vertices_size:,} bytes (stride=16)")
            print(f"    Expected normals size: {normals_size:,} bytes (stride=16)")
            print(f"    Expected faces size: {faces_size:,} bytes")

            total_expected = vertices_size + normals_size + faces_size
            if class_flag:
                total_expected += face_count  # Classifications are per-face
            print(f"    Total data expected: {total_expected:,} bytes")

            # Read vertices
            vertices = f.read(vertices_size)
            print(f"    Vertices read: {len(vertices):,} bytes")

            # Read normals
            normals = f.read(normals_size)
            print(f"    Normals read: {len(normals):,} bytes")

            # Read faces
            faces = f.read(faces_size)
            print(f"    Faces read: {len(faces):,} bytes")

            # Read classifications (per-face, not per-vertex!)
            if class_flag:
                classifications = f.read(face_count)  # Classifications are per-face
                print(f"    Classifications read: {len(classifications):,} bytes (per-face)")

            pos_end = f.tell()
            print(f"    Mesh size: {pos_end - pos_start:,} bytes")
            print(f"    End position: {pos_end}")

        # Parse texture frames
        print()
        print("=" * 60)
        print(f"TEXTURE FRAMES ({texture_count})")
        print("=" * 60)

        for i in range(min(texture_count, 3)):  # Only show first 3
            pos_start = f.tell()
            print(f"\n  Texture {i} @ position {pos_start}")

            uuid = f.read(16)
            if len(uuid) < 16:
                print(f"    ERROR: Incomplete UUID")
                break

            timestamp = struct.unpack('<d', f.read(8))[0]
            print(f"    Timestamp: {timestamp}")

            transform = f.read(64)
            intrinsics = f.read(48)  # simd_float3x3 = 48 bytes

            width = struct.unpack('<I', f.read(4))[0]
            height = struct.unpack('<I', f.read(4))[0]
            print(f"    Resolution: {width}x{height}")

            image_length = struct.unpack('<I', f.read(4))[0]
            print(f"    Image length: {image_length:,} bytes")

            image_data = f.read(image_length)
            print(f"    Image read: {len(image_data):,} bytes")

            # Check JPEG magic
            if image_data[:2] == b'\xff\xd8':
                print(f"    Format: JPEG")
            elif image_data[:4] == b'\x00\x00\x00\x0c':
                print(f"    Format: HEIC")
            else:
                print(f"    Format: Unknown (first bytes: {image_data[:4].hex()})")

            pos_end = f.tell()
            print(f"    Frame size: {pos_end - pos_start:,} bytes")

        if texture_count > 3:
            print(f"\n  ... and {texture_count - 3} more texture frames")
            # Skip remaining textures
            for i in range(3, texture_count):
                f.read(16)  # UUID
                f.read(8)   # timestamp
                f.read(64)  # transform
                f.read(36)  # intrinsics
                f.read(8)   # width+height
                img_len = struct.unpack('<I', f.read(4))[0]
                f.read(img_len)

        # Parse depth frames
        print()
        print("=" * 60)
        print(f"DEPTH FRAMES ({depth_count})")
        print("=" * 60)

        has_confidence = bool(flags & 0x02)

        for i in range(min(depth_count, 3)):  # Only show first 3
            pos_start = f.tell()
            print(f"\n  Depth {i} @ position {pos_start}")

            uuid = f.read(16)
            if len(uuid) < 16:
                print(f"    ERROR: Incomplete UUID")
                break

            timestamp = struct.unpack('<d', f.read(8))[0]
            print(f"    Timestamp: {timestamp}")

            transform = f.read(64)
            intrinsics = f.read(48)  # simd_float3x3 = 48 bytes

            width = struct.unpack('<I', f.read(4))[0]
            height = struct.unpack('<I', f.read(4))[0]
            print(f"    Resolution: {width}x{height}")

            depth_size = width * height * 4
            print(f"    Expected depth size: {depth_size:,} bytes")

            depth_data = f.read(depth_size)
            print(f"    Depth read: {len(depth_data):,} bytes")

            if has_confidence:
                conf_size = width * height
                conf_data = f.read(conf_size)
                print(f"    Confidence read: {len(conf_data):,} bytes")

            pos_end = f.tell()
            print(f"    Frame size: {pos_end - pos_start:,} bytes")

        print()
        print("=" * 60)
        print(f"Final position: {f.tell():,} / {file_size:,} bytes")
        remaining = file_size - f.tell()
        print(f"Remaining: {remaining:,} bytes")


if __name__ == '__main__':
    if len(sys.argv) > 1:
        filepath = sys.argv[1]
    else:
        # Default path
        filepath = "/data/scans/raw_scans/204a0613-2e89-4a2b-b604-f55cac42f2dd/raw_data.lraw"

    if not Path(filepath).exists():
        print(f"File not found: {filepath}")
        sys.exit(1)

    debug_lraw(filepath)
