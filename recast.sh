#!/bin/bash
set -e

KU9="$1"
TVBOX="$2"
OUT="$3"

echo "========================================"
echo "  重铸酷9 - 基于实际仓库结构"
echo "========================================"
echo "酷9: $KU9 (单模块, Java已混淆)"
echo "TVBoxOS: $TVBOX (多模块: app/player/quickjs/pyramid)"
echo "输出: $OUT"
echo ""

# 1. 复制TVBoxOS作为完整骨架
echo "[1/5] 复制TVBoxOS骨架..."
cp -r "$TVBOX" "$OUT"

# 2. 替换酷9的UI资源 (res + assets)
echo "[2/5] 移植酷9 UI资源..."
cp -r "$KU9/app/src/main/res" "$OUT/app/src/main/"
cp -r "$KU9/app/src/main/assets" "$OUT/app/src/main/" 2>/dev/null || true

# 3. 替换AndroidManifest.xml
echo "[3/5] 移植AndroidManifest.xml..."
cp "$KU9/app/src/main/AndroidManifest.xml" "$OUT/app/src/main/"

# 4. 复制酷9的jniLibs和libs (如果有)
echo "[4/5] 移植jniLibs和libs..."
cp -r "$KU9/app/src/main/jniLibs" "$OUT/app/src/main/" 2>/dev/null || true
cp -r "$KU9/app/libs" "$OUT/app/" 2>/dev/null || true

# 5. 处理酷9的混淆Java代码 - 保留备用，但不覆盖TVBoxOS的标准代码
echo "[5/5] 处理Java源码..."
# 将酷9的混淆Java代码保存到单独目录，供后续分析
mkdir -p "$OUT/ku9_obfuscated_java"
cp -r "$KU9/app/src/main/java" "$OUT/ku9_obfuscated_java/" 2>/dev/null || true
# 保留TVBoxOS的标准Java代码不变
echo "  -> TVBoxOS标准Java代码保留在 app/src/main/java/"
echo "  -> 酷9混淆代码备份到 ku9_obfuscated_java/"

# 清理反编译残留 (如果有)
find "$OUT/app/src/main/java" -name "R*.java" -delete 2>/dev/null || true

echo ""
echo "========================================"
echo "  重铸完成！"
echo "========================================"
echo ""
echo "输出目录: $OUT"
echo ""
echo "说明:"
echo "  - 使用TVBoxOS作为骨架 (app/player/quickjs/pyramid)"
echo "  - UI资源 (res/assets) 来自酷9"
echo "  - Java代码使用TVBoxOS标准版本 (因为酷9代码已混淆)"
echo "  - 酷9混淆代码备份在 ku9_obfuscated_java/ 供后续提取特有功能"
echo ""
echo "编译: cd $OUT && ./gradlew :app:assembleJavaDebug"
