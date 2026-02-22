#!/bin/bash
set -e

APP_NAME="MyMacAnimator"
APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "╔══════════════════════════════════════════╗"
echo "║   Building ${APP_NAME} for macOS         ║"
echo "╚══════════════════════════════════════════╝"

# Очистка
rm -rf "${APP_DIR}"

# Создание структуры .app bundle
echo "→ Creating app bundle structure..."
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"

# Копируем Info.plist
echo "→ Generating Info.plist..."
cp Info.plist "${CONTENTS}/Info.plist"

# Генерация иконки (простой PNG → ICNS)
echo "→ Generating app icon..."
ICONSET="${RESOURCES}/AppIcon.iconset"
mkdir -p "${ICONSET}"

# Создаём иконку программно через sips
# Сначала создадим базовый PNG через Python если доступен
python3 - <<'PYEOF' 2>/dev/null || true
import struct, zlib, os

def create_png(width, height, filename):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    
    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            cx, cy = x - width//2, y - height//2
            dist = (cx*cx + cy*cy) ** 0.5
            r_outer = width * 0.42
            r_inner = width * 0.15
            
            if dist < r_outer:
                t = dist / r_outer
                r = int(40 + 180 * (1 - t))
                g = int(120 + 100 * t)
                b = int(220 - 80 * t)
                a = 255
                
                # Рисуем "A" в центре (animation)
                nx, ny = cx / (width*0.3), cy / (height*0.3)
                if abs(ny) < 0.8:
                    if abs(nx + ny*0.4) < 0.12 or abs(nx - ny*0.4) < 0.12:
                        r, g, b = 255, 255, 255
                    if abs(ny + 0.2) < 0.08 and abs(nx) < 0.25:
                        r, g, b = 255, 255, 255
            else:
                r, g, b, a = 0, 0, 0, 0
            raw += struct.pack('BBBB', r, g, b, a)
    
    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    
    with open(filename, 'wb') as f:
        f.write(sig)
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', zlib.compress(raw, 9)))
        f.write(chunk(b'IEND', b''))

sizes = [16, 32, 64, 128, 256, 512, 1024]
iconset = os.environ.get('ICONSET', 'MyMacAnimator.app/Contents/Resources/AppIcon.iconset')
for s in sizes:
    create_png(s, s, f'{iconset}/icon_{s}x{s}.png')
    if s <= 512:
        create_png(s*2, s*2, f'{iconset}/icon_{s}x{s}@2x.png')

print("Icons generated successfully")
PYEOF

# Конвертируем iconset в icns (если iconutil доступен)
if [ -d "${ICONSET}" ] && command -v iconutil &> /dev/null; then
    iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns" 2>/dev/null || true
    rm -rf "${ICONSET}"
    echo "  ✓ AppIcon.icns created"
else
    echo "  ⚠ Skipping icon generation (iconutil not found or icons missing)"
fi

# Компиляция
echo "→ Compiling source code..."
clang++ -std=c++17 \
    -framework Cocoa \
    -framework QuartzCore \
    -framework CoreGraphics \
    -framework CoreVideo \
    -framework AVFoundation \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    -fobjc-arc \
    -O2 \
    -Wno-deprecated-declarations \
    -o "${MACOS}/${APP_NAME}" \
    main.mm

echo "  ✓ Compilation successful"

# Подпись (ad-hoc для локального запуска)
echo "→ Code signing (ad-hoc)..."
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
echo "  ✓ Signed"

# Информация
BINARY_SIZE=$(du -sh "${MACOS}/${APP_NAME}" | cut -f1)
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Build Complete!                        ║"
echo "║   Binary size: ${BINARY_SIZE}                    ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Run:  open ${APP_DIR}"
echo "  or: ./${MACOS}/${APP_NAME}"
echo ""

# Запускаем
read -p "Launch now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "${APP_DIR}"
fi